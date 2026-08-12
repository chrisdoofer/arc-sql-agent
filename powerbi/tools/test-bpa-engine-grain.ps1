[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$powerBiRoot = Split-Path -Parent $PSScriptRoot
$bimPath = Join-Path $powerBiRoot 'ArcSqlEstate.bim'
$layoutBuilderPath = Join-Path $PSScriptRoot 'build-layout.mjs'
$model = Get-Content -Raw -Encoding utf8 $bimPath | ConvertFrom-Json -Depth 100

$findingsTable = $model.model.tables | Where-Object name -eq 'view_best_practice_findings'
$partitionExpression = $findingsTable.partitions[0].source.expression -join "`n"
$requiredFilter = 'LOWER ( TRIM ( COALESCE ( ext_arc_sql_instances[service_type], "" ) ) ) = "engine"'
if (-not $partitionExpression.Contains($requiredFilter)) {
    throw 'Best-practice instance findings are not restricted to normalized Database Engine resources.'
}

$measure = ($model.model.tables | Where-Object name -eq 'all_measures').measures |
    Where-Object name -eq 'kpi_bpa_engine_instance_count'
if ($null -eq $measure -or -not $measure.expression.Contains('view_sql_instances[service_type]')) {
    throw 'The Best Practices page engine-population measure is missing or does not filter service type.'
}

$layoutBuilder = Get-Content -Raw -Encoding utf8 $layoutBuilderPath
if (-not $layoutBuilder.Contains('all_measures.kpi_bpa_engine_instance_count')) {
    throw 'The Best Practices population card is not bound to the engine-only measure.'
}

$mixedFixture = @(
    [pscustomobject]@{ resource_key = 'engine-1'; service_type = 'Engine' },
    [pscustomobject]@{ resource_key = 'engine-2'; service_type = ' engine ' },
    [pscustomobject]@{ resource_key = 'ssis-1'; service_type = 'SSIS' },
    [pscustomobject]@{ resource_key = 'ssis-2'; service_type = 'Integration Services' },
    [pscustomobject]@{ resource_key = 'unknown-1'; service_type = $null },
    [pscustomobject]@{ resource_key = $null; service_type = 'Engine' }
)

$engineResources = @(
    $mixedFixture | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.resource_key) -and
        ([string]$_.service_type).Trim().ToLowerInvariant() -eq 'engine'
    }
)
if ($engineResources.Count -ne 2) {
    throw "Expected 2 Database Engine resources in the mixed fixture; found $($engineResources.Count)."
}

$engineChecks = @('INST-01', 'SEC-01', 'HADR-01', 'INST-11', 'COVERAGE-01')
$findingCount = $engineResources.Count * $engineChecks.Count
if ($findingCount -ne 10) {
    throw "Expected 10 engine-level findings in the mixed fixture; found $findingCount."
}

$withAdditionalSsis = $mixedFixture + [pscustomobject]@{
    resource_key = 'ssis-3'
    service_type = 'SSIS'
}
$engineCountWithAdditionalSsis = @(
    $withAdditionalSsis | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.resource_key) -and
        ([string]$_.service_type).Trim().ToLowerInvariant() -eq 'engine'
    }
).Count
if ($engineCountWithAdditionalSsis -ne $engineResources.Count) {
    throw 'Adding an SSIS resource changed the Database Engine assessment population.'
}

Write-Host 'PASS: mixed Engine/SSIS resources preserve the engine-only BPA population and finding count.'
