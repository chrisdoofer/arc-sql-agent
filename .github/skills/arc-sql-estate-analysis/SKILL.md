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

6. Azure Migrate project discovery is performed as part of the consolidated estate query in Phase 4 (the `microsoft.migrate/migrateprojects` type is included in that query). There is no need to run a separate project discovery query at this point. Once the consolidated query result is available in Phase 4, extract Migrate project rows from it and proceed as follows:

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

   ```kql
   resources
   | where type =~ 'microsoft.hybridcompute/machines' or type =~ 'microsoft.azurearcdata/sqlserverinstances'
   | summarize count() by type, subscriptionId
   ```

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

4. If live Azure scope is validated, collect all Arc-enabled SQL estate data using a **single consolidated Azure Resource Graph query**. This retrieves SQL instances, databases, Arc-enabled machines, and Azure Migrate projects in one round-trip:

   ```kql
   resources
   | where type =~ 'microsoft.azurearcdata/sqlserverinstances'
       or type =~ 'microsoft.azurearcdata/sqlserverinstances/databases'
       or type =~ 'microsoft.hybridcompute/machines'
       or type =~ 'microsoft.migrate/migrateprojects'
   | where subscriptionId in ({subscriptionIds})
   | project id, name, type, resourceGroup, subscriptionId, location, properties, tags
   ```

   Execute using the Azure CLI template (see `references/command-templates.md` — Template 5: Consolidated Estate ARG Query):

   ```powershell
   az graph query -q "resources | where (type =~ 'microsoft.azurearcdata/sqlserverinstances' or type =~ 'microsoft.azurearcdata/sqlserverinstances/databases' or type =~ 'microsoft.hybridcompute/machines' or type =~ 'microsoft.migrate/migrateprojects') | where subscriptionId in ('{sub1}','{sub2}') | project id, name, type, resourceGroup, subscriptionId, location, properties, tags" --subscriptions {subscriptionIds} --first 1000 -o json
   ```

   **Data available in Resource Graph (use the consolidated query — no separate ARM calls needed):**
   - SQL instance properties: `version`, `edition`, `vCores`, `licenseType`, `status`, `backupPolicy`, `monitoring`, `azureDefenderStatus`, `alwaysOnRole`, `tcpStaticPorts`
   - Assessment / migration data: `properties.migration` including `assessment.enabled`, `assessmentUploadTime`, `skuRecommendationResults`, `serverAssessments`
   - Database properties: `state`, `sizeMB`, `compatibilityLevel`, `recoveryMode`, `backupInformation`, `collationName`, `databaseOptions`
   - Machine properties: `osSku`, `osName`, `status`, `detectedProperties` (coreCount, memory, processorNames)
   - Azure Migrate project identifiers: `id`, `name`, `resourceGroup`, `subscriptionId`, `location`

   **NOT available in Resource Graph (separate API calls are required and justified):**
   - Azure Migrate project utilisation data — requires Migrate API endpoints
   - Assessed machine metrics from Azure Migrate (CPU/memory baselines, confidence scores)
   - Agentless dependency analysis data — via the `Microsoft.DependencyMap` REST API (primary, see Phase 4 step 8b) or portal CSV export for classic agentless appliance data (fallback, see Phase 4 step 8c)

   **Post-query local processing (perform locally — no additional network calls):**
   1. Filter results by `type` field to separate: SQL instances, databases, machines, and Migrate projects
   2. Group databases by parent instance using the resource ID hierarchy (instance resource ID is the parent segment of each database resource ID)
   3. Correlate machines to SQL instances by matching `properties.containerResourceId` in the instance to the machine `id`, or by matching instance machine name to `name` in machines
   4. Extract assessment and migration data from `properties.migration` on each SQL instance resource
   5. Identify any Azure Migrate projects returned and present for user selection (see Phase 1 step 6 — project discovery can be satisfied by this query; no separate project discovery query is needed)

   **Pagination for large estates (1000+ resources):**
   - Resource Graph returns a maximum of 1,000 rows per query by default
   - Always include `--first 1000` in the CLI command
   - Check the response for a `skip_token` field; if present, issue a follow-up query using `--skip-token {skipToken}` to retrieve the next page
   - Repeat until no `skip_token` is returned
   - Even with pagination this approach reduces network round-trips from N individual calls to 1–2 paged queries

5. Migration assessment data handling:
   - Assessment results are stored in a **telemetry data plane** (accessed via the `getTelemetry` action), not directly in ARM resource properties
   - The ARM properties `properties.migration.assessment.skuRecommendationResults` and `serverAssessments` are synced summaries from that telemetry plane; `assessmentUploadTime` is a freshness indicator, not the extraction gate
   - When `skuRecommendationResults` or `serverAssessments` contains usable data:
     - use the populated ARM fields as the data source for MI/VM/DB readiness, SKU recommendations, and cost evidence even if `assessmentUploadTime` is null
     - if `assessmentUploadTime` is null or appears stale/inconsistent, disclose that the assessment freshness timestamp is unavailable or inconsistent, but do not suppress the populated assessment output
   - Only when `assessment.enabled = true` and the recommendation fields are not populated:
     - do NOT conclude that no assessment exists
     - report this as: "Assessment collected but not yet synced to ARM — data may be available in the Azure portal"
     - recommend the user trigger a fresh assessment via the portal ("Run Assessment" button) or wait for the next scheduled sync
     - do NOT list this as a "no assessment data" gap — instead surface it as a sync-pending state
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

   > **Resource type note:** `Microsoft.Migrate/migrateProjects` is the project *container* resource used for discovery (returned by the consolidated ARG query). Assessment and utilisation data lives under a **different resource type**: `Microsoft.Migrate/assessmentProjects`. Do not query `migrateProjects` for assessments — it only supports api-versions up to `2020-06-01-preview` and has no assessment sub-resources.

   a. List assessments in the selected project:
      ```
      GET /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Migrate/assessmentProjects/{project}/groups/{group}/assessments?api-version=2023-03-15
      ```
      - to enumerate available groups first: `GET .../assessmentProjects/{project}/groups?api-version=2023-03-15`
      - prefer Azure SQL assessment types where available; fall back to Azure VM assessments for utilisation data

   b. For each relevant assessment, retrieve assessed machines:
      ```
      GET /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Migrate/assessmentProjects/{project}/groups/{group}/assessments/{assessment}/assessedMachines?api-version=2023-03-15
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

   a. Determine dependency data access path. There are two distinct dependency data sources — check for the newer one first:
      - **Azure Migrate Dependency Map (`Microsoft.DependencyMap/maps`)** — the newer dependency mapping service. Connection data is held in a graph-based datastore that is NOT queryable via Azure Resource Graph, but IS retrievable programmatically via the `Microsoft.DependencyMap` REST API. **This is the primary, preferred path.** See step 8b.
      - **Classic agentless Azure Migrate appliance dependency analysis** — the older appliance-based feature. This data is NOT accessible via REST API or PowerShell; it lives in the Azure Migrate service layer and is only available via portal CSV export. Use this only as a fallback when no Dependency Map resource exists. See step 8c.
      - do NOT recommend agent-based dependency analysis as an alternative — deploying additional agents introduces friction and is not aligned with the agentless approach customers have already chosen

   b. Direct Dependency Map API extraction (primary path):
      - resolve the Dependency Map resource(s) in scope using command-templates.md **Template 7 (List Dependency Map Resources)** — this returns the `{mapName}` needed for export
      - if one or more maps are found, bulk-export dependencies using command-templates.md **Template 8 (Export Dependencies via Direct API)**:
        - resolve `{focusedMachineId}` from the map's discovered machines, correlating to each Arc-enabled SQL machine by name (case-insensitive, strip domain suffix); if a machine cannot be correlated, surface it in "Data gaps / follow-up questions" rather than guessing
        - use a **28-day** collection window (the API rejects start dates older than 30 days; 28 days stays safely inside this hard limit) and the default (resolvable) process filter unless the user requests otherwise
        - the operation is async — poll the `Location` header until `status` is `Succeeded`, then download the CSV from `properties.exportedDataSasUri`
        - if the result reports `statusCode: PartialMatch` with `availableDaysCount`, disclose that fewer days of data were available than requested as a data-freshness note
      - for targeted single-machine inspection, use command-templates.md **Template 9 (Get Dependency View for a Focused Machine)**
      - **API version:** default to `2025-05-01-preview`; if rejected, fall back to `2025-07-01-preview` then `2025-01-31-preview`. If all versions fail, surface the API error and fall back to the portal CSV export path (step 8c)
      - the exported CSV uses the same column structure as the portal export — parse it using the dependency-CSV correlation rules in step 8d
      - if no Dependency Map resource is returned by Template 7, the new service is not in use in this scope — fall back to step 8c

   c. Classic agentless dependency CSV export (fallback — only when no Dependency Map resource exists or the API is unavailable):
      - classic agentless dependency connection data cannot be retrieved programmatically
      - prompt the user via `ask_user`: "Azure Migrate agentless dependency analysis is enabled but no Dependency Map resource was found, so the data is only accessible via the Azure portal. Would you like to export the dependency data as CSV so I can include it in the analysis?"
      - provide export instructions:
        1. In the Azure portal, navigate to the Azure Migrate project
        2. Go to **All inventory** or **Infrastructure inventory** view
        3. Select **Manage Dependencies** dropdown → **Export dependencies**
        4. Select the appliance(s) and a time interval (recommend **28 days** — the portal enforces a 30-day hard limit on start date)
        5. Set process type to **Resolvable** (default) for clearest results
        6. Select **Generate**, then **Download** the CSV when ready

   d. Parse the dependency CSV (from either step 8b or step 8c) — the exported CSV contains one row per observed dependency with these fields:
        - `Timeslot` — 6-hour window when the dependency was observed
        - `Source server name`
        - `Source application`
        - `Source process`
        - `Destination server name`
        - `Destination IP`
        - `Destination application`
        - `Destination process`
        - `Destination port`
      - when the CSV is available:
        - parse and correlate source/destination server names to Arc-enabled SQL machines
        - filter for SQL-relevant connections (destination port 1433, or connections where source/destination matches an Arc SQL machine name)
        - summarise inbound and outbound connections per SQL instance
        - identify SQL-to-SQL dependencies for migration sequencing

   e. Build a dependency map per Arc-enabled SQL machine:
      - which other machines/services connect to each SQL instance (inbound on port 1433 or custom SQL ports)
      - which external services each SQL machine connects to (outbound)
      - flag any SQL-to-SQL dependencies (important for migration sequencing)

   f. If dependency analysis is not enabled (no Dependency Map resource and classic dependency analysis disabled):
      - note that dependency data is unavailable
      - surface this in "Data gaps / follow-up questions" with guidance: "Azure Migrate dependency analysis is not enabled — enabling it (Dependency Map or the agentless appliance) would provide application dependency mapping for migration sequencing"

   g. If the API path fails and the user declines to export or cannot provide the CSV:
      - continue the analysis without dependency data
      - note in "Data gaps / follow-up questions": "Dependency data available in Azure Migrate but not retrieved — retry the Dependency Map API export or export the dependency CSV from the Azure Migrate portal to include application dependency mapping in future analysis"

9. SQL on Azure VM best practices alignment (optional, additive):
   - offer this scan during analysis when either:
     - SQL Server on Azure VM is identified as a candidate target, or
     - the user explicitly asks for Azure SQL VM best-practices alignment
   - first prompt via `ask_user`:
     - "SQL Server on Azure VM has been identified as a candidate target. Would you like me to run an Azure VM best practices alignment scan on the Arc-enabled SQL machines?"
     - choices: `["Yes — run alignment scan", "Skip — not needed for this analysis"]`
   - if accepted, use this execution order:
     - **Tier 1 (Resource Graph, read-only, default):** resolve checks directly from Arc SQL instance/database properties:
       - INST-01 (`maxServerMemoryMB`)
       - INST-07 (`databaseOptions.isAutoShrinkOn`)
       - INST-08 (`databaseOptions.isAutoCloseOn`)
       - INST-11 (`patchLevel`, `currentVersion`)
       - SEC-01 (`azureDefenderStatus`)
       - SEC-02 (`databaseOptions.isEncrypted`)
       - HADR-01 (`isHadrEnabled`, `alwaysOnRole`)
     - **Tier 2 (Log Analytics BPA, read-only, preferred for broad coverage):** query SQL Best Practices Assessment results from `SqlAssessment_CL` and map BPA check IDs to Azure SQL VM best-practice categories (Storage, Instance configuration, Security, HADR, Operations)
       - **Step 1 — Workspace discovery:** resolve the target Log Analytics workspace using this priority order:
         1. Read `properties.monitoring.logAnalyticsWorkspaceResourceId` from each Arc SQL instance resource (already available in Resource Graph data collected in Phase 4); extract the workspace resource ID from this field
         2. If the field is absent or null for all instances, enumerate Log Analytics workspaces in scope:
            ```bash
            az monitor log-analytics workspace list --subscription <subscriptionId> --query "[].{id:id, name:name, resourceGroup:resourceGroup}" -o json
            ```
         3. For each discovered workspace, check whether the `SqlAssessment_CL` table exists:
            ```bash
            az monitor log-analytics workspace table show --subscription <subscriptionId> --resource-group <resourceGroup> --workspace-name <workspaceName> --name SqlAssessment_CL --query "name" -o tsv 2>/dev/null
            ```
         4. Use the first workspace where the table is confirmed to exist; if multiple workspaces contain the table, query all of them and merge results
       - **Step 2 — Execution method (REST API only):** always use the Log Analytics REST API for BPA queries; do **not** use `az monitor log-analytics query`, because CLI execution may return empty computed columns for KQL expressions such as `parse_csv`, `split`, `extend`, `indexof`, and `substring`
        1. Resolve the workspace GUID (`customerId`) for each target workspace:
           ```powershell
           $workspaceGuid = az monitor log-analytics workspace show --subscription "<subscriptionId>" --resource-group "<resourceGroup>" --workspace-name "<workspaceName>" --query "customerId" -o tsv
           ```
        2. Pre-filter to the target machine names and relevant BPA check IDs before parsing `RawData`; this avoids volume explosions from verbose rows such as `DbBackupMedia` and keeps the result set focused on Azure SQL VM alignment checks
           - replace `'<machine1>', '<machine2>'` in the example below with the full comma-separated list of individually quoted Arc machine names collected earlier in Phase 4 (for example `('machine-a', 'machine-b', 'machine-c')`); do not leave placeholders in the executed query
        3. Submit the KQL through `az rest --method POST --url "https://api.loganalytics.io/v1/workspaces/$workspaceGuid/query"` with a JSON body file, using the `$workspaceGuid` resolved in step 1:
           ```powershell
           $queryBody = @{
               query = @"
SqlAssessment_CL
| where TimeGenerated > ago(30d)
| extend parsed = parse_csv(RawData)
| extend checkId = tostring(parsed[2]),
         checkName = tostring(parsed[3]),
         severity = tostring(parsed[6]),
         machineDb = tostring(parsed[7]),
         message = tostring(parsed[9]),
         instanceName = tostring(parsed[11])
| extend machineName = tostring(split(machineDb, ':')[0])
| where machineName in ('<machine1>', '<machine2>')
| where checkId in ('NtfsBlockSizeNotFormatted','TempDbSameVolume','TempDBFiles1PerCPU',
    'TempDBFilesNotLess8','InstantFileInitialization','QueryStoreOn','BackupCompression',
    'AutoShrink','AutoClose','PercentAutogrows','FilesAutogrowth','MaxServerMemory',
    'MaxDop','TempDBDataSameSize','DataFilesSameVolume','LogFilesSameVolume',
    'DbBackupMedia','CostThresholdParallelism','LockPagesInMemory','AdHocWorkload')
| summarize findingCount=count(), latestTime=max(TimeGenerated), sampleMessage=any(message)
    by machineName, instanceName, checkId, checkName, severity
| order by machineName asc, checkId asc
"@
           } | ConvertTo-Json -Compress

           $queryPath = Join-Path $env:TEMP ("la-bpa-query-" + [guid]::NewGuid().ToString() + ".json")
           $queryBody | Set-Content $queryPath

           $env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
           $response = az rest --method POST --url "https://api.loganalytics.io/v1/workspaces/$workspaceGuid/query" --body "@$queryPath" --headers "Content-Type=application/json" -o json | ConvertFrom-Json
           ```
        4. Use `summarize` to deduplicate repeated BPA findings (especially file-level backup media rows)
        5. If more than one workspace contains `SqlAssessment_CL`, repeat the same REST API call for each workspace GUID and merge the returned result sets outside the single API call before mapping findings into the report
        6. If the REST call fails (for example authentication, workspace resolution, or API errors), capture the failure explicitly (workspace name/GUID, HTTP/API error text, and query window attempted) and continue to the next workspace or fallback path rather than silently treating the result as empty BPA data
       - **Step 3 — Data freshness fallback:** if the 30-day query returns no rows for the target machines, widen progressively:
        1. rerun with `| where TimeGenerated > ago(90d)`
        2. rerun without a time filter and take the latest available results
        3. only conclude "BPA data unavailable" when the table does not exist in any discovered workspace, or when the all-time query still returns zero rows
       - **Step 4 — Report data age:** when BPA results are found, record and surface the most recent `TimeGenerated` value (e.g. "BPA results from 2025-05-15") alongside findings so users can assess freshness; if the data is older than 90 days, note this explicitly in the output
       - include mapped BPA coverage for the Azure VM alignment checks, including:
         - STOR-03 (`NtfsBlockSizeNotFormatted`)
         - STOR-02 (`TempDbSameVolume`)
         - STOR-04 (`TempDBFiles1PerCPU`, `TempDBFilesNotLess8`)
         - INST-03 (`InstantFileInitialization`)
         - INST-04/06/07/08/09/10 (`QueryStoreOn`, `BackupCompression`, `AutoShrink`, `AutoClose`, `PercentAutogrows`, `FilesAutogrowth`)
         - OPS and HADR operational checks where BPA evidence exists
     - **Tier 3 (Arc Run Command, fallback only):**
       - offer only when BPA is unavailable/incomplete (`bestPracticesAssessment = null`, no workspace with `SqlAssessment_CL` found after full enumeration, or required checks remain unresolved after exhausting all time windows)
       - after Tier 1/2, prompt:
         - "The Resource Graph scan identified {X} findings from {Y} checks. There are {Z} additional checks (storage layout, SQL config, maintenance jobs) that require live queries via Arc Run Command. Would you like me to run the full scan?"
         - choices: `["Yes — run full scan via Arc Run Command", "No — Resource Graph results are sufficient"]`
       - if approved, execute unresolved checks using consolidated scripts (SQL + OS), reusable command slots, and existing approval guardrails
   - produce one structured JSON result per check using this schema:
     ```json
     {
       "machineName": "ArcBox-SQL",
       "instanceName": "MSSQLSERVER",
       "checkId": "STOR-01",
       "checkName": "Data, log, and tempdb on separate drives",
       "category": "Storage",
       "status": "Fail",
       "currentValue": "Data: E:\\ Log: E:\\ TempDB: E:\\",
       "expectedValue": "Each file type on a distinct drive",
       "detail": "Data and log files share drive E:\\",
       "severity": "High",
       "remediation": "Separate data and log files onto distinct drives before Azure migration."
     }
     ```
   - allowed status values: `Pass` | `Fail` | `Warning` | `NotAssessed` | `NotApplicable`
   - allowed severity values: `Critical` | `High` | `Medium` | `Low` | `Informational`
   - classify findings consistently:
     - Critical = high migration landing risk (for example severe storage/tempdb or memory misconfiguration)
     - High = strong best-practice deviation likely requiring remediation
     - Medium/Low = optimisation improvements and quick wins
     - Informational = context-only findings
   - if the scan is skipped or unavailable, still include the report section and mark it as `Not assessed`

10. Azure Migrate Security Insights — vulnerability exposure (conditional, when an Azure Migrate project is in scope):

    a. **When to run:** execute this step whenever an Azure Migrate project was selected in Phase 1, regardless of whether utilisation or dependency data was successfully retrieved.

    b. **Query vulnerability records from Azure Resource Graph:**

       Run the following two ARG queries using `az graph query` scoped to the subscription(s) containing the Azure Migrate project:

       **Query A — Severity summary (executive headline):**
       ```kql
       machinesinventoryinsightsresources
       | where type in~ (
           "Microsoft.OffAzure/vmwareSites/machines/inventoryInsights/vulnerabilities",
           "Microsoft.OffAzure/hypervSites/machines/inventoryInsights/vulnerabilities",
           "Microsoft.OffAzure/serverSites/machines/inventoryInsights/vulnerabilities"
       )
       | extend
           cve = tostring(properties.cve),
           severity = tostring(properties.baseSeverity),
           cvss = todouble(properties.baseScore)
       | summarize
           vulnerabilityCount = count(),
           distinctCves = dcount(cve),
           maxCvss = max(cvss)
           by severity
       | order by maxCvss desc
       ```

       **Query B — Per-machine vulnerability detail (top 20 by CVSS score):**
       ```kql
       machinesinventoryinsightsresources
       | where type in~ (
           "Microsoft.OffAzure/vmwareSites/machines/inventoryInsights/vulnerabilities",
           "Microsoft.OffAzure/hypervSites/machines/inventoryInsights/vulnerabilities",
           "Microsoft.OffAzure/serverSites/machines/inventoryInsights/vulnerabilities"
       )
       | extend
           machineResourceId = tostring(split(id, "/inventoryInsights/")[0]),
           cve = tostring(properties.cve),
           cvss = todouble(properties.baseScore),
           severity = tostring(properties.baseSeverity),
           publishedOn = tostring(properties.publishedOn),
           scope = tostring(properties.vulnerabilityScopeId)
       | project machineResourceId, cve, cvss, severity, publishedOn, scope
       | order by cvss desc
       | limit 20
       ```

    c. **Handle empty results gracefully:**
       - if either query returns zero rows (no appliance, no discoveries, or table not populated), do NOT treat this as an error
       - record that Security Insights data is unavailable for this scope
       - surface in "Data gaps / follow-up questions": "Azure Migrate Security Insights data not found for the selected project scope. Ensure the Azure Migrate appliance is deployed and discovery has been completed, or that the appliance version supports Security Insights (preview feature)."
       - **important caveat:** the `machinesinventoryinsightsresources` ARG table and `inventoryInsights/vulnerabilities` resource types are a **preview/undocumented surface** — if the ARG query fails with a schema or resource-type error, treat this as the feature not being available in the current environment and record as a data gap rather than failing the analysis

    d. **Correlate machines to the Arc-enabled SQL estate:**
       - parse the `machineResourceId` field (prefix of the vulnerability record `id` before `/inventoryInsights/`) to extract the discovered machine resource ID
       - match discovered machine resource IDs or names (case-insensitive, strip domain suffix) to the Arc-enabled SQL machines collected in Phase 4
       - for correlated machines, record total vulnerability count, Critical/High count, and top CVSS score alongside the machine record
       - for machines that cannot be correlated (discovery machine names differ from Arc machine names), surface in "Data gaps / follow-up questions" with the unmatched names for manual reconciliation

    e. **Store Security Insights results for use in Phase 6:**
       - severity distribution: count per severity band (Critical, High, Medium, Low), total distinct CVEs, overall max CVSS
       - top CVEs: list of CVE IDs with CVSS score, severity, publication date, and software scope (from Query B output)
       - per-machine summary: for each correlated machine — total vulnerability count, Critical count, High count, max CVSS
       - data provenance note (preview ARG surface, not a committed public API)

    f. **If no Azure Migrate project was selected in Phase 1:**
       - skip this step entirely
       - do not add a Security posture section to the report; omit the section rather than producing empty placeholders
       - if the user asks about vulnerability data, refer them to deploying an Azure Migrate appliance


## Phase 5 - Enterprise downgrade audit

1. You MUST attempt an Enterprise downgrade audit before making any Enterprise → Standard recommendation.

2. Before executing ANY write operation in this phase (extension installation, run command creation, run command update, or run command deletion), you MUST obtain explicit user approval via `ask_user`:

   a. **Extension installation check** — before installing or upgrading the Arc Run Command extension (`Microsoft.Cplat.Core.RunCommandHandlerWindows`) on any machine:
      - Present: "The Arc Run Command extension needs to be installed on {machineName} to execute the Enterprise downgrade audit. This will install the 'Microsoft.Cplat.Core.RunCommandHandlerWindows' extension on this machine in subscription {subscriptionId}. Shall I proceed?"
      - Choices: `["Approve", "Skip this step", "Cancel analysis"]`
      - If Approved: proceed with installation
      - If Skipped: note that the audit could not be executed for this machine due to missing extension; surface in Data gaps / follow-up questions; continue with remaining machines
      - If Cancelled: stop the analysis gracefully and present any findings gathered so far

   b. **Run command execution approval** — before creating or updating a run command slot to execute an audit script on any machine, you MUST present the full script content to the user and obtain explicit approval:

      **Step 1 — Present the script for review.** Display the following block in full before requesting approval:

      ```
      **Target machine:** {machineName}
      **Instance:** {instanceName}
      **Purpose:** {brief description of what the script does}
      **Estimated execution time:** 1–3 minutes

      **Script to execute:**
      ```powershell
      {full script content — never summarise or truncate}
      ```

      Shall I execute this script on {machineName}?
      ```

      - Show the complete, untruncated script content (Pattern 1 — DMV audit, using the exact reference implementation from "Consolidated script patterns" below).
      - Briefly describe what each script does (e.g. "This script queries `sys.dm_db_persisted_sku_features` across all user databases to detect persisted Enterprise-only features.").
      - Never substitute a description in place of the full script content.

      **Step 2 — Request approval via `ask_user`.**
      - Choices: `["Approve and execute", "Skip this check", "Modify script first"]`
      - If **Approve and execute**: proceed with the run command create or update using the presented script
      - If **Skip this check**: note that the audit could not be executed for this machine; set `executionStatus = Skipped` in the output record; surface downstream impact (downgrade confidence falls to Low for this machine); note in Data gaps that the DMV audit was declined by the user; continue with remaining machines
      - If **Modify script first**: ask the user to supply their modifications, apply them, re-present the updated script in the same format (Step 1), and request approval again before proceeding
      - If the user declines without selecting a listed choice, treat as "Skip this check"

      **Batch approval — multiple machines with the same script template:**
      When the same script template (Pattern 1 — DMV audit, or Pattern 2 — runtime validation) will run on more than one machine in the same estate:
      1. Present the script template once, clearly labelled "Script template (identical for all listed machines)"
      2. List all target machines and instance names below the script block
      3. Request approval via `ask_user` with choices: `["Approve for all listed machines", "Approve individually per machine", "Skip all"]`
      - If **Approve for all listed machines**: proceed with run command submission for each listed machine using the presented template
      - If **Approve individually per machine**: loop through each machine, presenting the same script block with the specific `{machineName}` and `{instanceName}` substituted, and requesting single-machine approval before each submission
      - If **Skip all**: set `executionStatus = Skipped` for all listed machines; note in output; downgrade confidence falls to Low for all skipped machines

   c. **Run command deletion approval** — before deleting any run command resource (quota cleanup only):
      - Present: "To free run command quota on {machineName} (subscription: {subscriptionId}), I need to delete {count} existing run command resource(s): {names}. Shall I proceed?"
      - Choices: `["Approve", "Skip this step", "Cancel analysis"]`
      - If Approved: proceed with deletion
      - If Skipped: note that quota could not be freed; report as a pre-execution blocker; do not proceed with run command execution for this machine
      - If Cancelled: stop the analysis gracefully and present any findings gathered so far

3. Use a real execution path after tenant/subscription scope has been validated:
   - identify target Arc-enabled SQL instances from the validated scope dataset
   - for each target instance, enumerate relevant user databases (`database_id > 4`) that are online; include read-only databases because they can still return persisted feature evidence
   - execute the downgrade DMV across ALL user databases on each machine in a SINGLE consolidated script execution via Arc Run Command
   - the consolidated script MUST:
     - enumerate user databases dynamically (database_id > 4, state_desc = 'ONLINE')
     - execute `SELECT feature_name FROM sys.dm_db_persisted_sku_features` in each database
     - output structured JSON results for all databases in one response
   - this reduces round-trips from N (one per database) to 1 per machine
   - see "Consolidated script patterns" under Execution reliability considerations for the reference implementation

4. Capture results in a structured per-database output record using this minimum schema:
   - machineName
   - instanceName
   - databaseName
   - featureName
   - executionStatus
   - errorMessage
   - field names are mandatory and must use this exact camelCase naming
   - downstream processing depends on exact key matches; do not rename or reformat these keys

5. Populate structured output as follows:
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

6. Treat this step as a REQUIRED data acquisition step:
   - do not skip execution due to partial data availability
   - do not proceed as if the audit was completed unless results are actually obtained

7. Handle results as follows:
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

8. The downgrade recommendation MUST distinguish between:
   - persisted feature evidence
   - target edition support interpretation
   - runtime / operational feature usage results
   - remaining business-impact validation required

9. You MUST execute a separate runtime feature validation stage via Arc Run Command alongside the DMV findings before presenting any Enterprise → Standard downgrade as safe to proceed:
   - treat the DMV audit as persisted feature validation only
   - **Before submitting the runtime validation script**, apply the same script presentation and approval gate defined in step 2b above:
     - Present the full consolidated runtime script (Pattern 2 — runtime validation, from "Consolidated script patterns") in a code block to the user
     - Include: target machine, instance name, purpose ("This script checks for Always On AG configuration, Resource Governor, partitioned tables, and SQL Agent online index operations to identify Enterprise-only runtime feature usage"), and estimated execution time
     - Apply batch approval when the same script targets multiple machines (same rules as step 2b)
     - If the user declines, set `executionStatus = Skipped` for all runtime checks on that machine; note in output that runtime validation was declined; downgrade confidence falls to Low; continue analysis with available data
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

10. You MUST classify each Enterprise → Standard downgrade readiness using the following classification model:
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

11. The classification MUST be surfaced in:
   - Executive Summary (include classification status for any downgrade opportunities)
   - Key optimisation opportunities (for Enterprise → Standard recommendations)
   - Enterprise downgrade audit section (detailed classification)

12. You MUST NOT:
   - claim "no Enterprise features in use" without DMV evidence
   - provide Medium or High confidence downgrade recommendations without successful audit execution or equivalent evidence

13. Execution reliability considerations:

- You MUST consider execution reliability when using Arc Run Command or equivalent execution methods.

- **CRITICAL: Use exact command templates from `references/command-templates.md`**
  - When executing Arc Run Commands, use the exact command templates defined in `references/command-templates.md`
  - DO NOT attempt to construct run command submission commands from scratch
  - DO NOT modify or "improve" the templates — they are pre-validated patterns designed to avoid known failure modes
  - Template placeholders: `{machineName}`, `{resourceGroup}`, `{subscriptionId}`, `{location}`, `{slotName}`, `{scriptContent}`
  - The templates eliminate trial-and-error by handling:
    - Azure CLI argument parsing issues (quoting, special characters)
    - Command-line length limits (via temp file references)
    - Variable loss across tool calls (via single PowerShell call patterns)
    - Encoding requirements for complex SQL queries
  - Expected outcome: reliable, first-attempt execution success with zero argument parsing or encoding errors

- **CLI output hygiene — ALWAYS apply when parsing az output as JSON:**
  - Set `$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'` immediately before every `az` call whose output is assigned to a variable or piped to `ConvertFrom-Json`. CLI preview and deprecation warnings write to stdout and corrupt JSON parsing if not suppressed.
  - NEVER use `2>&1` in a pipeline that feeds `ConvertFrom-Json`. Stderr redirection folds warning lines into the stdout stream, causing `Unexpected character encountered while parsing value: W` parse failures.
  - The command templates in `references/command-templates.md` already include this env var — do not remove it.

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
  - When multiple machines require audit, submit run commands on EACH machine simultaneously using plain `az rest --method PUT` (no `--no-wait` — `az rest` does not support that flag)
  - Each PUT returns immediately with `provisioningState=Creating`; execution continues asynchronously on the Arc host
  - After all PUTs have been submitted, poll results across all machines using Template 3 (Poll) until each reaches `execState=Succeeded` or `execState=Failed`
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
  - ALWAYS use the exact command templates from `references/command-templates.md` for Arc Run Command submission
  - Specifically, use Template 2 (Create or Update Run Command via REST API) for all script submissions
  - ALWAYS use REST API (`az rest --method PUT`) for run command submission — never use `az connectedmachine run-command create/update` directly
  - ALWAYS encode scripts using `powershell -EncodedCommand <base64>` format
  - ALWAYS write JSON body to temp file and reference via `@$env:TEMP\filename.json`
  - This avoids all Azure CLI argument parsing issues with SQL queries containing joins, LIKE clauses, percent signs, and nested quotes
  - The template combines encoding and submission in a single PowerShell call to avoid variable loss
  - DO NOT attempt to pass complex SQL queries directly via `--script` — they will fail due to CLI argument parsing
  - DO NOT split encoding and submission across multiple tool calls — use the single-call template pattern

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
   - For SQL on Azure VM best-practices alignment findings (when executed):
     - surface Critical/High items as migration-preparation optimisation opportunities
     - surface Medium items as Quick wins where low-effort remediation is feasible
     - use alignment outcomes to adjust confidence in SQL Server on Azure VM target recommendations
     - if many unresolved Fail/Warning checks exist, note that clean Azure VM build-and-migrate may be safer than direct lift-and-shift

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

10. When Azure Migrate Security Insights data is available (collected in Phase 4 step 10):

    a. **Executive Summary headline:** include a one-line security posture headline, for example:
       - "Security posture: {N} Critical and {N} High CVEs identified across the estate (max CVSS: {score}) — {N} machines with Critical exposure flagged for priority migration."
       - only include this line when vulnerability data was retrieved; omit when no Security Insights data is available

    b. **Security posture — vulnerability exposure section:** produce this section using the template in `references/output-template.md`. Include:
       - severity distribution summary (Critical / High / Medium / Low counts, distinct CVE count, max CVSS)
       - top CVEs by CVSS score (table: CVE ID, CVSS, severity, age in days from publishedOn, affected software scope)
       - per-machine vulnerability summary (correlated Arc-enabled SQL machines only)
       - data provenance note: _"Security vulnerability data sourced from Azure Migrate Security Insights via the `machinesinventoryinsightsresources` Azure Resource Graph table (`inventoryInsights/vulnerabilities` resource types). This is a preview/undocumented surface — treat findings as indicative and validate via the Azure Migrate portal. Microsoft has not published a committed API schema for this data."_

    c. **Azure target recommendations — migration priority adjustment:**
       - flag any Arc-enabled SQL machine with one or more Critical or High CVEs as **higher priority for migration or remediation** in the Azure target recommendations section
       - append a migration priority note to affected machines, for example: "Priority: elevated — {N} Critical CVE(s) identified (max CVSS: {score}). Recommend accelerating migration or applying outstanding patches before migration window."
       - machines with no CVE data or only Medium/Low CVEs should not have their priority artificially lowered

    d. **Risks and blockers — unpatched vulnerabilities:**
       - if any Critical CVEs are present in the estate, add a risk entry: "Unpatched critical vulnerabilities ({N} Critical CVE(s), max CVSS {score}) identified on machines in the migration scope. These increase exposure during any extended migration timeline and should be treated as a migration risk factor."
       - if no Critical CVEs but High CVEs are present, add a lower-severity risk entry referencing the High CVE count

    e. **Confidence and evidence guardrail:**
       - always disclose that the Security Insights data comes from a preview ARG surface
       - do not claim definitive patch status — only report what the Security Insights data shows
       - if correlation between discovered machines and Arc SQL machines was partial or failed, note the correlation coverage in the section and in "Data gaps / follow-up questions"

11. Separate confirmed findings from assumptions, unknowns, or missing fields.

12. Produce the final answer using the structure in `references/output-template.md`.

13. Adaptive report formatting — scale the report presentation based on estate size:

    **Step 1 — Determine estate tier:**
    After collecting estate data in Phase 4, count the total number of distinct SQL Server instances in the validated dataset:
    - **Tier 1: ≤10 instances** — full inline detail (current behaviour, no change)
    - **Tier 2: 11–50 instances** — aggregated distributions + action-oriented groupings
    - **Tier 3: 51+ instances** — as Tier 2, plus top-N exception filtering, collapsible HTML sections (export only), and percentage-based heatmaps

    State the detected tier and instance count in the Estate summary opening line, for example:
    `Estate size: 47 instances across 32 machines — Tier 2 (aggregated) report format applied.`

    **Step 2 — Tier 1 (≤10 instances):**
    Use all output-template.md sections as-is with full inline detail. No changes to current behaviour.

    **Step 3 — Tier 2 (11–50 instances) section overrides:**

    - **Estate summary — replace inline instance/machine names with distribution counts:**
      ```
      SQL instances: {N} across {M} machines
        Editions:  {N} Enterprise | {N} Standard | {N} Express
        Versions:  {N}× SQL 2022 | {N}× SQL 2019 | {N}× SQL 2016 (EoS) | {N}× SQL 2014 (EoS)
        Status:    {N} Connected | {N} Unreachable | {N} Disconnected
      ```
      Continue using the existing licensing, backup/monitoring/security, and utilisation subsections unchanged.

    - **Machine inventory — replace inline machine listing with action-oriented groupings table:**
      Present this table in the Estate summary section immediately after the distribution block:
      ```
      | Migration target                    | Machines | Instances | Key characteristic                |
      |-------------------------------------|----------|-----------|-----------------------------------|
      | Azure SQL MI (Ready)                | {N}      | {N}       | No blockers identified            |
      | Azure SQL MI (Remediation needed)   | {N}      | {N}       | Known blockers — see Appendix A   |
      | SQL on Azure VM                     | {N}      | {N}       | MI-blocked, VM-ready              |
      | Requires further assessment         | {N}      | {N}       | Unreachable or no assessment data |
      ```
      Move the full machine inventory (one row per machine with all properties) to Appendix A.

    - **Enterprise downgrade audit — lead with summary counts; show AMBER/RED detail inline, list GREEN by name only:**
      Open the section with:
      ```
      Downgrade candidates: {N} Enterprise instances
        GREEN (ready):    {N}
        AMBER (pending):  {N}
        RED (blocked):    {N}
      ```
      Then list GREEN instance names in a compact block (no per-database detail inline):
      ```
      GREEN instances (no blockers — full DMV results in Appendix B):
        - {instanceName} on {machineName}
        - ...
      ```
      Follow with the full existing structured audit table and runtime validation table for AMBER and RED records only.
      Move full per-database DMV results for GREEN instances to Appendix B.

    - **BPA alignment — replace per-machine detail tables with an estate-wide findings heatmap:**
      ```
      | Check ID | Check name            | Category | Severity      | Machines affected |
      |----------|-----------------------|----------|---------------|-------------------|
      | STOR-03  | NTFS block size       | Storage  | High          | {N}/{total}       |
      | INST-07  | Auto-shrink enabled   | Config   | Medium        | {N}/{total}       |
      | ...                                                                               |
      ```
      Sort by severity descending (Critical → High → Medium → Low → Informational), then by affected machine count descending within each severity band.
      Move per-machine BPA detail tables to Appendix C.
      Keep the existing pre-migration remediation checklist in the body for Critical and High findings only.

    - **Azure target recommendations — replace per-instance narrative with an action-grouped summary table:**
      ```
      | Migration target  | Instances | Recommended action             | Confidence |
      |-------------------|-----------|--------------------------------|------------|
      | Azure SQL MI      | {N}       | Ready — migrate in Wave 1      | High       |
      | Azure SQL MI      | {N}       | Remediation needed before MI   | Medium     |
      | SQL on Azure VM   | {N}       | Lift-and-shift candidates      | Medium     |
      | Further assess    | {N}       | Additional data required       | Low        |
      ```
      Follow with migration sequencing recommendations (waves) and SKU right-sizing confidence at a group level.
      Move per-instance TCO and licensing notes to Appendix D.

    - **Appendix (new section for Tier 2+):**
      Add an `# Appendix` section after `# Data gaps / follow-up questions` with the following sub-sections:
      - **Appendix A — Full machine inventory:** one row per machine with all properties (name, OS, version, edition, vCores, status, assessment status)
      - **Appendix B — Enterprise downgrade audit: GREEN instance details:** full per-database DMV results for GREEN-classified instances
      - **Appendix C — BPA alignment: per-machine detail:** full check-by-check BPA findings tables for each machine
      - **Appendix D — Azure target recommendation details:** per-instance TCO notes, licensing position, and AHB eligibility by machine

    **Step 4 — Tier 3 (51+ instances), additional overrides beyond Tier 2:**

    - **Top-N exceptions in report body (default top 10, configurable):**
      - Enterprise downgrade audit body: show only the top 10 AMBER/RED instances ordered by severity (RED first). State: `"Showing top 10 of {total} AMBER/RED findings — see Appendix B for complete list."`
      - BPA heatmap body: show only the top 10 failing checks ordered by machines-affected count. State: `"Showing top 10 of {total} failing checks — see Appendix C for complete list."`
      - Azure target summary table: group by target category (no top-N truncation needed — the table already aggregates by category).

    - **Percentage-based BPA heatmap column:**
      Replace the raw `{N}/{total}` machines-affected column with `{N}/{total} ({pct}%)` for all BPA heatmap rows.

    - **Collapsible HTML sections (HTML/PDF export only — Phase 7):**
      When generating HTML output, wrap Appendix sub-sections and per-machine detail blocks in `<details><summary>…</summary>` elements so they can be expanded/collapsed in the browser.
      Apply to: Appendix A (machine inventory), Appendix B (GREEN DMV details), Appendix C (per-machine BPA tables), Appendix D (per-instance TCO details).
      Markdown and plain-text output must include all content without collapsing (use headings only).

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
   - required headings: `Executive Summary`, `Estate summary`, `Key optimisation opportunities`, `Enterprise downgrade audit`, `SQL on Azure VM best practices alignment`, `Security posture — vulnerability exposure`, `Quick wins`, `Strategic moves`, `Azure target recommendations`, `Risks and blockers`, `Data gaps / follow-up questions`
     (include `SQL on Azure VM best practices alignment` even when the scan is skipped, and state `Not assessed` in that section; include `Security posture — vulnerability exposure` only when an Azure Migrate project was selected and Security Insights data was queried — omit the section entirely if no Azure Migrate project was in scope)
   - failure response format:
     - `PDF export status: Failed`
     - `Reason: {error_detail}`
     - `HTML output: {absolute_html_path}`
     - `Suggested manual command: {edge_or_chrome_command}`

6. Collapsible sections for Tier 3 HTML export:
   - When the estate is Tier 3 (51+ instances), wrap each Appendix sub-section in a `<details><summary>` block so large data tables are collapsed by default in the browser:
     ```html
     <details>
       <summary><strong>Appendix A — Full machine inventory</strong> (47 machines — click to expand)</summary>
       <!-- machine inventory table here -->
     </details>
     ```
     Replace the example machine count with the actual count from the estate. Use the same actual-value substitution for all `{N}` and `{M}` placeholders throughout the report.
   - Apply to: Appendix A, Appendix B, Appendix C, Appendix D.
   - Do not collapse main report body sections (Executive Summary through Data gaps).
   - This does not apply to Tier 1 or Tier 2 exports — those use normal headings throughout.

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
 
## Change approval guardrails

- Never modify customer Azure resources without explicit user approval via `ask_user`.
- Present the action, target resource, and subscription before requesting approval.
- Use choices: `["Approve", "Skip this step", "Cancel analysis"]` for all approval prompts.
- If the user selects **Approve**: proceed with the action.
- If the user selects **Skip this step**: note the skipped action in output; surface any downstream impact (e.g. "Enterprise downgrade audit could not be executed because run command execution was declined"); continue with available data.
- If the user selects **Cancel analysis**: stop gracefully and present any findings gathered so far.
- Read-only operations (Resource Graph queries, ARM GET requests, `az account list`, `az account show`) do NOT require approval and must not be unnecessarily gated.
- The following categories of action MUST be preceded by an approval prompt:
  - Extension installation or upgrade on Arc-enabled machines
  - Arc Run Command resource creation
  - Arc Run Command resource update (this triggers execution)
  - Arc Run Command resource deletion
  - Any ARM PUT, POST, PATCH, or DELETE that modifies resources in the customer's subscription
  - Any `az rest --method PUT/POST/PATCH/DELETE` call that modifies state

## Script execution transparency guardrails

- Always present the full script content to the user before executing via Arc Run Command. Never summarise, truncate, or substitute a description in place of the actual script.
- Use the following presentation format for every script before requesting approval:

  ```
  **Target machine:** {machineName}
  **Instance:** {instanceName}
  **Purpose:** {brief description}
  **Estimated execution time:** {estimate}

  **Script to execute:**
  ```powershell
  {full script content}
  ```

  Shall I execute this script on {machineName}?
  ```

- Include target machine, instance name, purpose description, and estimated execution time in every script presentation.
- Use choices `["Approve and execute", "Skip this check", "Modify script first"]` for script execution approval prompts.
- Offer batch approval when the same script template targets multiple machines: present the script once, list all target machines, and offer `["Approve for all listed machines", "Approve individually per machine", "Skip all"]`.
- If the user declines (Skip this check or Skip all), note the skipped check in output, set `executionStatus = Skipped`, and adjust downgrade confidence to Low for any affected machines.
- If the user selects **Modify script first**, collect their changes, re-present the updated script in full, and request approval again before proceeding.
- No script may ever be submitted to Arc Run Command without the user first seeing the complete script content and explicitly approving execution.

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

- If `skuRecommendationResults` or `serverAssessments` contains usable data, use it regardless of `assessmentUploadTime`. Treat a null or stale `assessmentUploadTime` as a freshness caveat, not a reason to suppress populated recommendation data.

- When `assessment.enabled = true`, `assessmentUploadTime = null`, and recommendation fields are not populated:
  - treat this as a **sync-pending state**, not a data absence
  - do not report "no assessment data uploaded" as a data gap
  - instead report: "Assessment collected but ARM sync pending — check Azure portal for latest results or trigger 'Run Assessment' to force sync"

- When reporting assessment gaps in output, distinguish between:
  - "Assessment not enabled" (assessment.enabled = false) — genuine gap, recommend enabling
  - "Assessment enabled, data available but freshness timestamp missing" (enabled = true, assessmentUploadTime = null, recommendation fields populated) — use the available recommendation data and disclose the missing timestamp
  - "Assessment enabled, sync pending" (enabled = true, assessmentUploadTime = null, recommendation fields empty) — data likely exists in portal
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

- Azure Migrate resource type and API version:
  - `Microsoft.Migrate/migrateProjects` is the **project container** — use it only for project discovery (already returned by the consolidated ARG query). It supports api-versions up to `2020-06-01-preview` only and has no assessment or utilisation sub-resources.
  - `Microsoft.Migrate/assessmentProjects` is the **assessment data store** — use api-version `2023-03-15` for all assessment and assessed-machine queries.
  - do NOT query `migrateProjects` for assessments; doing so returns `NoRegisteredProviderFound` for any version later than `2020-06-01-preview`.
  - if the `assessmentProjects` api-version `2023-03-15` is not accepted, fall back to `2019-10-01` then `2018-02-02`; if all versions fail, surface the API error and continue without Migrate data

- Dependency data has two sources with different access paths. The newer **Azure Migrate Dependency Map** (`Microsoft.DependencyMap/maps`) IS retrievable programmatically via the `Microsoft.DependencyMap` REST API (connection data lives in a graph datastore that is not in Resource Graph, but the export/view actions return it) — this is the primary path; use command-templates.md Templates 7–9. The older **classic agentless Azure Migrate appliance** dependency data is NOT accessible via REST API or PowerShell and can only be exported as CSV via portal **Manage Dependencies > Export dependencies** — use this only as a fallback when no Dependency Map resource exists. Confirm the Dependency Map API version (`2025-05-01-preview`, falling back to `2025-07-01-preview` then `2025-01-31-preview`).

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
The detailed report structure below is the canonical section order and expands core customer-facing sections into explicit audit and planning blocks.

1. Executive Summary (3–5 concise bullet points for CIO/IT Director audience, highlighting key risks, optimisation opportunities, and Azure direction)
2. Estate summary
3. Key optimisation opportunities
4. Enterprise downgrade audit
5. SQL on Azure VM best practices alignment (when executed, or state Not assessed if skipped)
6. Quick wins
7. Strategic moves
8. Azure target recommendations
9. Risks and blockers
10. Data gaps / follow-up questions
11. Appendix (Tier 2 and Tier 3 only — omit for Tier 1 estates with ≤10 instances):
    - Appendix A — Full machine inventory
    - Appendix B — Enterprise downgrade audit: GREEN instance details
    - Appendix C — BPA alignment: per-machine detail
    - Appendix D — Azure target recommendation details
