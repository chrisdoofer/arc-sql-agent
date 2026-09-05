using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AnalysisServices.AdomdClient;
using Microsoft.AnalysisServices.Tabular;

const string MappingTableName = "dim_linux_patch_cve_mapping";
const string BasePartitionName = "dim_linux_patch_cve_mapping";
const string TemporaryTablePrefix = "__linux_cve_synthetic_";

var options = Options.Parse(args);
var fixtures = LoadFixtures(options.FixturePath)
    .Where(fixture => options.FixtureNames.Count == 0 || options.FixtureNames.Contains(fixture.Name, StringComparer.OrdinalIgnoreCase))
    .ToList();

if (fixtures.Count == 0)
{
    throw new InvalidOperationException("No synthetic fixtures matched the requested selection.");
}

var port = options.Port ?? DiscoverPowerBiPort();
using var server = new Server();
server.Connect($"Data Source=localhost:{port}");

var database = server.Databases
    .Cast<Database>()
    .SingleOrDefault(candidate => candidate.Model.Tables.Find(MappingTableName) is not null)
    ?? throw new InvalidOperationException($"No Power BI Desktop model on port {port} contains '{MappingTableName}'.");

Console.WriteLine($"Model: {database.Name} on localhost:{port}");
RemoveStaleTemporaryTables(database);

var baseline = ModelSnapshot.Capture(database);
var failures = new List<string>();

if (options.Mode.Equals("semantic", StringComparison.OrdinalIgnoreCase))
{
    try
    {
        RunSemanticFixtureSuite(database, port, fixtures);
        foreach (var fixture in fixtures)
        {
            Console.WriteLine($"PASS {fixture.Name}: semantic exposure path");
        }
    }
    catch (Exception exception)
    {
        failures.Add($"semantic suite: {exception.Message}");
        Console.Error.WriteLine($"FAIL semantic suite: {exception}");
    }
}
else if (options.Mode.Equals("live-provider", StringComparison.OrdinalIgnoreCase))
{
    foreach (var fixture in fixtures)
    {
        try
        {
            RunLiveProviderFixture(database, port, fixture);
            Console.WriteLine($"PASS {fixture.Name}: {fixture.ExpectedAdvisory} / {fixture.ExpectedCve}");
        }
        catch (Exception exception)
        {
            failures.Add($"{fixture.Name}: {exception.Message}");
            Console.Error.WriteLine($"FAIL {fixture.Name}: {exception}");
        }
    }
}
else
{
    failures.Add($"Unsupported validation mode '{options.Mode}'.");
}

RemoveStaleTemporaryTables(database);
var finalSnapshot = ModelSnapshot.Capture(database);
if (!baseline.Equals(finalSnapshot))
{
    failures.Add("The production model metadata changed during synthetic validation.");
}

if (failures.Count > 0)
{
    throw new InvalidOperationException(
        "Synthetic Linux CVE validation failed:" + Environment.NewLine +
        string.Join(Environment.NewLine, failures.Select(failure => $" - {failure}")));
}

Console.WriteLine($"All {fixtures.Count} Linux CVE fixtures passed; temporary tables were removed.");

static List<Fixture> LoadFixtures(string fixturePath)
{
    var json = File.ReadAllText(fixturePath);
    return System.Text.Json.JsonSerializer.Deserialize<List<Fixture>>(json, new JsonSerializerOptions
    {
        PropertyNameCaseInsensitive = true
    }) ?? throw new InvalidOperationException($"No fixtures were found in '{fixturePath}'.");
}

static int DiscoverPowerBiPort()
{
    var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
    var roots = new[]
    {
        Path.Combine(localAppData, "Microsoft", "Power BI Desktop", "AnalysisServicesWorkspaces"),
        Path.Combine(localAppData, "Packages", "Microsoft.MicrosoftPowerBIDesktop_8wekyb3d8bbwe", "LocalState", "AnalysisServicesWorkspaces")
    };

    var candidates = roots
        .Where(Directory.Exists)
        .SelectMany(root => Directory.EnumerateFiles(root, "msmdsrv.port.txt", SearchOption.AllDirectories))
        .Select(File.ReadAllText)
        .Select(value => int.TryParse(value.Trim(), out var parsed) ? parsed : 0)
        .Where(value => value > 0)
        .Distinct()
        .OrderByDescending(value => value)
        .ToList();

    foreach (var candidate in candidates)
    {
        try
        {
            using var probe = new Server();
            probe.Connect($"Data Source=localhost:{candidate};Timeout=5");
            if (probe.Databases.Cast<Database>().Any(database => database.Model.Tables.Find(MappingTableName) is not null))
            {
                return candidate;
            }
        }
        catch
        {
            // Stale Power BI workspace port files are expected after Desktop exits.
        }
    }

    throw new InvalidOperationException("No running Power BI Desktop model containing the Linux CVE mapping table was found. Open the template or pass --port.");
}

static void RunSemanticFixtureSuite(Database database, int port, IReadOnlyList<Fixture> fixtures)
{
    const string missingTableName = TemporaryTablePrefix + "missing";
    const string mappingTableName = TemporaryTablePrefix + "mapping";
    const string exposureTableName = TemporaryTablePrefix + "exposure";

    try
    {
        var missingTable = CreateImportTable(
            missingTableName,
            $"let Source = {BuildSyntheticMissingPatchesTable(fixtures)} in Source",
            MissingPatchColumns());
        var mappingTable = CreateImportTable(
            mappingTableName,
            $"let Source = {BuildSyntheticMappingTable(fixtures)} in Source",
            MappingColumns());

        database.Model.Tables.Add(missingTable);
        database.Model.Tables.Add(mappingTable);
        database.Model.SaveChanges();
        missingTable.RequestRefresh(RefreshType.Full);
        mappingTable.RequestRefresh(RefreshType.Full);
        database.Model.SaveChanges();

        var productionExposure = database.Model.Tables.Find("view_patch_cve_mappings")
            ?? throw new InvalidOperationException("Table 'view_patch_cve_mappings' was not found.");
        var productionPartition = productionExposure.Partitions.FirstOrDefault()?.Source as CalculatedPartitionSource
            ?? throw new InvalidOperationException("Table 'view_patch_cve_mappings' is not calculated.");
        var expression = Regex.Replace(productionPartition.Expression, @"\bview_missing_patches\b", missingTableName);
        expression = Regex.Replace(expression, @"\bdim_linux_patch_cve_mapping\b", mappingTableName);

        var exposureTable = new Table
        {
            Name = exposureTableName,
            IsHidden = true,
            Description = "Temporary synthetic Linux CVE exposure validation table. Removed automatically."
        };
        foreach (var sourceColumn in productionExposure.Columns.Cast<Column>().Where(column => !column.Name.StartsWith("RowNumber-", StringComparison.Ordinal)))
        {
            exposureTable.Columns.Add(new CalculatedTableColumn
            {
                Name = sourceColumn.Name,
                SourceColumn = sourceColumn.Name,
                DataType = sourceColumn.DataType,
                IsHidden = true,
                SummarizeBy = sourceColumn.SummarizeBy
            });
        }
        exposureTable.Partitions.Add(new Partition
        {
            Name = exposureTableName,
            Mode = ModeType.Import,
            Source = new CalculatedPartitionSource { Expression = expression }
        });

        database.Model.Tables.Add(exposureTable);
        database.Model.SaveChanges();
        database.Model.RequestRefresh(RefreshType.Calculate);
        database.Model.SaveChanges();
        exposureTable = database.Model.Tables.Find(exposureTableName)
            ?? throw new InvalidOperationException("The temporary calculated exposure table disappeared during refresh.");
        var exposurePartition = exposureTable.Partitions.First();
        if (exposurePartition.State == ObjectState.SemanticError || !string.IsNullOrWhiteSpace(exposurePartition.ErrorMessage))
        {
            throw new InvalidOperationException($"Temporary calculated exposure expression failed: {exposurePartition.ErrorMessage}");
        }

        var rows = QueryExposureRows(port, database.Name, exposureTableName);
        if (rows.Count != fixtures.Count)
        {
            throw new InvalidOperationException(
                $"The calculated exposure table returned {rows.Count} rows for {fixtures.Count} fixtures; expected exactly one row per fixture.");
        }

        foreach (var fixture in fixtures)
        {
            var expectedMachineName = $"synthetic-{fixture.Name}";
            var matches = rows.Count(row =>
                row.MachineName.Equals(expectedMachineName, StringComparison.OrdinalIgnoreCase) &&
                row.PackageName.Equals(fixture.PackageName, StringComparison.OrdinalIgnoreCase) &&
                row.PackageVersion.Equals(fixture.PackageVersion, StringComparison.Ordinal) &&
                row.AdvisoryId.Equals(fixture.ExpectedAdvisory, StringComparison.OrdinalIgnoreCase) &&
                row.CveId.Equals(fixture.ExpectedCve, StringComparison.OrdinalIgnoreCase) &&
                row.MappingSource.Equals(fixture.ExpectedMappingSource, StringComparison.OrdinalIgnoreCase) &&
                row.Confidence.Equals(fixture.ExpectedConfidence, StringComparison.OrdinalIgnoreCase));
            if (matches != 1)
            {
                throw new InvalidOperationException(
                    $"The calculated exposure table returned {matches} matching rows for '{fixture.Name}'; expected exactly one.");
            }
        }
    }
    finally
    {
        RemoveStaleTemporaryTables(database);
    }
}

static void RunLiveProviderFixture(Database database, int port, Fixture fixture)
{
    var temporaryTableName = TemporaryTablePrefix + Regex.Replace(fixture.Name, "[^A-Za-z0-9_]", "_");
    var temporaryTable = database.Model.Tables.Find(temporaryTableName);
    if (temporaryTable is not null)
    {
        database.Model.Tables.Remove(temporaryTable);
        database.Model.SaveChanges();
    }

    var expression = BuildFixtureExpression(database, fixture);
    temporaryTable = CreateTemporaryTable(temporaryTableName, expression);

    try
    {
        database.Model.Tables.Add(temporaryTable);
        database.Model.SaveChanges();
        temporaryTable.RequestRefresh(RefreshType.Full);
        database.Model.SaveChanges();

        var rows = QueryRows(port, database.Name, temporaryTableName);
        var match = rows.Any(row =>
            row.AdvisoryId.Equals(fixture.ExpectedAdvisory, StringComparison.OrdinalIgnoreCase) &&
            row.CveId.Equals(fixture.ExpectedCve, StringComparison.OrdinalIgnoreCase) &&
            row.MappingSource.Equals(fixture.ExpectedMappingSource, StringComparison.OrdinalIgnoreCase) &&
            row.PackageName.Equals(fixture.PackageName, StringComparison.OrdinalIgnoreCase) &&
            row.PackageVersion.Equals(fixture.PackageVersion, StringComparison.Ordinal));

        if (!match)
        {
            var observed = rows.Count == 0
                ? "no mapping rows"
                : string.Join(", ", rows.Take(5).Select(row => $"{row.AdvisoryId}/{row.CveId}/{row.MappingSource}"));
            throw new InvalidOperationException($"Expected mapping was not returned; observed {observed}.");
        }
    }
    finally
    {
        var existing = database.Model.Tables.Find(temporaryTableName);
        if (existing is not null)
        {
            database.Model.Tables.Remove(existing);
            database.Model.SaveChanges();
        }
    }
}

static string BuildFixtureExpression(Database database, Fixture fixture)
{
    var syntheticTable = BuildSyntheticMissingPatchesTable([fixture]);

    if (fixture.Provider.Equals("function", StringComparison.OrdinalIgnoreCase))
    {
        if (string.IsNullOrWhiteSpace(fixture.FunctionName) || database.Model.Expressions.Find(fixture.FunctionName) is null)
        {
            throw new InvalidOperationException($"Named expression '{fixture.FunctionName}' was not found.");
        }

        return $"""
            let
                SyntheticMissingPatches = {syntheticTable},
                Rows = {fixture.FunctionName}(SyntheticMissingPatches),
                Source = Table.FromRecords(Rows, {MappingTableType()})
            in
                Source
            """;
    }

    if (!fixture.Provider.Equals("base-partition", StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException($"Unsupported fixture provider '{fixture.Provider}'.");
    }

    const string mappingTableName = "dim_linux_patch_cve_mapping";
    var mappingTable = database.Model.Tables.Find(mappingTableName)
        ?? throw new InvalidOperationException($"Table '{mappingTableName}' was not found.");
    var partition = mappingTable.Partitions.Find(BasePartitionName)
        ?? throw new InvalidOperationException($"Partition '{BasePartitionName}' was not found.");
    var source = partition.Source as MPartitionSource
        ?? throw new InvalidOperationException($"Partition '{BasePartitionName}' is not an M partition.");

    var expression = Regex.Replace(source.Expression, @"\bview_missing_patches\b", "SyntheticMissingPatches");
    var letMatch = Regex.Match(expression, @"^\s*let\b", RegexOptions.IgnoreCase);
    if (!letMatch.Success)
    {
        throw new InvalidOperationException("The base Linux mapping partition does not begin with a Power Query let expression.");
    }

    return expression.Insert(
        letMatch.Index + letMatch.Length,
        Environment.NewLine + $"    SyntheticMissingPatches = {syntheticTable},");
}

static string BuildSyntheticMissingPatchesTable(IEnumerable<Fixture> fixtures)
{
    var rows = fixtures.Select(fixture =>
    {
        var values = new[]
        {
            $"/synthetic/{fixture.Name}",
            $"synthetic-{fixture.Name}",
            fixture.PackageName,
            fixture.PackageName,
            "",
            "Security",
            "Linux",
            fixture.Distribution.Equals("SUSE Linux Enterprise Server", StringComparison.OrdinalIgnoreCase) ? "Zypper" :
                fixture.Distribution.Equals("Ubuntu", StringComparison.OrdinalIgnoreCase) ||
                fixture.Distribution.Equals("Debian GNU/Linux", StringComparison.OrdinalIgnoreCase) ? "Apt" : "Yum",
            fixture.Distribution,
            fixture.Release,
            fixture.PackageVersion,
            "NeverReboots",
            null,
            "synthetic-subscription",
            "synthetic-resource-group",
            "synthetic-tenant",
            "0"
        };
        return "{ " + string.Join(
            ", ",
            values.Select((value, index) =>
                index == 12 ? "#datetime(2026, 8, 11, 0, 0, 0)" :
                index == 16 ? "0" :
                MString(value ?? ""))) + " }";
    });
    var rowList = string.Join("," + Environment.NewLine + "                ", rows);

    return $$"""
        #table(
            type table [
                machine_resource_id = text,
                machine_name = text,
                patch_id = text,
                patch_name = text,
                kb_id = text,
                classification = text,
                os_type = text,
                patch_service_used = text,
                os_distribution = text,
                release_codename = text,
                package_version = text,
                reboot_behavior = text,
                assessment_time = datetime,
                subscription_id = text,
                resource_group = text,
                tenant_id = text,
                resource_key = Int64.Type
            ],
            {
                {{rowList}}
            }
        )
        """;
}

static string BuildSyntheticMappingTable(IEnumerable<Fixture> fixtures)
{
    var rows = fixtures.Select(fixture =>
        "{ " + string.Join(", ",
            MString(fixture.Distribution),
            MString(fixture.Release),
            MString(fixture.PackageName),
            MString(fixture.PackageVersion),
            MString(fixture.ExpectedAdvisory),
            MString(fixture.ExpectedCve),
            MString("Important"),
            MString($"Synthetic {fixture.Distribution} advisory"),
            "#datetime(2026, 8, 11, 0, 0, 0)",
            MString(fixture.ExpectedMappingSource),
            MString($"https://synthetic.invalid/{fixture.Name}")) + " }");
    var rowList = string.Join("," + Environment.NewLine + "                ", rows);

    return $$"""
        #table(
            {{MappingTableType()}},
            {
                {{rowList}}
            }
        )
        """;
}

static Table CreateImportTable(string name, string expression, IReadOnlyList<(string Name, DataType DataType)> columns)
{
    var table = new Table
    {
        Name = name,
        IsHidden = true,
        Description = "Temporary synthetic Linux CVE validation table. Removed automatically."
    };

    foreach (var column in columns)
    {
        table.Columns.Add(new DataColumn
        {
            Name = column.Name,
            SourceColumn = column.Name,
            DataType = column.DataType,
            IsHidden = true,
            SummarizeBy = column.DataType == DataType.String ? AggregateFunction.None : AggregateFunction.Default
        });
    }

    table.Partitions.Add(new Partition
    {
        Name = name,
        Mode = ModeType.Import,
        Source = new MPartitionSource { Expression = expression }
    });

    return table;
}

static Table CreateTemporaryTable(string name, string expression) =>
    CreateImportTable(name, expression, MappingColumns());

static List<MappingRow> QueryRows(int port, string databaseName, string tableName)
{
    using var connection = new AdomdConnection($"Data Source=localhost:{port};Initial Catalog={databaseName}");
    connection.Open();
    using var command = connection.CreateCommand();
    command.CommandText = $"""
        EVALUATE
        SELECTCOLUMNS(
            '{tableName.Replace("'", "''")}',
            "package_name", [package_name],
            "package_version", [package_version],
            "advisory_id", [advisory_id],
            "cve_id", [cve_id],
            "mapping_source", [mapping_source]
        )
        """;
    command.CommandTimeout = 30;

    using var reader = command.ExecuteReader();
    var rows = new List<MappingRow>();
    while (reader.Read())
    {
        rows.Add(new MappingRow(
            Convert.ToString(reader.GetValue(0)) ?? "",
            Convert.ToString(reader.GetValue(1)) ?? "",
            Convert.ToString(reader.GetValue(2)) ?? "",
            Convert.ToString(reader.GetValue(3)) ?? "",
            Convert.ToString(reader.GetValue(4)) ?? ""));
    }

    return rows;
}

static List<ExposureRow> QueryExposureRows(int port, string databaseName, string tableName)
{
    using var connection = new AdomdConnection($"Data Source=localhost:{port};Initial Catalog={databaseName}");
    connection.Open();
    using var command = connection.CreateCommand();
    command.CommandText = $"""
        EVALUATE
        SELECTCOLUMNS(
            '{tableName.Replace("'", "''")}',
            "machine_name", [machine_name],
            "package_name", [patch_name],
            "package_version", [package_version],
            "advisory_id", [advisory_reference],
            "cve_id", [cve_id],
            "mapping_source", [mapping_source],
            "confidence", [confidence]
        )
        """;
    command.CommandTimeout = 30;

    using var reader = command.ExecuteReader();
    var rows = new List<ExposureRow>();
    while (reader.Read())
    {
        rows.Add(new ExposureRow(
            Convert.ToString(reader.GetValue(0)) ?? "",
            Convert.ToString(reader.GetValue(1)) ?? "",
            Convert.ToString(reader.GetValue(2)) ?? "",
            Convert.ToString(reader.GetValue(3)) ?? "",
            Convert.ToString(reader.GetValue(4)) ?? "",
            Convert.ToString(reader.GetValue(5)) ?? "",
            Convert.ToString(reader.GetValue(6)) ?? ""));
    }

    return rows;
}

static void RemoveStaleTemporaryTables(Database database)
{
    var staleTables = database.Model.Tables
        .Cast<Table>()
        .Where(table => table.Name.StartsWith(TemporaryTablePrefix, StringComparison.Ordinal))
        .OrderByDescending(table => table.Name.EndsWith("_exposure", StringComparison.Ordinal))
        .ToList();

    if (staleTables.Count == 0)
    {
        return;
    }

    foreach (var table in staleTables)
    {
        database.Model.Tables.Remove(table);
    }

    database.Model.SaveChanges();
}

static string MappingTableType() =>
    "type table [distribution = text, release_codename = text, package_name = text, package_version = text, advisory_id = text, cve_id = text, severity = text, product = text, published_at = nullable datetime, mapping_source = text, source_url = text]";

static IReadOnlyList<(string Name, DataType DataType)> MappingColumns() =>
[
    ("distribution", DataType.String),
    ("release_codename", DataType.String),
    ("package_name", DataType.String),
    ("package_version", DataType.String),
    ("advisory_id", DataType.String),
    ("cve_id", DataType.String),
    ("severity", DataType.String),
    ("product", DataType.String),
    ("published_at", DataType.DateTime),
    ("mapping_source", DataType.String),
    ("source_url", DataType.String)
];

static IReadOnlyList<(string Name, DataType DataType)> MissingPatchColumns() =>
[
    ("machine_resource_id", DataType.String),
    ("machine_name", DataType.String),
    ("patch_id", DataType.String),
    ("patch_name", DataType.String),
    ("kb_id", DataType.String),
    ("classification", DataType.String),
    ("os_type", DataType.String),
    ("patch_service_used", DataType.String),
    ("os_distribution", DataType.String),
    ("release_codename", DataType.String),
    ("package_version", DataType.String),
    ("reboot_behavior", DataType.String),
    ("assessment_time", DataType.DateTime),
    ("subscription_id", DataType.String),
    ("resource_group", DataType.String),
    ("tenant_id", DataType.String),
    ("resource_key", DataType.Int64)
];

static string MString(string value) => "\"" + value.Replace("\"", "\"\"") + "\"";

sealed record Fixture(
    string Name,
    string Provider,
    string? FunctionName,
    string Distribution,
    string Release,
    string PackageName,
    string PackageVersion,
    string ExpectedAdvisory,
    string ExpectedCve,
    string ExpectedMappingSource,
    string ExpectedConfidence);

sealed record MappingRow(
    string PackageName,
    string PackageVersion,
    string AdvisoryId,
    string CveId,
    string MappingSource);

sealed record ExposureRow(
    string MachineName,
    string PackageName,
    string PackageVersion,
    string AdvisoryId,
    string CveId,
    string MappingSource,
    string Confidence);

sealed record ModelSnapshot(
    int TableCount,
    int RelationshipCount,
    int MeasureCount,
    string NamedExpressionsHash,
    string LinuxPartitionsHash)
{
    public static ModelSnapshot Capture(Database database)
    {
        var namedExpressions = string.Join(
            "\n",
            database.Model.Expressions
                .Cast<NamedExpression>()
                .OrderBy(expression => expression.Name, StringComparer.Ordinal)
                .Select(expression => $"{expression.Name}\n{expression.Expression}"));
        const string mappingTableName = "dim_linux_patch_cve_mapping";
        var mappingTable = database.Model.Tables.Find(mappingTableName)
            ?? throw new InvalidOperationException($"Table '{mappingTableName}' was not found.");
        var partitions = string.Join(
            "\n",
            mappingTable.Partitions
                .Cast<Partition>()
                .OrderBy(partition => partition.Name, StringComparer.Ordinal)
                .Select(partition => $"{partition.Name}\n{(partition.Source as MPartitionSource)?.Expression}"));

        return new ModelSnapshot(
            database.Model.Tables.Count,
            database.Model.Relationships.Count,
            database.Model.Tables.Cast<Table>().Sum(table => table.Measures.Count),
            Hash(namedExpressions),
            Hash(partitions));
    }

    private static string Hash(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}

sealed record Options(int? Port, string FixturePath, IReadOnlyList<string> FixtureNames, string Mode)
{
    public static Options Parse(string[] arguments)
    {
        int? port = null;
        string? fixturePath = null;
        var fixtureNames = new List<string>();
        var mode = "semantic";

        for (var index = 0; index < arguments.Length; index++)
        {
            switch (arguments[index])
            {
                case "--port":
                    port = int.Parse(arguments[++index]);
                    break;
                case "--fixtures":
                    fixturePath = Path.GetFullPath(arguments[++index]);
                    break;
                case "--fixture":
                    fixtureNames.Add(arguments[++index]);
                    break;
                case "--mode":
                    mode = arguments[++index];
                    break;
                default:
                    throw new ArgumentException($"Unknown argument '{arguments[index]}'.");
            }
        }

        fixturePath ??= Path.Combine(AppContext.BaseDirectory, "fixtures.json");
        return new Options(port, fixturePath, fixtureNames, mode);
    }
}
