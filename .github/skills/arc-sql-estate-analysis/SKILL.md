---
name: arc-sql-estate-analysis
description: Analyse an Arc-enabled SQL Server estate and recommend Azure optimisation and migration pathways. Use this when asked to assess SQL versions, editions, sizing, utilisation patterns, licensing optimisation, and Azure target options.
license: MIT
---

# Purpose

Use this skill to assess an Arc-enabled SQL Server estate and produce a structured optimisation recommendation for Azure migration.

# When to use this skill

Use this skill when the user asks to:

- assess an Arc-enabled SQL Server estate
- identify SQL Server end-of-support or end-of-life exposure
- find optimisation opportunities before migrating to Azure
- recommend candidate Azure landing options for SQL workloads
- separate evidence-based findings from assumptions or missing data
- analyse a tenant-scoped Arc-enabled SQL Server estate from live Azure data
- prompt for tenant ID or tenant DNS name before querying live Azure data
- fall back to Excel, JSON, or CSV input if live Azure access is unavailable or cannot be validated
- export the final analysis as a branded HTML or PDF report (including `/export-pdf`)

# Analysis workflow

## Phase 1 - Determine data acquisition mode

1. Determine whether the user wants:
   - live Azure tenant data, or
   - uploaded estate data (Excel / JSON / CSV)

2. If the user does not explicitly provide a file, prefer live Azure tenant data by default.

3. If live Azure tenant data is selected, obtain tenant scope from the user before any live query:
   - accept either a tenant ID (GUID) or tenant DNS name
   - if the user has access to multiple tenants, do not proceed until the tenant is explicitly identified

4. Resolve the subscriptions available in the selected tenant.

5. Ask the user to confirm the subscription scope for analysis:
   - single subscription
   - multiple subscriptions
   - all subscriptions in tenant
   - if a named workload subscription is mentioned, use that explicitly
   - confirm selected subscription IDs or names before analysis

6. After subscription scope is confirmed, query Resource Graph for Azure Migrate projects across the confirmed scope:
   ```
   resources
   | where type == "microsoft.migrate/migrateprojects"
   | project id, name, resourceGroup, subscriptionId, location
   ```

7. If one or more Azure Migrate projects are found:
   - present the list to the user via `ask_user`
   - prompt: "I found the following Azure Migrate project(s) in your tenant. Would you like me to include utilisation and dependency data from one of these in the analysis?"
   - choices: list of project names (with subscription and resource group context) + "Skip — don't use Azure Migrate data"
   - if the user selects a project, store the project resource ID for use in Phase 4 data acquisition

8. If no Azure Migrate projects are found:
   - note internally that Azure Migrate data is unavailable
   - continue with the existing analysis flow
   - surface the absence in "Data gaps / follow-up questions" with guidance: "No Azure Migrate project detected in scope — deploying an Azure Migrate appliance with dependency analysis would provide workload utilisation baselines and application dependency mapping"

## Phase 2 - Validate live Azure scope before analysis

1. Before running full estate analysis, perform a lightweight validation query against the selected tenant / subscription scope:
   - confirm that Arc-enabled SQL Server resources or Arc-enabled machines are visible in the chosen scope
   - verify returned tenant and subscription identifiers match the requested scope
   - if returned resources do not belong to the requested tenant / subscription scope, treat the result as invalid and do not continue with analysis
   - Evaluate query reliability:
      - detect potential false-negative results
      - detect inconsistent or cross-tenant results
   - If the validation query returns no resources:
     - treat the result as potentially unreliable
     - do not conclude that no resources exist yet

2. If the query returns no resources:
   - always confirm with the user before concluding that no resources exist
   - ask whether data is expected in the selected scope

3. If query results are inconsistent, empty, or suspected to be incorrect:
   - attempt an alternative query approach immediately when:
     - results are empty but expected
     - results appear inconsistent
     - scope cannot be validated

4. Preferred fallback order:
   - adjust the query structure
   - remove inline filters and rely on explicit subscription scoping
   - use an alternative execution method (e.g. Azure CLI)

5. Only proceed to analysis when:
   - at least one validated and consistent dataset has been obtained
   - or the agent has clearly confirmed that no data exists after multiple query attempts

6. If multiple query methods produce conflicting results:
   - prefer the dataset that:
     - aligns with explicit tenant and subscription scope
     - returns consistent and complete resource identifiers
   - clearly explain which data source was used and why

7. If the validation query fails, returns an unexpected scope, or live access cannot be trusted for tenant / subscription isolation:
   - stop immediately and report a scope validation error
   - in the error response, include requested tenant/subscription scope, observed scope from returned resources, and reason validation failed
   - do not produce estate analysis from unverified scope data (including unintended cross-tenant or cross-subscription results)
   - clearly state that live Azure scope could not be validated
   - offer fallback input modes:
     - Excel export
     - JSON export
     - CSV export

## Phase 3 - Collect licensing declarations

1. After tenant / subscription scope has been validated, but before licensing recommendations are formed, prompt the user via `ask_user`:
   - Prompt 1: "Do you have active Software Assurance coverage on any SQL Server licences in this estate?"
   - Choices: `Yes` / `No` / `Unsure`

2. If the user selects `Yes`, immediately follow up via `ask_user` with:
   - Prompt 2: "How many SQL Server Standard edition cores are covered by Software Assurance?"
   - Prompt 3: "How many SQL Server Enterprise edition cores are covered by Software Assurance?"
   - Accept freeform numeric input for both prompts
   - Store the declared values separately as Standard SA-covered cores and Enterprise SA-covered cores

3. If the user selects `No` or `Unsure`:
   - Record Software Assurance status as `Not confirmed` for `No`
   - Record Software Assurance status as `Unknown` for `Unsure`
   - Continue the analysis, but state that Azure Hybrid Benefit eligibility could not be confirmed
   - Add the missing SA confirmation to `Data gaps / follow-up questions`

4. Use the declared Software Assurance response during analysis:
   - Populate the `Software Assurance status` field in Estate summary from the declared answer
   - Use declared Standard and Enterprise SA-covered core counts to assess Azure Hybrid Benefit eligibility
   - Factor declared SA-covered cores into TCO comparisons for Azure target recommendations
   - If Enterprise SA-covered cores are declared but the recommendation favors Standard edition, highlight in `Key optimisation opportunities` and `Azure target recommendations` that SA entitlements may need reassignment or repurposing

## Phase 4 - Acquire estate data

1. When collecting live Azure data:
   - do not rely on a single successful query as authoritative
   - confirm that returned data:
     - belongs to the requested tenant and subscription
     - matches expected resource types
     - is consistent across repeated queries if necessary

2. If initial tool results appear incomplete or inconsistent:
   - re-run queries using:
     - alternate filtering patterns
     - explicit subscription scoping parameters
   - if still unresolved, attempt fallback acquisition methods before analysis

3. When using fallback or multiple query methods:
   - explicitly confirm that the dataset has been validated
   - state whether the data source is:
     - primary (MCP)
     - fallback (CLI or alternate method)

4. If live Azure scope is validated, collect Arc-enabled SQL estate data from the confirmed tenant / subscription scope:
   - SQL Server instances
   - databases
   - Arc-enabled host machines
   - any available assessment / readiness / backup / security metadata

5. Migration assessment data handling:
   - Assessment results are stored in a **telemetry data plane** (accessed via the `getTelemetry` action), not directly in ARM resource properties
   - The ARM property `properties.migration.assessment.skuRecommendationResults` is only populated after the Arc SQL extension syncs a summary to the resource — indicated by `assessmentUploadTime` being non-null
   - When `assessment.enabled = true` but `assessmentUploadTime = null`:
     - do NOT conclude that no assessment exists
     - report this as: "Assessment collected but not yet synced to ARM — data may be available in the Azure portal"
     - recommend the user trigger a fresh assessment via the portal ("Run Assessment" button) or wait for the next scheduled sync
     - do NOT list this as a "no assessment data" gap — instead surface it as a sync-pending state
   - When `assessmentUploadTime` is non-null:
     - use `skuRecommendationResults` and `serverAssessments` from the ARM properties as the data source
     - this data is programmatically accessible and should be used for MI/VM/DB readiness and SKU recommendations
   - There is currently no documented public API for reading assessment telemetry data directly — the portal uses an internal telemetry endpoint
   - If a user asks whether `getTelemetry` can be called programmatically:
     - you may attempt an ARM action probe (for example via `az rest --method POST`) only after tenant/subscription scope validation
     - treat a successful payload response as exceptional and verify response scope before using it
     - if the action is unavailable, unauthorized, undocumented, or returns no usable schema, treat telemetry as not publicly accessible and continue with ARM-synced guidance
   - There is currently no documented public API for triggering the portal "Run Assessment" action directly
     - do not claim that assessment sync can be forced via public API automation
     - recommend the user trigger "Run Assessment" in the Azure portal or wait for scheduled sync
   - Surface the sync-pending state in the output under "Data gaps / follow-up questions" with guidance to check the portal, rather than claiming the assessment does not exist

6. If uploaded data is used instead:
   - infer schema from the uploaded file
   - map fields to the analysis model where possible
   - clearly state any missing columns or unsupported inputs

7. Azure Migrate utilisation data extraction (when an Azure Migrate project was selected in Phase 1):

   a. List assessments in the selected project:
      ```
      GET /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Migrate/migrateProjects/{project}/assessments?api-version=2023-05-01
      ```
      - if the API version is not supported, fall back to `2020-05-01-preview` then `2018-09-01-preview`
      - prefer Azure SQL assessment types where available; fall back to Azure VM assessments for utilisation data

   b. For each relevant assessment, retrieve assessed machines:
      ```
      GET /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Migrate/migrateProjects/{project}/assessments/{assessment}/assessedMachines?api-version=2023-05-01
      ```

   c. Extract per-machine utilisation metrics:
      - `percentageCpuUtilization` — average CPU usage over collection period
      - `percentageMemoryUtilization` — average memory usage
      - `confidenceRatingInPercentage` — data quality indicator
      - disk I/O and network throughput where available
      - note the collection period (start/end dates) for data freshness disclosure

   d. Correlate Azure Migrate machines to Arc-enabled SQL machines:
      - match by machine name (primary, case-insensitive, strip domain suffix if needed)
      - fall back to IP address matching if name match fails
      - fall back to FQDN matching if IP match fails
      - if automatic correlation confidence is below 80% (e.g. name mismatch, IP mismatch), surface the attempted match for user confirmation rather than assuming
      - surface unmatched machines in "Data gaps / follow-up questions" with both the Arc machine name and Migrate machine name for manual reconciliation

8. Azure Migrate dependency data extraction (when an Azure Migrate project was selected in Phase 1):

   a. Determine dependency data access path:
      - agentless dependency data is NOT accessible via REST API or PowerShell — it is stored in the Azure Migrate service layer and viewable only in the Azure portal dependency visualization
      - the only supported path for retrieving this data is the **portal CSV export** (see below)
      - do NOT recommend agent-based dependency analysis as an alternative — deploying additional agents introduces friction and is not aligned with the agentless approach customers have already chosen

   b. Agentless dependency CSV export:
      - agentless dependency connection data cannot be retrieved programmatically
      - prompt the user via `ask_user`: "Azure Migrate dependency analysis is enabled but the data is only accessible via the Azure portal. Would you like to export the dependency data as CSV so I can include it in the analysis?"
      - provide export instructions:
        1. In the Azure portal, navigate to the Azure Migrate project
        2. Go to **All inventory** or **Infrastructure inventory** view
        3. Select **Manage Dependencies** dropdown → **Export dependencies**
        4. Select the appliance(s) and a time interval (recommend 30 days)
        5. Set process type to **Resolvable** (default) for clearest results
        6. Select **Generate**, then **Download** the CSV when ready
      - the exported CSV contains one row per observed dependency with these fields:
        - `Timeslot` — 6-hour window when the dependency was observed
        - `Source server name`
        - `Source application`
        - `Source process`
        - `Destination server name`
        - `Destination IP`
        - `Destination application`
        - `Destination process`
        - `Destination port`
      - when the user provides the CSV:
        - parse and correlate source/destination server names to Arc-enabled SQL machines
        - filter for SQL-relevant connections (destination port 1433, or connections where source/destination matches an Arc SQL machine name)
        - summarise inbound and outbound connections per SQL instance
        - identify SQL-to-SQL dependencies for migration sequencing

   c. Build a dependency map per Arc-enabled SQL machine:
      - which other machines/services connect to each SQL instance (inbound on port 1433 or custom SQL ports)
      - which external services each SQL machine connects to (outbound)
      - flag any SQL-to-SQL dependencies (important for migration sequencing)

   e. If dependency analysis is not enabled in the Azure Migrate project:
      - note that dependency data is unavailable
      - surface this in "Data gaps / follow-up questions" with guidance: "Azure Migrate agentless dependency analysis is not enabled — enabling it on the Azure Migrate appliance would provide application dependency mapping for migration sequencing"

   e. If the user declines to export or cannot provide the CSV:
      - continue the analysis without dependency data
      - note in "Data gaps / follow-up questions": "Dependency data available in Azure Migrate portal but not exported — export the dependency CSV from the Azure Migrate portal to include application dependency mapping in future analysis"


## Phase 5 - Enterprise downgrade audit

1. You MUST attempt an Enterprise downgrade audit before making any Enterprise → Standard recommendation.

2. Use a real execution path after tenant/subscription scope has been validated:
   - identify target Arc-enabled SQL instances from the validated scope dataset
   - for each target instance, enumerate relevant user databases (`database_id > 4`) that are online; include read-only databases because they can still return persisted feature evidence
   - execute the downgrade DMV across ALL user databases on each machine in a SINGLE consolidated script execution via Arc Run Command
   - the consolidated script MUST:
     - enumerate user databases dynamically (database_id > 4, state_desc = 'ONLINE')
     - execute `SELECT feature_name FROM sys.dm_db_persisted_sku_features` in each database
     - output structured JSON results for all databases in one response
   - this reduces round-trips from N (one per database) to 1 per machine
   - see "Consolidated script patterns" under Execution reliability considerations for the reference implementation

3. Capture results in a structured per-database output record using this minimum schema:
   - machineName
   - instanceName
   - databaseName
   - featureName
   - executionStatus
   - errorMessage
   - field names are mandatory and must use this exact camelCase naming
   - downstream processing depends on exact key matches; do not rename or reformat these keys

4. Populate structured output as follows:
   - audit succeeded with findings:
     - emit one record per returned feature row
     - set `featureName` to the returned DMV value
     - set `executionStatus = Succeeded`
     - set `errorMessage = null`
   - audit succeeded with no persisted features returned:
     - emit one explicit success record for that database
     - set `featureName = null`
     - set `executionStatus = Succeeded`
     - set `errorMessage = null`
   - audit failed:
     - emit one explicit failure record for that database
     - set `featureName = null`
     - set `executionStatus = Failed`
     - capture the failure reason in `errorMessage`

5. Treat this step as a REQUIRED data acquisition step:
   - do not skip execution due to partial data availability
   - do not proceed as if the audit was completed unless results are actually obtained

6. Handle results as follows:
   - If rows are returned:
     - surface the feature names clearly
     - treat them as potential downgrade blockers until interpreted against target Standard edition support for the chosen downgrade target version (default SQL Server 2022 Standard unless another target is specified)
   - If no rows are returned:
     - explicitly state that the DMV returned no persisted edition-restricted features
     - treat this as positive evidence, but NOT conclusive proof that Enterprise is unnecessary
   - If execution fails or cannot be performed:
     - explicitly state that the Enterprise downgrade audit could not be executed
     - do not claim that no Enterprise features are in use
     - downgrade confidence for any Enterprise → Standard recommendation must be Low

7. The downgrade recommendation MUST distinguish between:
   - persisted feature evidence
   - target edition support interpretation
   - runtime / operational feature usage results
   - remaining business-impact validation required

8. You MUST execute a separate runtime feature validation stage via Arc Run Command alongside the DMV findings before presenting any Enterprise → Standard downgrade as safe to proceed:
   - treat the DMV audit as persisted feature validation only
   - execute ALL runtime checks on each machine in a SINGLE consolidated script execution (not one query per round-trip)
   - the consolidated runtime script MUST execute the following queries and return structured JSON output:
     - Always On availability groups:
       SELECT ag.name AS ag_name, ar.replica_server_name, ar.availability_mode_desc
       FROM sys.availability_groups ag
       JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id;
       - interpret returned rows against Basic AG limits on Standard edition (for example single database per AG, no readable secondary scale-out)
     - Resource Governor:
       SELECT is_enabled FROM sys.resource_governor_configuration;
     - Partitioned tables:
       SELECT OBJECT_SCHEMA_NAME(p.object_id) AS schema_name,
              OBJECT_NAME(p.object_id) AS table_name,
              COUNT(DISTINCT p.partition_number) AS partition_count
       FROM sys.partitions p
       WHERE p.partition_number > 1 AND p.index_id IN (0,1)
       GROUP BY p.object_id;
     - SQL Agent job steps using online index operations:
       SELECT j.name AS job_name, js.command
       FROM msdb.dbo.sysjobs j
       JOIN msdb.dbo.sysjobsteps js ON j.job_id = js.job_id
       WHERE js.command LIKE '%ONLINE%=%ON%';
   - this reduces runtime validation from 4 round-trips per machine to 1
   - see "Consolidated script patterns" under Execution reliability considerations for the reference implementation
   - adapt `Invoke-Sqlcmd` parameters to host module capability:
     - the consolidated script MUST auto-detect `-TrustServerCertificate` support at runtime (see reference implementation) rather than relying on prior knowledge or retries
     - if host policy requires trusted certificates and the parameter is unavailable, surface this as an execution prerequisite gap (module upgrade/certificate remediation) instead of forcing retries
   - capture runtime results in a structured per-check output record using this minimum schema:
     - machineName
     - instanceName
     - checkName
     - result
     - executionStatus
     - errorMessage
   - classify runtime checks as follows:
     - successful execution with blockers/evidence returned:
       - set `executionStatus = Succeeded`
       - set `result` to concise blocker details
     - successful execution with no blockers:
       - set `executionStatus = Succeeded`
       - set `result = null` or `No blockers detected`
       - valid no-blocker examples include:
         - Always On AG query returns zero rows
         - Resource Governor query returns `is_enabled = 0`
         - partitioned table query returns zero rows
         - online index operation query returns zero rows
     - execution failure:
       - set `executionStatus = Failed`
       - set `result = null`
       - capture error in `errorMessage`
   - include compression interpretation in downgrade analysis:
     - SQL Server 2022 Standard supports compression
     - for older downgrade targets, validate compression support explicitly against target version

9. You MUST classify each Enterprise → Standard downgrade readiness using the following classification model:
   - GREEN = ready to downgrade:
     - DMV audit executed successfully with no persisted features detected
     - Runtime validation completed with no blockers identified
     - technical checks are complete; only business scheduling/impact approvals remain
   - AMBER = requires runtime validation:
     - DMV audit executed successfully with no persisted features detected
     - Runtime validation incomplete, failed, or status unknown for one or more required checks
   - RED = blocked by persisted or confirmed features:
     - Persisted features present in DMV audit (successful execution with features returned), OR
     - DMV audit execution failed or could not be completed, OR
     - Confirmed runtime blockers identified

10. The classification MUST be surfaced in:
   - Executive Summary (include classification status for any downgrade opportunities)
   - Key optimisation opportunities (for Enterprise → Standard recommendations)
   - Enterprise downgrade audit section (detailed classification)

11. You MUST NOT:
   - claim "no Enterprise features in use" without DMV evidence
   - provide Medium or High confidence downgrade recommendations without successful audit execution or equivalent evidence

12. Execution reliability considerations:

- You MUST consider execution reliability when using Arc Run Command or equivalent execution methods.

- Run command quota management (CRITICAL — understand before any execution):
  - Azure Arc enforces a maximum of 25 run commands per machine.
  - Deletions are extremely slow (minutes per command, processed sequentially by the Arc agent) and are NOT suitable as a pre-execution cleanup strategy.
  - DO NOT rely on `az connectedmachine run-command delete` as a fast way to free quota — deletions queue behind each other and may not propagate for 10+ minutes.

- Preferred execution strategy — REUSABLE COMMAND SLOTS:
  - Use a fixed naming convention with a small number of reusable command names per machine.
  - Naming pattern: `estate-audit-{machineName}-{slotNumber}` (e.g. `estate-audit-ArcBox-SQL-01`)
  - On FIRST execution against a machine:
    1. List existing run commands with `az connectedmachine run-command list`
    2. Check whether reusable slots already exist from a prior session
    3. If slots exist: UPDATE them with the new script using `az connectedmachine run-command update --force-string --set "source.script=<new script>"`
    4. If slots do not exist and quota allows: CREATE new commands using the slot naming convention
  - On SUBSEQUENT executions within the same session:
    - Always UPDATE existing slots rather than creating new commands
  - This approach avoids the 25-command limit entirely by reusing the same named resources.
  - Maximum slots needed per machine: 2 (one for DMV audit, one for runtime checks — both run as consolidated scripts)

- Parallel execution across machines:
  - When multiple machines require audit, submit run commands on EACH machine simultaneously using `--no-wait`
  - Then poll for results across all machines
  - This overlaps execution time: 2 machines × 2 scripts = 4 operations, but elapsed time ≈ 2 sequential operations (not 4)
  - DO NOT run multiple concurrent commands on the SAME machine (risk of HCRP500)
  - DO run commands on DIFFERENT machines in parallel

- Fallback: quota cleanup (use only when reusable slots cannot be created):
  - If the machine is already at 25/25 and no reusable slots exist from a prior session:
    1. Submit batch deletions via REST API: `az rest --method DELETE --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.HybridCompute/machines/{machine}/runCommands/{name}?api-version=2024-07-10"`
    2. Allow 5–10 minutes for propagation before re-checking capacity
    3. If quota cannot be freed within a reasonable time, report this as a pre-execution blocker
    4. Log the number of stale commands identified and the deletion approach used

- Execution sequencing:
  - Prefer sequential execution of operations on the SAME machine (one slot update at a time).
  - Use parallel execution ACROSS different machines (submit to machine A and machine B simultaneously).
  - Avoid creating multiple Run Command executions concurrently on the same machine, as this may result in execution conflicts (for example HCRP500 errors).

- Execution environment variability:
  - Be aware that execution environments may differ by host version.
  - Older SQL Server hosts may use earlier versions of the SqlServer PowerShell module.
  - The consolidated scripts auto-detect parameter support at runtime (see below).

- Script execution approach — CONSOLIDATED SCRIPTS WITH ENCODING:
  - ALWAYS use `powershell -EncodedCommand <base64>` to submit scripts via Arc Run Command.
  - This avoids all Azure CLI argument parsing issues with SQL queries containing joins, LIKE clauses, percent signs, and nested quotes.
  - Encoding workflow:
    1. Build the full PowerShell script as a string variable
    2. Encode: `$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))`
    3. Submit: `--script "powershell -EncodedCommand $encoded"` (for create) or `--force-string --set "source.script=powershell -EncodedCommand $encoded"` (for update)
  - DO NOT attempt to pass complex SQL queries directly via `--script` — they will fail due to CLI argument parsing.

- Consolidated script patterns:

  PATTERN 1 — DMV AUDIT (all databases on one instance, single execution):

  ```powershell
  $hasTsc = (Get-Command Invoke-Sqlcmd).Parameters.ContainsKey('TrustServerCertificate')
  $baseParams = @{ ServerInstance = 'localhost' }
  if ($hasTsc) { $baseParams['TrustServerCertificate'] = $true }
  $dbs = Invoke-Sqlcmd -Query "SELECT name FROM sys.databases WHERE database_id > 4 AND state_desc = 'ONLINE'" @baseParams
  $results = @()
  foreach ($db in $dbs) {
      try {
          $features = Invoke-Sqlcmd -Query "SELECT feature_name FROM sys.dm_db_persisted_sku_features" -Database $db.name @baseParams
          if ($features) {
              foreach ($f in $features) {
                  $results += @{ databaseName = $db.name; featureName = $f.feature_name; executionStatus = 'Succeeded'; errorMessage = $null }
              }
          } else {
              $results += @{ databaseName = $db.name; featureName = $null; executionStatus = 'Succeeded'; errorMessage = $null }
          }
      } catch {
          $results += @{ databaseName = $db.name; featureName = $null; executionStatus = 'Failed'; errorMessage = $_.Exception.Message }
      }
  }
  $results | ConvertTo-Json -Depth 3
  ```

  PATTERN 2 — RUNTIME VALIDATION (all checks on one instance, single execution):

  ```powershell
  $hasTsc = (Get-Command Invoke-Sqlcmd).Parameters.ContainsKey('TrustServerCertificate')
  $baseParams = @{ ServerInstance = 'localhost' }
  if ($hasTsc) { $baseParams['TrustServerCertificate'] = $true }
  $results = @()
  # Always On AG
  try {
      $ag = Invoke-Sqlcmd -Query "SELECT ag.name AS ag_name, ar.replica_server_name, ar.availability_mode_desc FROM sys.availability_groups ag JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id" @baseParams
      $results += @{ checkName = 'alwaysOnAvailabilityGroups'; result = if ($ag) { ($ag | ConvertTo-Json -Compress) } else { 'No blockers detected' }; executionStatus = 'Succeeded'; errorMessage = $null }
  } catch { $results += @{ checkName = 'alwaysOnAvailabilityGroups'; result = $null; executionStatus = 'Failed'; errorMessage = $_.Exception.Message } }
  # Resource Governor
  try {
      $rg = Invoke-Sqlcmd -Query "SELECT is_enabled FROM sys.resource_governor_configuration" @baseParams
      $results += @{ checkName = 'resourceGovernor'; result = "is_enabled=$($rg.is_enabled)"; executionStatus = 'Succeeded'; errorMessage = $null }
  } catch { $results += @{ checkName = 'resourceGovernor'; result = $null; executionStatus = 'Failed'; errorMessage = $_.Exception.Message } }
  # Partitioned tables
  try {
      $pt = Invoke-Sqlcmd -Query "SELECT OBJECT_SCHEMA_NAME(p.object_id) AS schema_name, OBJECT_NAME(p.object_id) AS table_name, COUNT(DISTINCT p.partition_number) AS partition_count FROM sys.partitions p WHERE p.partition_number > 1 AND p.index_id IN (0,1) GROUP BY p.object_id" @baseParams
      $results += @{ checkName = 'partitionedTables'; result = if ($pt) { ($pt | ConvertTo-Json -Compress) } else { 'No blockers detected' }; executionStatus = 'Succeeded'; errorMessage = $null }
  } catch { $results += @{ checkName = 'partitionedTables'; result = $null; executionStatus = 'Failed'; errorMessage = $_.Exception.Message } }
  # Online index operations
  try {
      $oi = Invoke-Sqlcmd -Query "SELECT j.name AS job_name, js.command FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobsteps js ON j.job_id = js.job_id WHERE js.command LIKE '%ONLINE%=%ON%'" -Database msdb @baseParams
      $results += @{ checkName = 'onlineIndexOperations'; result = if ($oi) { ($oi | ConvertTo-Json -Compress) } else { 'No blockers detected' }; executionStatus = 'Succeeded'; errorMessage = $null }
  } catch { $results += @{ checkName = 'onlineIndexOperations'; result = $null; executionStatus = 'Failed'; errorMessage = $_.Exception.Message } }
  $results | ConvertTo-Json -Depth 3
  ```

  - These patterns reduce total execution from 15 sequential round-trips (at ~3-5 min each) to 4 total operations (2 per machine), or 2 elapsed operations when machines are run in parallel.
  - Expected total execution time: ~10-15 minutes (down from 45-75 minutes).

- Output interpretation:
  - If execution returns empty output:
    - distinguish between:
      - a valid "no rows returned" DMV result
      - execution failure or output capture issues
  - Only treat empty DMV results as valid evidence when:
    - executionStatus indicates success, and
    - no errorMessage is present

- You MUST use executionStatus and errorMessage fields to disambiguate successful execution from failed or incomplete execution.
``


## Phase 6 - Analyse estate

1. Summarise the estate by host, instance, version, and edition where possible.

2. Flag end-of-support or end-of-life exposure.

3. Identify optimisation opportunities, always framed as steps towards Azure migration (not standalone on-premises cost reduction):
   - edition optimisation (e.g. Enterprise → Standard downgrade) as a pre-migration step to reduce Azure licensing costs or unlock Azure Hybrid Benefit eligibility
   - rightsizing opportunities that align current workloads with target Azure SKUs
   - operational improvements (e.g. backup, monitoring, security) that prepare the estate for cloud migration readiness
   - Do not use indirect signals (e.g. database properties such as isMemoryOptimizationEnabled) as proof of Enterprise feature usage.
   - Treat such signals as indicative only and require DMV confirmation for downgrade decisions.
   - For Enterprise → Standard downgrade candidates, present:
     - persisted feature findings from `sys.dm_db_persisted_sku_features`
     - runtime validation execution results from Arc Run Command checks
     - target edition support interpretation (including compression support for selected target version)
   - GREEN readiness can be used only when persisted and runtime technical checks are completed and clean

4. When interpreting licensing:
   - Treat licensing model, Software Assurance status, and billing mode as separate dimensions (not a single "license type" field)
   - Assess each dimension independently from source evidence
   - Report licensing model only when explicitly evidenced (for example: Server/CAL, Core, Unknown)
   - Do not assume Software Assurance status from licenseType alone
   - Prefer the user's declared response from the licensing declaration phase for Software Assurance status over ambiguous Azure metadata
   - Report Software Assurance as Enabled / Not confirmed / Unknown based on the declared response when available; otherwise use explicit source signals only
   - Report billing mode as Paid / PAYG / Free / Unknown based on explicit signals only
   - Do not infer Server/CAL from Paid billing or Software Assurance signals
   - Use declared Standard and Enterprise SA-covered core counts to determine whether Azure Hybrid Benefit applies fully, partially, or cannot be confirmed
   - If declared SA-covered cores are lower than the target Azure core requirement:
     - quantify the covered and uncovered core split
     - surface that split in Estate summary and Azure target recommendations using the `Confirmed eligible cores` and `Unconfirmed or uncovered cores` fields
     - treat any uncovered portion as licence-included / PAYG exposure unless other explicit evidence exists
   - If multiple signals are inconsistent or incomplete, mark licensing as Unknown or Mixed, use cautious wording (for example "appears", "not confirmed"), and surface this explicitly as a data gap

5. Identify combined optimisation opportunities that reduce total cost of ownership (TCO) on the path to Azure, including:
   - combining licensing optimisation (e.g. edition downgrade) with Azure migration planning — position edition changes as enabling lower Azure target costs, not as on-premises savings in isolation
   - with Azure cost optimisation (e.g. PAYG via Arc, Azure Hybrid Benefit, or lower-cost Azure SKUs)
   - prioritising changes that can be applied together for maximum impact on Azure migration readiness and target cost

6. Classify recommendations into:
   - Quick wins = low effort steps that improve Azure migration readiness or reduce target Azure costs
   - Strategic moves = higher effort changes that provide medium- to long-term Azure migration value or optimise Azure landing costs

7. Recommend candidate Azure target options, for example:
   - Azure SQL Managed Instance
   - SQL Server on Azure Virtual Machines
   - Arc-enabled SQL Server PAYG as an interim transition option
   - explicitly state whether Azure Hybrid Benefit appears eligible based on the declared SA-covered cores
   - reflect the declared SA position in TCO comparisons and PAYG versus licence-included guidance
   - When Azure SQL Managed Instance readiness metadata is available:
     - report the readiness state for each MI candidate
     - if a workload is marked Not Ready, retrieve the blocker details from the source data
     - explain briefly why the blocker prevents MI readiness
     - provide concise remediation steps tied to the evidenced blocker
     - if blocker detail is not available, state that clearly and add it to Data gaps / follow-up questions instead of inferring a reason

8. When Azure Migrate utilisation data is available:
   - include workload utilisation baselines in Estate summary with source attribution ("Azure Migrate project: {name}")
   - surface the collection period and confidence rating alongside utilisation figures
   - use utilisation data to validate or refine SKU right-sizing recommendations:
     - if average CPU utilisation is below 30%, flag as over-provisioned and recommend a smaller SKU
     - if average CPU utilisation is above 80%, flag as potentially under-provisioned
   - increase confidence rating on sizing recommendations from Low → Medium or High when utilisation data supports the recommendation
   - if utilisation data is available for some machines but not others, clearly distinguish which recommendations are utilisation-validated and which are configuration-based only

9. When Azure Migrate dependency data is available:
   - include an application dependency summary in Estate summary showing key inbound and outbound connections per SQL instance
   - use dependency data to inform migration sequencing in Azure target recommendations:
     - identify SQL instances with no inbound SQL dependencies as candidates for early migration waves
     - identify SQL instances with cross-instance dependencies that must be migrated together or in sequence
   - surface any unexpected dependencies in Risks and blockers (e.g. SQL instance connecting to external non-Azure endpoints, undocumented application connections)
   - flag SQL-to-SQL dependencies explicitly — these affect migration wave planning and downtime windows

10. Separate confirmed findings from assumptions, unknowns, or missing fields.

11. Produce the final answer using the structure in `references/output-template.md`.

## Phase 7 - Optional report export (HTML/PDF)

1. If the user requests export (for example "export report", "save as PDF", or `/export-pdf`), generate a self-contained HTML report:
   - use `references/output-template.md` for section order and headings
   - use `references/branded-report-template.md` for branded HTML structure and styling

2. Build branded HTML using the structure in `references/branded-report-template.md`:
   - Microsoft four-square logo as inline SVG
   - `Microsoft` wordmark text
   - Azure Arc pill/badge with `SQL Server Estate Analysis` label
   - Blue gradient header bar (`#0078d4` to `#005a9e`)
   - Fluent UI / Segoe UI styling with colour-coded readiness badges (`GREEN`, `AMBER`, `RED`)
   - Confidential watermark and footer with generation date
   - no external image, font, or CDN dependencies

3. Output handling:
   - default behaviour:
     - `/export-pdf`: generate HTML and convert to PDF
     - generic export request (such as "export report"): generate HTML unless PDF is explicitly requested
     - rationale: HTML export has no browser binary dependency and is the safest default artifact
     - if PDF is explicitly requested (for example "export report as PDF"), generate HTML and convert to PDF
     - if the request is ambiguous, ask whether the user wants HTML or PDF
   - if user provides an output path, use it
   - otherwise default to current session working directory
   - default filenames:
     - HTML: `estate-report.html`
     - PDF: `estate-report.pdf`

4. For PDF conversion, render HTML to PDF via Edge or Chrome headless:
   - prefer absolute paths for both `<input-html-path>` and `<output-pdf-path>` to avoid path resolution issues
   - placeholders are full file paths (including directory and `.html` / `.pdf` filenames)
   - Edge:
     - `msedge --headless --disable-gpu --print-to-pdf="<output-pdf-path>" "<input-html-path>"`
     - example: `msedge --headless --disable-gpu --print-to-pdf="/workspace/estate-report.pdf" "/workspace/estate-report.html"`
   - Chrome:
     - `google-chrome --headless --disable-gpu --print-to-pdf="<output-pdf-path>" "<input-html-path>"`
     - example: `google-chrome --headless --disable-gpu --print-to-pdf="/workspace/estate-report.pdf" "/workspace/estate-report.html"`

5. If browser binaries are unavailable, or conversion fails (for example browser not found, write permission denied, or insufficient disk space), return the generated HTML and clearly state that PDF conversion could not be completed in the current environment.
   - include the HTML output path so the user can run conversion manually
   - validate that generated HTML is non-empty and contains required section headings before attempting conversion; if validation fails, report the HTML validation error instead of attempting PDF conversion
   - required headings: `Executive Summary`, `Estate summary`, `Key optimisation opportunities`, `Enterprise downgrade audit`, `Quick wins`, `Strategic moves`, `Azure target recommendations`, `Risks and blockers`, `Data gaps / follow-up questions`
   - failure response format:
     - `PDF export status: Failed`
     - `Reason: {error_detail}`
     - `HTML output: {absolute_html_path}`
     - `Suggested manual command: {edge_or_chrome_command}`

# Guardrails

- Keep findings evidence-based.
- Do not claim utilisation, savings, or migration suitability unless the source data supports it.
- Always frame optimisation recommendations as steps towards Azure migration. Do not present on-premises licensing optimisation (e.g. edition downgrade, PAYG conversion) as a standalone cost-saving exercise — every recommendation must connect to how it improves Azure migration readiness, reduces target Azure costs, or enables Azure Hybrid Benefit eligibility.
- If required fields are missing, state that plainly under Data gaps / follow-up questions.
- Do not infer Azure SQL Managed Instance blockers or remediation without explicit readiness evidence.
- Never recommend Enterprise → Standard downgrade with Medium or High confidence unless the Enterprise downgrade audit has executed successfully or equivalent evidence is explicitly available.
- Never describe an Enterprise → Standard downgrade as fully safe unless runtime feature validation has also been completed.
- Prefer concise, customer-ready wording.
- Apply confidence inline to each recommendation only in:
  - Key optimisation opportunities
  - Azure target recommendations
- Use only these confidence levels:
  - High = strong direct evidence
  - Medium = reasonable inference with some gaps
  - Low = limited data or assumptions required
 
## Enterprise downgrade audit guardrails

- Never recommend an Enterprise → Standard downgrade based solely on inventory heuristics when audit data is absent.
- Treat `sys.dm_db_persisted_sku_features` as an important input, not the sole decision gate.
- If the DMV returns rows, surface feature names clearly and treat them as potential blockers until each has been assessed against the SQL Server 2022 Standard edition support matrix.
- If the DMV returns no rows, report this as positive evidence and require runtime validation execution results before declaring technical downgrade readiness.
- If the Arc Run Command audit could not be executed for an instance, do not issue a downgrade recommendation for that instance; surface the gap under Data gaps / follow-up questions.
- Preserve cautious wording ("may be safe to downgrade pending confirmation", "audit evidence supports further investigation") wherever feature interpretation is uncertain.
- Do not over-claim downgrade suitability; keep wording customer-safe and defensible.

## Tenant and scope guardrails

- Never assume that a tenant or subscription filter has been applied correctly just because it was passed to a tool.
- Always verify that returned resources belong to the tenant / subscription scope requested by the user before continuing with analysis.
- If returned resources belong to a different subscription or tenant than requested, stop and report a scope validation failure.
- Do not produce a full estate analysis until scope has been validated.
- If live tenant scope cannot be validated, offer fallback analysis via uploaded Excel, JSON, or CSV data.
- Never proceed to analysis if tenant or subscription scope cannot be confidently validated.
- If returned resources appear to belong to a different tenant or subscription than requested, stop and report the issue.
- Always prioritise correctness of scope over completeness of output.

## Report export guardrails

- Keep exported HTML self-contained (inline SVG/CSS only; no external image dependencies).
- Preserve section order from `references/output-template.md` in both HTML and PDF outputs.
- Apply GREEN / AMBER / RED badges exactly for downgrade readiness states where present.
- Include generation date in footer and keep `Confidential` watermark/footer text in exported output.

## Tool reliability guardrails

- Do not assume that execution tools (e.g. Azure MCP, Resource Graph) correctly apply tenant or subscription scoping.

- Treat empty or unexpected query results as potentially unreliable.

- Never conclude that no resources exist based on a single query result.

- If a query returns no resources:
  - confirm whether data is expected in the selected scope before proceeding
  - do not assume the result is correct without validation

- When results are empty, inconsistent, or conflict with expected scope:
  - actively attempt to validate or corroborate the result

- Use alternative query approaches or execution methods when results are unreliable, including:
  - adjusting the query structure
  - removing inline filters
  - using an alternative execution method (e.g. Azure CLI)

- Prefer validated, scope-aligned data over first-returned results.

- Clearly communicate when fallback methods are used and which data source was ultimately trusted.

## Migration assessment data guardrails

- Do not conclude that no migration assessment exists based solely on `assessmentUploadTime = null` or `skuRecommendationResults = null` in ARM properties or Resource Graph.

- Assessment data is stored in a telemetry data plane (not ARM properties). The ARM resource only contains a synced summary. The portal reads from both sources; programmatic access is limited to the synced summary.

- When `assessment.enabled = true` and `assessmentUploadTime = null`:
  - treat this as a **sync-pending state**, not a data absence
  - do not report "no assessment data uploaded" as a data gap
  - instead report: "Assessment collected but ARM sync pending — check Azure portal for latest results or trigger 'Run Assessment' to force sync"

- When reporting assessment gaps in output, distinguish between:
  - "Assessment not enabled" (assessment.enabled = false) — genuine gap, recommend enabling
  - "Assessment enabled, sync pending" (enabled = true, assessmentUploadTime = null) — data likely exists in portal
  - "Assessment synced but incomplete" (assessmentUploadTime set, but fields missing) — partial data, report what is available

- Never infer MI/VM readiness status from the absence of synced ARM data alone. If ARM data is unavailable, state the limitation and direct the user to the portal assessment blade.

- If a `getTelemetry` ARM action probe is attempted and fails due to authorization, API exposure, schema, or endpoint availability:
  - report the probe result as evidence that telemetry is not publicly consumable in the current context
  - continue analysis using ARM-synced fields and sync-pending guidance only

- Do not claim that "Run Assessment" can be automated through a documented public API unless explicit public documentation is provided in the current session evidence.

## Azure Migrate integration guardrails

- Azure Migrate integration is additive — if no Azure Migrate project exists or the user skips project selection, the analysis continues without error using existing data sources. Do not treat the absence of Azure Migrate data as a blocker.

- Always disclose the data source when presenting utilisation or dependency findings. Clearly attribute data to "Azure Migrate project: {name}" with the collection period and confidence rating.

- Do not assume that Azure Migrate discovered machines map 1:1 to Arc-enabled SQL machines. Machine correlation must be validated:
  - match by machine name first (case-insensitive, strip domain suffix if needed)
  - fall back to IP address, then FQDN
  - if automatic correlation confidence is below 80%, surface the attempted match for user confirmation rather than assuming a match
  - surface unmatched machines from either side in "Data gaps / follow-up questions"

- Do not increase recommendation confidence based on Azure Migrate data unless the machine correlation has been validated and the utilisation data covers a meaningful collection period (at least 7 days).

- Handle partial Azure Migrate coverage explicitly:
  - if utilisation data is available for some Arc machines but not others, clearly distinguish which sizing recommendations are utilisation-validated versus configuration-based only
  - do not generalise utilisation patterns from covered machines to uncovered machines

- Azure Migrate API version compatibility:
  - attempt the latest stable API version (`2023-05-01`) first
  - if the response indicates version unsupported, fall back to `2020-05-01-preview` then `2018-09-01-preview`
  - if all versions fail, surface the API error and continue without Migrate data

- Agentless dependency data is NOT accessible via REST API or PowerShell. The data is stored in the Azure Migrate service layer and can only be viewed in the Azure portal or exported as CSV via portal **Manage Dependencies > Export dependencies**. Do not attempt to retrieve agentless dependency data programmatically — prompt the user to export the CSV instead.

- Do not recommend agent-based dependency analysis as an alternative to the agentless CSV export. Deploying additional agents introduces friction and is not aligned with the agentless approach customers have already chosen.

- When parsing an Azure Migrate dependency CSV export:
  - validate that the CSV contains the expected columns: `Timeslot`, `Source server name`, `Source application`, `Source process`, `Destination server name`, `Destination IP`, `Destination application`, `Destination process`, `Destination port`
  - correlate source/destination server names to Arc-enabled SQL machines using the same machine correlation strategy (name → IP → FQDN)
  - filter for SQL-relevant connections: destination port 1433 (default SQL port), or connections where source or destination server name matches an Arc SQL machine
  - summarise by connection frequency — prioritise high-frequency connections over one-off observations

- Limit dependency data queries to the most relevant connections:
  - use `summarize` and `top` operators in KQL to limit to top connections per machine by count
  - do not attempt to retrieve exhaustive connection logs for large estates

- Do not infer application ownership or business criticality from dependency data alone. Dependency data shows network connections, not business relationships. Surface raw dependency findings and let the user interpret business impact.

# Output requirements

Always produce the sections below in order:

1. Executive Summary (3–5 concise bullet points for CIO/IT Director audience, highlighting key risks, optimisation opportunities, and Azure direction)
2. Estate summary
3. Key optimisation opportunities
4. Enterprise downgrade audit
5. Azure target recommendations
6. Risks and blockers
7. Data gaps / follow-up questions
