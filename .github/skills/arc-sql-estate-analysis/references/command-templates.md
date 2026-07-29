# PowerShell Command Templates

This file contains exact, copy-paste-ready PowerShell command templates for Azure Arc Run Command operations. These templates are designed to eliminate trial-and-error execution by providing pre-validated patterns that avoid common failure modes.

## Design Principles

1. **Always use REST API (az rest --method PUT)** for run command submission — never use `az connectedmachine run-command create/update` directly, as it has argument length limits and quoting issues
2. **Always write the JSON body to a temp file** and reference via `@$env:TEMP\filename.json` — never pass complex JSON inline
3. **Always encode scripts separately** then insert into the body — never attempt to pass raw SQL or PowerShell via CLI arguments
4. **Use a single PowerShell call** for the encode-and-submit workflow — do not split across multiple tool calls that lose variable context
5. **Use reusable command slots** to avoid quota limits — update existing slots rather than creating new commands
6. **Suppress CLI warnings before JSON output** — set `$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'` immediately before any `az` call whose output is assigned to a variable or piped to `ConvertFrom-Json`. CLI preview and deprecation warnings are written to stdout and corrupt JSON parsing if not suppressed. Never use `2>&1` in a pipeline that feeds `ConvertFrom-Json` — stderr redirection folds warnings into the JSON stream and causes parse failures.

## Template Categories

### 1. List Existing Run Commands

**Purpose:** Check existing run command slots on a machine to determine whether to create or update.

**Usage:** Use this before attempting to create a run command to avoid quota conflicts.

```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az connectedmachine run-command list --machine-name {machineName} --resource-group {resourceGroup} --query "[].{name:name, status:provisioningState}" -o json
```

**Placeholders:**
- `{machineName}` — Arc machine name (e.g., `ArcBox-SQL-01`)
- `{resourceGroup}` — Resource group name

**Expected output:** JSON array of run command resources with name and provisioning state.

---

### 1a. Verify RunCommandHandler Extension Health (pre-flight)

**Purpose:** Confirm the `RunCommandHandlerWindows` extension is present and healthy on the target machine **before** submitting a Run Command. Older Arc agents (observed on agent 1.65) do not always auto-provision this extension; when it is absent, a `PUT` to `runCommands/{slot}` returns `provisioningState=Creating` optimistically but the slot never materialises and a follow-up `GET` returns `HCRP404`.

**Usage:** Run this once per machine before the first Run Command submission. If the extension is missing or not `Succeeded`, do not trust an optimistic `Creating` response — either install/repair the extension (Phase 5 write approval) or record the machine as audit-incomplete in Data gaps.

```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az connectedmachine extension list --machine-name {machineName} --resource-group {resourceGroup} --subscription {subscriptionId} --query "[?contains(name, 'RunCommandHandlerWindows')].{name:name, state:provisioningState}" -o json
```

**Placeholders:**
- `{machineName}` — Arc machine name
- `{resourceGroup}` — Resource group name
- `{subscriptionId}` — Azure subscription ID (GUID)

**Expected output:** A single element with `provisioningState = Succeeded`. An empty array (or a non-`Succeeded` state) means the machine cannot reliably run commands — see Template 2's post-submission verification step.

---

### 2. Create or Update Run Command via REST API

**Purpose:** Submit a PowerShell script to an Arc machine via Run Command using the REST API to avoid Azure CLI argument parsing issues.

**Usage:** Use this for all run command submissions. This template handles encoding, temp file creation, and REST API submission in a single PowerShell call.

**Why REST API:** The `az connectedmachine run-command create/update` commands have known issues with:
- Complex SQL queries containing joins, LIKE clauses, percent signs, and nested quotes
- Command-line length limits (typically 8191 characters on Windows)
- Argument parsing errors with special characters

#### Template

```powershell
$script = @'
{scriptContent}
'@
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
$scriptPayload = "powershell -EncodedCommand $encoded"
$body = @{
    location = "{location}"
    properties = @{
        source = @{ script = $scriptPayload }
    }
} | ConvertTo-Json -Depth 5 -Compress
$body | Set-Content "$env:TEMP\rc-{slotName}.json" -NoNewline
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az rest --method PUT --url "https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.HybridCompute/machines/{machineName}/runCommands/{slotName}?api-version=2024-07-10" --body "@$env:TEMP\rc-{slotName}.json" -o json
```

**Placeholders:**
- `{scriptContent}` — The full PowerShell script to execute (can be multi-line, with SQL queries, special characters, etc.)
- `{location}` — Azure region of the Arc machine (e.g., `eastus`, `westeurope`)
- `{slotName}` — Run command slot name (e.g., `estate-audit-ArcBox-SQL-01`)
- `{subscriptionId}` — Azure subscription ID (GUID)
- `{resourceGroup}` — Resource group name
- `{machineName}` — Arc machine name

**What this template does:**
1. Takes the raw PowerShell script and encodes it to Base64 Unicode
2. Wraps the encoded script in `powershell -EncodedCommand` format
3. Builds a JSON body with the location and script payload
4. Writes the JSON body to a temp file to avoid command-line length limits
5. Submits the run command via REST API using the temp file reference

**Why encoding is required:**
- Encoding eliminates ALL Azure CLI argument parsing issues
- SQL queries with `%`, `'`, `"`, joins, and LIKE clauses work reliably
- No need to escape special characters or worry about command-line length

**Expected output:** JSON response with run command resource details and provisioning state.

> **Verify the slot after PUT — do not trust the optimistic `Creating` response.** The `PUT` returns immediately with `provisioningState=Creating` even on machines where the slot will never materialise (missing/unhealthy `RunCommandHandlerWindows` extension — see Template 1a). Always confirm the slot actually exists before polling for results:
>
> ```powershell
> $env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
> az connectedmachine run-command show --machine-name {machineName} --resource-group {resourceGroup} --subscription {subscriptionId} --name {slotName} --query "provisioningState" -o tsv
> ```
>
> If this returns `HCRP404` / resource-not-found (rather than `Creating`/`Succeeded`) within ~60s of the PUT, the extension is not servicing Run Commands on that host. Repair/install the extension (Phase 5 write approval) and retry, or record the machine as audit-incomplete in Data gaps — never report a downgrade/security result derived from a slot that never persisted.

---

### 3. Poll Run Command Status and Retrieve Results

**Purpose:** Check the execution status of a run command and retrieve output once execution completes.

**Usage:** Poll this after submitting a run command to check for completion and retrieve results.

```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az connectedmachine run-command show --machine-name {machineName} --resource-group {resourceGroup} --name {slotName} --query "{status:provisioningState, execState:instanceView.executionState, exitCode:instanceView.exitCode, stdout:instanceView.output, stderr:instanceView.error}" -o json
```

**Placeholders:**
- `{machineName}` — Arc machine name
- `{resourceGroup}` — Resource group name
- `{slotName}` — Run command slot name

**Expected output:** JSON object with:
- `status` — Provisioning state (e.g., `Succeeded`, `Failed`, `Running`)
- `execState` — Execution state (e.g., `Succeeded`, `Failed`, `Running`)
- `exitCode` — Exit code (0 = success)
- `stdout` — Standard output from the script
- `stderr` — Standard error from the script

**Polling strategy:**
- Poll immediately after submission
- If `execState` is `Running`, wait 15-30 seconds and poll again
- If `execState` is `Succeeded` or `Failed`, retrieve output from `stdout`/`stderr`
- Typical execution time: 1-3 minutes for SQL DMV queries

---

### 4. Delete Run Command (Quota Cleanup)

**Purpose:** Delete a run command resource to free quota when necessary.

**Usage:** Use only when quota is exhausted (25/25) and reusable slots cannot be updated. Deletions are slow (minutes per command) and should be avoided when possible.

```powershell
az rest --method DELETE --url "https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.HybridCompute/machines/{machineName}/runCommands/{slotName}?api-version=2024-07-10"
```

**Placeholders:**
- `{subscriptionId}` — Azure subscription ID
- `{resourceGroup}` — Resource group name
- `{machineName}` — Arc machine name
- `{slotName}` — Run command slot name to delete

**Important notes:**
- Deletions are processed sequentially by the Arc agent and may take 5-10 minutes to propagate
- DO NOT rely on deletions as a fast way to free quota
- Prefer updating existing reusable slots instead
- If quota cleanup is required, submit batch deletions and allow 5-10 minutes before re-checking capacity

---

## Common Failure Modes and How Templates Avoid Them

### Failure Mode 1: Azure CLI Argument Parsing Errors

**Problem:**
```bash
az connectedmachine run-command create --script "SELECT * FROM sys.databases WHERE name LIKE '%test%'"
# ERROR: unrecognized arguments: %test%
```

**Why it happens:** Azure CLI interprets `%`, `'`, `"`, and other special characters as shell metacharacters.

**How template avoids it:** Template 2 (Create/Update via REST) encodes the entire script to Base64, eliminating all argument parsing issues.

---

### Failure Mode 2: Command Line Too Long

**Problem:**
```bash
az connectedmachine run-command create --script "... 10KB SQL query ..."
# ERROR: The command line is too long.
```

**Why it happens:** Windows command line has an ~8191 character limit. Complex scripts exceed this.

**How template avoids it:** Template 2 writes the JSON body to a temp file and references it via `@$env:TEMP\rc-{slotName}.json`, bypassing command-line length limits entirely.

---

### Failure Mode 3: Variable Loss Across Multiple Tool Calls

**Problem:**
```bash
# Tool call 1: Encode script
$encoded = [Convert]::ToBase64String(...)

# Tool call 2: Submit run command (fails because $encoded is lost)
az connectedmachine run-command create --script "powershell -EncodedCommand $encoded"
# ERROR: $encoded is undefined
```

**Why it happens:** Each tool call is a separate PowerShell session. Variables from call 1 are not available in call 2.

**How template avoids it:** Template 2 combines encoding and submission into a single PowerShell call, preserving all variables in scope.

---

### Failure Mode 4: Quota Exhaustion (25 Command Limit)

**Problem:**
```bash
az connectedmachine run-command create --name new-command-123 ...
# ERROR: Cannot create more than 25 run commands per machine
```

**Why it happens:** Azure Arc enforces a 25 run command limit per machine. Creating new commands each time exhausts quota quickly.

**How template avoids it:**
- Use fixed, reusable slot names (e.g., `estate-audit-{machineName}-01`)
- Check for existing slots with Template 1 (List)
- Update existing slots with Template 2 (Create/Update via REST) instead of creating new ones
- This approach never exceeds 2 slots per machine (one for DMV audit, one for runtime checks)

---

### Failure Mode 5: JSON Body Inline Parsing Issues

**Problem:**
```bash
az rest --body '{"properties":{"source":{"script":"SELECT * FROM sys.databases WHERE name LIKE ''%test%''"}}}' ...
# ERROR: Invalid JSON or escaped quotes mangled
```

**Why it happens:** Passing complex JSON inline requires nested escaping that is error-prone and varies by shell.

**How template avoids it:** Template 2 builds the JSON body using PowerShell's `ConvertTo-Json` and writes it to a temp file, ensuring correct JSON structure without manual escaping.

---

## Resource Graph Query Templates

While this file focuses on Arc Run Command execution, the skill also relies on Azure Resource Graph queries for estate inventory. Key queries are documented here and referenced from SKILL.md Phase 2 and Phase 4.

### 5. Consolidated Estate ARG Query

**Purpose:** Retrieve all estate data — SQL instances, databases, Arc-enabled machines, and Azure Migrate projects — in a single Resource Graph round-trip. This replaces multiple individual queries and individual ARM GET calls.

**Usage:** Execute once after scope validation (Phase 2). Post-process results locally to separate and correlate resource types. Do not make individual ARM GET calls for data that is already returned by this query.

```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az graph query -q "resources | where (type =~ 'microsoft.azurearcdata/sqlserverinstances' or type =~ 'microsoft.azurearcdata/sqlserverinstances/databases' or type =~ 'microsoft.hybridcompute/machines' or type =~ 'microsoft.migrate/migrateprojects') | where subscriptionId in ('{sub1}','{sub2}') | project id, name, type, resourceGroup, subscriptionId, location, properties, tags" --subscriptions {subscriptionIds} --first 1000 -o json
```

**Placeholders:**
- `'{sub1}','{sub2}'` — subscription IDs as a comma-separated quoted list inside the KQL `in()` operator
- `{subscriptionIds}` — subscription IDs as a space-separated list for the `--subscriptions` parameter
- Replace both placeholders with the confirmed subscription IDs from Phase 1

**KQL equivalent (for MCP tools or portal query):**
```kql
resources
| where type =~ 'microsoft.azurearcdata/sqlserverinstances'
    or type =~ 'microsoft.azurearcdata/sqlserverinstances/databases'
    or type =~ 'microsoft.hybridcompute/machines'
    or type =~ 'microsoft.migrate/migrateprojects'
| where subscriptionId in ({subscriptionIds})
| project id, name, type, resourceGroup, subscriptionId, location, properties, tags
```

**Data returned (all available in Resource Graph — no additional ARM calls needed):**

| Resource type | Key properties returned |
|---|---|
| `microsoft.azurearcdata/sqlserverinstances` | `version`, `edition`, `vCores`, `licenseType`, `status`, `backupPolicy`, `monitoring`, `azureDefenderStatus`, `alwaysOnRole`, `tcpStaticPorts`, `migration` (includes `assessment.enabled`, `assessmentUploadTime`, `skuRecommendationResults`, `serverAssessments`) |
| `microsoft.azurearcdata/sqlserverinstances/databases` | `state`, `sizeMB`, `compatibilityLevel`, `recoveryMode`, `backupInformation`, `collationName`, `databaseOptions` |
| `microsoft.hybridcompute/machines` | `osSku`, `osName`, `status`, `detectedProperties` (coreCount, memory, processorNames) |
| `microsoft.migrate/migrateprojects` | `id`, `name`, `resourceGroup`, `subscriptionId`, `location` |

**Data NOT in Resource Graph (requires separate justified API calls):**
- Azure Migrate assessed machine utilisation metrics (CPU/memory baselines, confidence scores) — Migrate API
- Application dependency data — Log Analytics workspace queries over VM Insights tables (`VMConnection`, `VMProcess`, `VMComputer`, `VMBoundPort`) when the customer has pre-enabled the prerequisite; optional Azure Migrate `Microsoft.DependencyMap` REST API enrichment; or classic Azure Migrate portal CSV export (fallback)

**Post-query local processing:**
1. Split rows by `type` field into four groups: instances, databases, machines, Migrate projects
2. Group databases by parent instance using the resource ID hierarchy (database `id` contains the parent instance `id` as a prefix)
3. Correlate machines to instances: match instance `properties.containerResourceId` to machine `id`, or match on machine `name`
4. Extract assessment data from each instance's `properties.migration` field
5. Present any Migrate projects to the user for selection (Phase 1 step 7)

**Pagination for large estates:**
- Resource Graph returns a maximum of 1,000 rows per request
- Always pass `--first 1000` to the CLI command
- If the response contains a `skip_token` field, retrieve the next page:

```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az graph query -q "{same query}" --subscriptions {subscriptionIds} --first 1000 --skip-token "{skipToken}" -o json
```

- Repeat until the response contains no `skip_token`
- Concatenate all pages before processing

**Expected output:** JSON array where each element has `id`, `name`, `type`, `resourceGroup`, `subscriptionId`, `location`, `properties`, `tags`.

---

### 6. Scope Validation Query

**Purpose:** Lightweight pre-check to confirm Arc resources are visible in the selected scope before issuing the full consolidated query. Used in Phase 2.

```kql
resources
| where type =~ 'microsoft.hybridcompute/machines' or type =~ 'microsoft.azurearcdata/sqlserverinstances'
| summarize count() by type, subscriptionId
```

**Azure CLI equivalent:**
```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az graph query -q "resources | where type =~ 'microsoft.hybridcompute/machines' or type =~ 'microsoft.azurearcdata/sqlserverinstances' | summarize count() by type, subscriptionId" --subscriptions {subscriptionIds} -o json
```

**Expected output:** Summary count of resource types per subscription. Use to confirm scope before issuing the full consolidated query.

---

**Legacy example — Enumerate Arc-enabled SQL instances with join (superseded):**

> **Note:** The following join-based query is superseded by Template 5 (Consolidated Estate ARG Query) above. It is retained here for reference only. Do not use it for new analysis — use the consolidated query instead.

```
resources
| where type == "microsoft.azurearcdata/sqlserverinstances"
| project id, name, resourceGroup, subscriptionId, location, version = properties.version, edition = properties.edition, machineName = tostring(split(properties.containerResourceId, '/')[8])
| join kind=inner (
    resources
    | where type == "microsoft.hybridcompute/machines"
    | project machineName = name, machineResourceGroup = resourceGroup, machineSubscriptionId = subscriptionId, status = properties.status
  ) on machineName
```

These queries are executed directly via Azure CLI or GitHub Copilot MCP tools and do not require the same encoding/quoting considerations as Arc Run Command scripts.

---

## Azure Monitor VM Insights — dependency query path (preferred optional source)

> **Consumer-managed prerequisite only:** the queries below assume the customer has already enabled
> VM Insights dependency monitoring on the Arc-enabled SQL machines and allowed it to collect for
> roughly **24 hours**. The analysis agent may query this data, but must **never** deploy the
> workspace, AMA / Dependency Agent extensions, DCR, or DCR associations itself.

**Detect-and-guide rule:** if the prerequisite check returns no `VMConnection` data in scope, print
`references/templates/dependency-monitoring/README.md` plus the deployment/teardown templates and
note that about **24 hours of collection** is required before dependency analysis is usable.

### Workspace prerequisite / data-availability check

**Purpose:** confirm that VM Insights dependency tables are populated before attempting dependency
analysis. This is the primary dependency-data check in Phase 4 step 8.

```kusto
VMConnection
| where TimeGenerated >= ago(7d)
| summarize totalConnections = count(), firstSeen = min(TimeGenerated), lastSeen = max(TimeGenerated), sourceMachines = dcount(Computer), destinationMachines = dcount(RemoteIp)
```

**Azure CLI equivalent:**
```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az monitor log-analytics query -w {workspaceId} --analytics-query "VMConnection | where TimeGenerated >= ago(7d) | summarize totalConnections = count(), firstSeen = min(TimeGenerated), lastSeen = max(TimeGenerated), sourceMachines = dcount(Computer), destinationMachines = dcount(RemoteIp)" -o json
```

**Expected output:** one row with connection counts and the effective collection window. If
`totalConnections = 0` (or no row is returned), dependency monitoring is not ready in this scope.

### SQL-focused dependency topology query

**Purpose:** extract the SQL-relevant inbound/outbound dependency graph from VM Insights using the
connection table, with optional process and machine context.

```kusto
let sqlHosts = dynamic([{sqlHostNames}]);
let recentMachines = materialize(
    VMComputer
    | summarize arg_max(TimeGenerated, *) by _ResourceId
    | project Computer, AzureResourceName, _ResourceId, Ipv4Addresses, DnsNames
);
VMConnection
| where TimeGenerated >= ago(7d)
| where Direction in ('inbound', 'outbound')
| where Computer in~ (sqlHosts)
   or DestinationPort in (1433, 1434, 4022)
   or ProcessName contains_cs 'sql'
| summarize Observations = count(), BytesSent = sum(BytesSent), BytesReceived = sum(BytesReceived), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by Computer, Direction, ProcessName, SourceIp, DestinationIp, DestinationPort, Protocol, RemoteIp
| join kind=leftouter recentMachines on Computer
| order by Observations desc
```

**Interpretation:** use this as the main dependency-map extraction query. The output identifies top
SQL-relevant flows, inbound/outbound direction, active ports, and the observation window.

### Supporting process inventory query

**Purpose:** validate SQL-related executables and supporting services seen on the monitored hosts.

```kusto
let sqlHosts = dynamic([{sqlHostNames}]);
VMProcess
| where TimeGenerated >= ago(7d)
| where Computer in~ (sqlHosts)
| where ExecutableName has_cs 'sql' or CommandLine contains_cs 'sql' or CompanyName has_cs 'Microsoft'
| summarize arg_max(TimeGenerated, *) by _ResourceId
| project Computer, ExecutableName, DisplayName, CommandLine, CompanyName, StartTime
| order by Computer asc, ExecutableName asc
```

### Supporting machine / bound-port query

**Purpose:** confirm machine identity, DNS/IP evidence, and open listener ports for correlated SQL
machines.

```kusto
let sqlHosts = dynamic([{sqlHostNames}]);
let machines =
    VMComputer
    | summarize arg_max(TimeGenerated, *) by _ResourceId
    | where Computer in~ (sqlHosts) or AzureResourceName in~ (sqlHosts)
    | project Computer, AzureResourceName, OperatingSystemFullName, DnsNames, Ipv4Addresses;
let ports =
    VMBoundPort
    | where TimeGenerated >= ago(7d)
    | where Computer in~ (sqlHosts)
    | where Ip != '127.0.0.1'
    | summarize arg_max(TimeGenerated, LinksLive) by PortId
    | project Computer, ProcessName, Port, Ip, Protocol, IsWildcardBind, LinksLive;
machines
| join kind=leftouter ports on Computer
| order by Computer asc, Port asc
```

---

### 7. List Azure Migrate Dependency Map Resources

**Purpose:** Discover optional `Microsoft.DependencyMap/maps` resources in scope and resolve the `{mapName}` required by the dependency view and export operations. Use this only for the optional Azure Migrate dependency-enrichment path in Phase 4 after the VM Insights path has been checked.

**Why direct API:** Dependency connection data is held in a graph-based datastore that is **not** queryable via Azure Resource Graph. The `Microsoft.DependencyMap` resource provider is the supported programmatic path. This is distinct from classic agentless Azure Migrate appliance dependency analysis (which has no API — portal CSV export only).

**List by subscription:**
```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az rest --method GET --url "https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.DependencyMap/maps?api-version={dependencyMapApiVersion}" -o json
```

**List by resource group:**
```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az rest --method GET --url "https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.DependencyMap/maps?api-version={dependencyMapApiVersion}" -o json
```

**Placeholders:**
- `{subscriptionId}` — Subscription ID (GUID)
- `{resourceGroup}` — Resource group containing the Dependency Map resource
- `{dependencyMapApiVersion}` — Dependency Map API version. Default `2025-05-01-preview`. Confirm the tenant accepts this version before relying on it; `2025-07-01-preview` is the latest published version. If a version is rejected, fall back to `2025-07-01-preview` then `2025-01-31-preview`.

**Expected output:** JSON `value[]` of map resources. Use `value[].name` as `{mapName}` for templates 8 and 9. If no maps are returned, the optional Dependency Map service is not in use in this scope — fall back to the classic agentless portal CSV export path (SKILL Phase 4 step 8e) or continue with VM Insights-only evidence if that is already available.

---

### 8. Export Dependencies via Direct API (Bulk CSV)

**Purpose:** Bulk-export observed dependencies from a Dependency Map to CSV programmatically — the direct-API equivalent of the portal **Manage Dependencies → Export dependencies** action. This is an **optional Azure Migrate enrichment** path when a `Microsoft.DependencyMap/maps` resource exists.

**Why direct API over the bundled PowerShell helper script:** the direct `az rest` call keeps every request/response auditable, requires only the Azure CLI (already a prerequisite — no extra PowerShell 5.1+ dependency), avoids opaque external-script logic and uncontrolled file-download side effects, and lets us version the exact call inline here. Convenience features of the helper script (auth, async polling, CSV download) are reproduced by this template.

**Operation:** `Maps_ExportDependencies` — `POST .../providers/Microsoft.DependencyMap/maps/{mapName}/exportDependencies`. This is a long-running (async) operation: it returns `202` with a `Location` header (poll until terminal) or `200` with the result inline. The terminal result carries `properties.exportedDataSasUri` — a short-lived SAS URL to the exported CSV.

#### Template
```powershell
$body = @{
    focusedMachineId = "{focusedMachineId}"
    applianceNameList = @({applianceNames})
    filters = @{
        dateTime = @{
            startDateTimeUtc = "{startDateTimeUtc}"
            endDateTimeUtc   = "{endDateTimeUtc}"
        }
        processNameFilter = @{
            operator     = "contains"
            processNames = @({processNames})
        }
    }
} | ConvertTo-Json -Depth 6 -Compress
$body | Set-Content "$env:TEMP\depmap-export.json" -NoNewline
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
$resp = az rest --method POST `
    --url "https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.DependencyMap/maps/{mapName}/exportDependencies?api-version={dependencyMapApiVersion}" `
    --body "@$env:TEMP\depmap-export.json" `
    --headers "Content-Type=application/json" `
    -o json
```

**Async polling:** if the response is empty and the call returned `202`, capture the `Location` response header and poll it with `az rest --method GET --url "{locationUrl}" -o json` every 5–10 seconds until `status` is `Succeeded` (or `Failed`/`Canceled`). When succeeded, read `properties.exportedDataSasUri`.

**Download the CSV:**
```powershell
Invoke-WebRequest -UseBasicParsing -Uri "{exportedDataSasUri}" -OutFile "$env:TEMP\dependency-export.csv"
```

**Placeholders:**
- `{focusedMachineId}` — machine node ID within the Dependency Map (resolve from the map's discovered machines; correlate to the Arc SQL machine by name). Required by the API.
- `{applianceNames}` — comma-separated, quoted appliance names, e.g. `"appliance-01","appliance-02"`. Maps to portal appliance selection.
- `{startDateTimeUtc}` / `{endDateTimeUtc}` — ISO 8601 UTC bounds of the collection window. Default to a **28-day** window ending now (e.g. `startDateTimeUtc = (Get-Date).AddDays(-28).ToUniversalTime().ToString("o")`). **Do not exceed 30 days** — the API rejects start dates older than 30 days with `Start date ... cannot be older than 30 days`.
- `{processNames}` — comma-separated, quoted process-name filters, e.g. `"sqlservr"`. Omit the `processNameFilter` block entirely for all resolvable processes.
- `{mapName}` — from Template 7.
- `{dependencyMapApiVersion}` — see Template 7.

**Expected output / result shape:**
```json
{
  "status": "Succeeded",
  "properties": {
    "exportedDataSasUri": "https://...blob.core.windows.net/export-data/file.csv?sv=...",
    "statusCode": "PartialMatch",
    "additionalInfo": { "availableDaysCount": 7 }
  }
}
```
The downloaded CSV uses the same column structure as the portal export (`Source server name`, `Destination server name`, `Destination port`, etc.) — parse it with the existing dependency-CSV correlation rules. `statusCode: PartialMatch` with `availableDaysCount` indicates fewer days of data were available than requested — disclose this as a data-freshness note.

---

### 9. Get Dependency View for a Focused Machine (Single Machine)

**Purpose:** Retrieve the dependency view for a single machine — the direct-API equivalent of the portal focused-machine dependency visualization. Use for targeted, per-SQL-instance optional Azure Migrate dependency inspection rather than bulk export.

**Operation:** `Maps_GetDependencyViewForFocusedMachine` — `POST .../providers/Microsoft.DependencyMap/maps/{mapName}/getDependencyViewForFocusedMachine`. Async: returns `202` with a `Location` header; poll until terminal, then read the result.

#### Template
```powershell
$body = @{
    focusedMachineId = "{focusedMachineId}"
    filters = @{
        dateTime = @{
            startDateTimeUtc = "{startDateTimeUtc}"
            endDateTimeUtc   = "{endDateTimeUtc}"
        }
        processNameFilter = @{
            operator     = "contains"
            processNames = @({processNames})
        }
    }
} | ConvertTo-Json -Depth 6 -Compress
$body | Set-Content "$env:TEMP\depmap-view.json" -NoNewline
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az rest --method POST `
    --url "https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.DependencyMap/maps/{mapName}/getDependencyViewForFocusedMachine?api-version={dependencyMapApiVersion}" `
    --body "@$env:TEMP\depmap-view.json" `
    --headers "Content-Type=application/json" `
    -o json
```

**Placeholders:** same as Template 8 (no `applianceNameList`). Poll the `Location` header as described in Template 8.

---

### 10. List / Get SQL Assessments from an Assessment Project

**Purpose:** Discover SQL-specific assessments (`Microsoft.Migrate/assessmentProjects/.../sqlAssessments`) and verify their status before retrieving per-instance data. Use this in Phase 4 step 7a **before** attempting the group-scoped VM assessment fallback path.

**Why a separate template:** SQL assessment data lives under a distinct sub-resource type (`sqlAssessments`) with its own api-version (`2024-03-03-preview`). Earlier api-versions (`2023-03-15`, `2023-04-01-preview`) return `InvalidHttpRequestPath` or `Internal Server Error` for this resource path. The SQL assessment contains per-instance utilisation, MI/VM/DB readiness, SKU recommendations, and cost — data that is not available from the group-scoped VM assessment path.

**Step 1 — Attempt to list SQL assessments at project scope:**
```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az rest --method GET --url "https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Migrate/assessmentProjects/{assessmentProjectName}/sqlAssessments?api-version=2024-03-03-preview" -o json
```

> **Known limitation:** The list operation may return `Internal Server Error` on some assessment projects (a known limitation of the `2024-03-03-preview` API surface — the list endpoint is not fully implemented for all project configurations). This is not a transient error; retry will not help. If it fails, proceed to Step 2 (direct GET by known name).

**Step 2 — Direct GET on known assessment name (fallback when list fails):**
```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az rest --method GET --url "https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Migrate/assessmentProjects/{assessmentProjectName}/sqlAssessments/{sqlAssessmentName}?api-version=2024-03-03-preview" -o json
```

Try the following names in order until one succeeds: `allapplications-sql`, `{assessmentProjectName}-sql`, `default`.

**Placeholders:**
- `{subscriptionId}` — Subscription ID (GUID) containing the Azure Migrate project
- `{resourceGroup}` — Resource group of the Azure Migrate / assessment project
- `{assessmentProjectName}` — Name of the `Microsoft.Migrate/assessmentProjects` resource (note: this is distinct from the `migrateProjects` container — the assessment project name typically matches the migrate project name, e.g. `migrate2684project`)
- `{sqlAssessmentName}` — SQL assessment name (e.g. `allapplications-sql`); try well-known names when list is unavailable

**Expected output (list):** JSON `value[]` of SQL assessment resources. Filter for `properties.status = Finished` — only Finished assessments contain complete readiness and cost data.

**Expected output (single GET):**
```json
{
  "name": "allapplications-sql",
  "properties": {
    "status": "Finished",
    "lastUpdatedTime": "2026-07-10T08:00:34Z",
    "numberOfMachines": 10,
    "numberOfInstances": 10
  }
}
```

Use `properties.status` and `properties.lastUpdatedTime` to assess freshness before extracting instance data.

---

### 11. Get Assessed SQL Instances from a SQL Assessment

**Purpose:** Retrieve per-instance SQL assessment data — utilisation baselines, MI/VM/DB readiness, SKU recommendations, cost, and Arc-machine linkage — from a Finished SQL assessment. This is the data source that replaces ARM-synced `skuRecommendationResults` when a Finished SQL assessment exists.

**Operation:** `GET .../sqlAssessments/{name}/assessedSqlInstances?api-version=2024-03-03-preview`

```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az rest --method GET --url "https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Migrate/assessmentProjects/{assessmentProjectName}/sqlAssessments/{sqlAssessmentName}/assessedSqlInstances?api-version=2024-03-03-preview" -o json
```

**Pagination:** check the response for a `nextLink` field; if present, follow it to retrieve subsequent pages until `nextLink` is absent.

**Placeholders:**
- `{subscriptionId}`, `{resourceGroup}`, `{assessmentProjectName}` — same as Template 10
- `{sqlAssessmentName}` — name of the Finished SQL assessment resolved via Template 10

**Key response fields to extract per instance (`value[]` array):**

| Field path | Description | Use in report |
|---|---|---|
| `properties.extendedDetails.percentageCoresUtilization` | Average CPU utilisation (%) over collection period | Utilisation baseline; raise confidence Low→Medium/High |
| `properties.extendedDetails.memoryInUseInMB` | Average memory in use (MB) | Convert to GB for reporting |
| `properties.extendedDetails.numberOfCoresAllocated` | vCores discovered | Validate against ARM inventory |
| `properties.extendedDetails.sqlEdition` | Discovered SQL edition | Validate against ARM `edition` field |
| `properties.extendedDetails.sqlVersion` | Discovered SQL version | Validate against ARM `version` field |
| `properties.extendedDetails.productSupportStatus` | EoS/ESU dates from assessment | Use for end-of-support analysis |
| `properties.extendedDetails.databaseSummary` | Per-database summary from assessment | Supplement ARM database inventory |
| `properties.recommendations[].targetType` | Target type: `AzureSqlManagedInstance` / `AzureSqlVirtualMachine` / `AzureSqlDatabase` | Maps to MI / SQL VM / SQL DB columns |
| `properties.recommendations[].migrationSuitability.readiness` | Readiness: `Suitable` / `ConditionallySuitable` / `ReadyWithConditions` / `NotSuitable` | See readiness mapping table below |
| `properties.recommendations[].confidenceScore` | Confidence score (0–100) | Disclose alongside readiness |
| `properties.recommendations[].skus` | Recommended SKU details (tier, hardware, vCores) | Azure target SKU recommendation |
| `properties.recommendations[].totalCost.costDetail` | Cost breakdown per billing model | Report cost; check `savingsOptions` for RI/AHB framing |
| `properties.linkages[].kind` | Linkage type: `Machine` = Arc host | Use for machine correlation |
| `properties.linkages[].linkageType` | `Parent` = the Arc host this instance runs on | Filter for `kind=Machine, linkageType=Parent` |
| `properties.linkages[].workloadName` | Arc machine name | **Primary correlation key** to Arc `microsoft.hybridcompute/machines` resources |

**Readiness value mapping:**

| API value | Report language | Indicator |
|---|---|---|
| `Suitable` | Ready | GREEN |
| `ConditionallySuitable` | Conditionally ready | AMBER |
| `ReadyWithConditions` | Ready with conditions | AMBER |
| `NotSuitable` | Not ready | RED |
| `Unknown` / absent | Unknown | GREY |

> **Important:** `ConditionallySuitable` must NOT be reported as "Not Ready". It indicates the instance can be migrated with acknowledged conditions — a meaningfully different finding from `NotSuitable`.

**Expected output shape:**
```json
{
  "value": [
    {
      "name": "instance-guid",
      "properties": {
        "extendedDetails": {
          "sqlEdition": "Enterprise",
          "sqlVersion": "SQL Server 2019",
          "numberOfCoresAllocated": 8,
          "percentageCoresUtilization": 42.5,
          "memoryInUseInMB": 12288
        },
        "recommendations": [
          {
            "targetType": "AzureSqlManagedInstance",
            "migrationSuitability": { "readiness": "ConditionallySuitable" },
            "confidenceScore": 87,
            "skus": [ { "tier": "BusinessCritical", "hardwareGeneration": "Gen5", "targetVCores": 8 } ],
            "totalCost": { "costDetail": { "computeCost": 1200.00, "savingsOptions": "ThreeYearReserved" } }
          }
        ],
        "linkages": [
          { "kind": "Machine", "linkageType": "Parent", "workloadName": "ArcBox-SQL" }
        ]
      }
    }
  ]
}
```

---

## Azure Update Manager — security exposure query templates (assessment-only)

These templates back the **core security-exposure path** (see `security-exposure.md`). They
read Azure Update Manager assessment data from Azure Resource Graph. They are **read-only /
assessment-only** — they never install patches, create maintenance configurations, or query
installation records for the purpose of triggering installs. Do **not** adapt these into
`patchinstallationresources` writes or `maintenanceresources` installation calls.

> **Prerequisite:** the Arc-enabled machines must have Azure Update Manager **periodic
> assessment** enabled (assessment-only; no patch installation). Assessment data is retained
> in Resource Graph for ~7 days. Machines with no assessment record are reported as an
> operational visibility gap, not silently dropped.

### 12. Update Manager — per-machine assessment summary

**Purpose:** Retrieve one assessment summary row per machine (available patch counts by
classification, OS type, last assessment time). Populates `PatchAssessmentSummary`.

```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az graph query -q "patchassessmentresources | where type !has 'softwarepatches' | where subscriptionId in ('{sub1}','{sub2}') | extend prop = parse_json(properties) | extend byClass = prop.availablePatchCountByClassification | project machineResourceId = tostring(split(id, '/patchAssessmentResults/')[0]), machineName = tostring(split(id, '/', 8)[0]), osType = tostring(prop.osType), assessmentState = tostring(coalesce(prop.status, prop.configurationStatus.assessmentModeConfiguration.status, prop.assessmentState)), assessmentTime = tostring(prop.lastModifiedDateTime), securityCount = toint(byClass.security), criticalCount = toint(byClass.critical), otherCount = toint(byClass.other), subscriptionId, resourceGroup, tenantId" --subscriptions {subscriptionIds} --first 1000 -o json
```

- Works for **both Windows and Linux** Arc machines (the `!has 'softwarepatches'` filter
  keeps only summary records).
- The record `name` is always `latest` (the id ends `/patchAssessmentResults/latest`), so the
  machine name is taken from the id path (`split(id, '/', 8)[0]`), not from `name`.
- If the table returns zero rows, treat as "no assessment data for scope" (a data gap / AUM
  not enabled), not an error.
- Parse each row with `ConvertFrom-AumSummary` (see `scripts/ArcSqlSecurityExposure.psm1`).

### 13. Update Manager — individual missing software patches (Windows + Linux)

**Purpose:** Retrieve one row per missing update. Populates `MissingPatch`. Do **not** assume
every row has a `kbId` (Linux packages and some Windows updates have none).

```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az graph query -q "patchassessmentresources | where type has 'softwarepatches' | where subscriptionId in ('{sub1}','{sub2}') | extend prop = parse_json(properties) | extend machineResourceId = tostring(split(id, '/patchAssessmentResults/')[0]) | join kind=leftouter (patchassessmentresources | where type !has 'softwarepatches' | extend sprop = parse_json(properties) | project machineResourceId = tostring(split(id, '/patchAssessmentResults/')[0]), osType = tostring(sprop.osType)) on machineResourceId | project machineResourceId, machineName = tostring(split(id, '/', 8)[0]), patchId = name, patchName = tostring(prop.patchName), kbId = tostring(prop.kbId), classification = tostring(prop.classifications), osType, packageVersion = tostring(prop.version), rebootBehavior = tostring(prop.rebootBehavior), assessmentTime = tostring(prop.lastModifiedDateTime), subscriptionId, resourceGroup, tenantId, properties" --subscriptions {subscriptionIds} --first 1000 -o json
```

- **OS type:** softwarepatches rows do **not** carry `osType` in their properties (verified
  live: 0/249 rows). It is resolved by the `leftouter` join to the summary record above. When
  parsing rows without the join, pass `ConvertFrom-AumSoftwarePatch -OsTypeLookup` (built from
  the summary pass); the parser falls back to inference (KB present → Windows, package version
  present → Linux, else `Unknown`).
- **KB extraction:** apply `Get-KbIdFromText` to `patchName`, `kbId`, and `patchId`; a title
  may contain multiple KBs. Records with no KB are retained and marked `Unmapped`.
- **Pagination:** for large estates check the response for a `skip_token` and re-issue with
  `--skip-token {skipToken}` until absent (same pattern as Template 5).
- Parse each row with `ConvertFrom-AumSoftwarePatch`.

### 14. Update Manager — missing security/critical patches only (headline scope)

**Purpose:** Narrow Template 13 to the security-relevant classifications for headline patch
debt metrics and top-machines-by-patch-debt.

```powershell
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az graph query -q "patchassessmentresources | where type has 'softwarepatches' | where subscriptionId in ('{sub1}','{sub2}') | extend prop = parse_json(properties) | extend classification = tostring(prop.classifications) | where classification in~ ('Security','Critical','Critical and Security Updates') | summarize missingSecurity = count() by machineResourceId = tostring(split(id, '/patchAssessmentResults/')[0]) | order by missingSecurity desc" --subscriptions {subscriptionIds} --first 1000 -o json
```

> **Guardrail:** none of Templates 12–14 may be modified to call `installPatches`, create a
> `Microsoft.Maintenance/maintenanceConfigurations` resource, or PUT/POST against
> `patchinstallationresources`. Route any such operation through `Assert-AssessmentOnly`,
> which fails fast with: `Patch installation is disabled for this agent. Assessment-only mode is enforced.`

---

## Usage Guidelines

### When to use each template:

1. **Before first execution on a machine:** Use Template 1 (List) to check for existing run command slots
2. **For all script submissions:** Use Template 2 (Create/Update via REST) with encoding
3. **After submission:** Use Template 3 (Poll) to check status and retrieve results
4. **Only when quota exhausted:** Use Template 4 (Delete) for cleanup, but prefer updating slots
5. **For all estate inventory queries:** Use Template 5 (Consolidated Estate ARG Query) — one call for all resource types
6. **Before the full estate query:** Use Template 6 (Scope Validation Query) as a lightweight pre-check in Phase 2
7. **For dependency analysis, check VM Insights first:** use the Azure Monitor VM Insights prerequisite / topology queries above to confirm `VMConnection` data exists in the selected workspace
8. **Only for optional Azure Migrate enrichment:** use Template 7 (List Azure Migrate Dependency Map Resources) to resolve `{mapName}` before any direct Dependency Map API call
9. **For bulk optional Azure Migrate dependency data:** use Template 8 (Export Dependencies via Direct API) when a `Microsoft.DependencyMap/maps` resource exists; download and parse the resulting CSV
10. **For single-machine optional Azure Migrate dependency inspection:** use Template 9 (Get Dependency View for a Focused Machine)
11. **To discover SQL-specific assessments (primary utilisation path):** Use Template 10 (List/Get SQL Assessments) to find Finished `sqlAssessments` resources — try list first, fall back to direct GET on known names; always use `api-version=2024-03-03-preview`
12. **To retrieve per-instance SQL data (primary utilisation path):** Use Template 11 (Get Assessed SQL Instances) to extract per-instance utilisation, readiness, SKU, cost, and Arc-machine linkage from a Finished SQL assessment; this supersedes ARM-synced `skuRecommendationResults`
13. **For per-machine patch assessment coverage (core security path):** Use Template 12 (Update Manager assessment summary) to build `PatchAssessmentSummary` rows for every Arc machine — no Azure Migrate required
14. **For missing-patch detail and KB extraction (core security path):** Use Template 13 (individual missing software patches) to build `MissingPatch` rows across Windows and Linux; extract KBs with `Get-KbIdFromText`
15. **For headline patch-debt ranking:** Use Template 14 (missing security/critical patches only) to rank top machines by security patch debt for executive metrics

### Placeholder naming conventions:

All templates use consistent placeholder naming:
- `{machineName}` — Arc-enabled machine name
- `{resourceGroup}` — Resource group name
- `{subscriptionId}` — Subscription ID (GUID)
- `{location}` — Azure region (e.g., `eastus`)
- `{slotName}` — Run command slot name (use pattern: `estate-audit-{machineName}-{slotNumber}`)
- `{scriptContent}` — Full PowerShell script to execute
- `{workspaceId}` — Log Analytics workspace ID (GUID or full resource ID accepted by `az monitor log-analytics query`) containing VM Insights dependency data
- `{sqlHostNames}` — comma-separated, quoted Arc SQL machine names for VM Insights filtering, e.g. `"SQL01","SQL02"`
- `{mapName}` — Azure Migrate Dependency Map resource name (`Microsoft.DependencyMap/maps`), resolved via Template 7
- `{dependencyMapApiVersion}` — Dependency Map API version (default `2025-05-01-preview`; fall back to `2025-07-01-preview` then `2025-01-31-preview`)
- `{focusedMachineId}` — machine node ID within the Dependency Map, correlated to the Arc SQL machine by name
- `{assessmentProjectName}` — Name of the `Microsoft.Migrate/assessmentProjects` resource (distinct from the `migrateProjects` container)
- `{sqlAssessmentName}` — SQL assessment name within the assessment project, resolved via Template 10 (e.g. `allapplications-sql`)

### Reusable slot naming pattern:

Use this pattern for all run command slots:
- DMV audit slot: `estate-audit-{machineName}-01`
- Runtime checks slot: `estate-audit-{machineName}-02`

This ensures:
- Slots are clearly identifiable
- Quota is never exceeded (max 2 slots per machine)
- Subsequent sessions can reuse the same slots

---

## Example: Complete Encode-and-Submit Workflow

Here's a complete example showing how to submit a DMV audit script to a machine named `ArcBox-SQL-01`:

```powershell
# Define the PowerShell script to execute remotely
$script = @'
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
'@

# Encode the script to Base64 Unicode
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))
$scriptPayload = "powershell -EncodedCommand $encoded"

# Build the REST API body
$body = @{
    location = "eastus"
    properties = @{
        source = @{ script = $scriptPayload }
    }
} | ConvertTo-Json -Depth 5 -Compress

# Write body to temp file
$body | Set-Content "$env:TEMP\rc-estate-audit-ArcBox-SQL-01-01.json" -NoNewline

# Submit via REST API
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'
az rest --method PUT --url "https://management.azure.com/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-arc-sql/providers/Microsoft.HybridCompute/machines/ArcBox-SQL-01/runCommands/estate-audit-ArcBox-SQL-01-01?api-version=2024-07-10" --body "@$env:TEMP\rc-estate-audit-ArcBox-SQL-01-01.json" -o json
```

**What this does:**
1. Defines the full DMV audit script (multi-line, with SQL queries and error handling)
2. Encodes it to Base64 to avoid ALL argument parsing issues
3. Builds a proper REST API body with location and encoded script
4. Writes the body to a temp file to avoid command-line length limits
5. Submits the run command via REST API

**Expected workflow:**
1. Submit the run command using the template above
2. Poll status with Template 3 every 15-30 seconds
3. When `execState` is `Succeeded`, retrieve results from `stdout`
4. Parse the JSON results and continue analysis

---

### Parallel submission across multiple machines

When the estate has multiple Arc machines requiring audit, submit run commands in parallel to overlap execution time:

1. **Submit phase** — issue one `az rest --method PUT` call per machine (do NOT add `--no-wait`; `az rest` does not support that flag). Each PUT returns immediately with `provisioningState=Creating`, indicating the run command resource has been created and execution has started asynchronously on the Arc host.
2. **Poll phase** — after all PUTs have been issued, poll each machine with Template 3 until `execState` reaches `Succeeded` or `Failed`.
3. **Constraint** — never submit more than one concurrent run command to the *same* machine (risk of HCRP500 conflict). Parallelism is across *different* machines only.

This pattern achieves elapsed time ≈ single-machine execution time regardless of how many machines are audited simultaneously.

---

## Summary

**Key takeaways:**
- Always use Template 2 (REST API with encoding) for run command submissions
- Never add `--no-wait` to `az rest` commands — the flag is not supported; use plain PUT (returns `provisioningState=Creating`) then poll separately
- Never construct run command submission commands from scratch
- Never pass complex SQL queries via CLI arguments
- Always write JSON bodies to temp files
- Always use reusable slot names to avoid quota issues
- Keep encode-and-submit workflow in a single PowerShell call
- Always set `$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'` before any `az` call whose output is parsed as JSON
- Never use `2>&1` in a pipeline that feeds `ConvertFrom-Json`

**Expected outcomes:**
- Zero Azure CLI argument parsing errors
- Zero command-line length errors
- Zero variable loss across tool calls
- Zero quota exhaustion errors
- Reliable, first-attempt execution success
- Reduced latency: ~30-60 seconds per avoided failed attempt

**When in doubt:** Copy the exact template, replace placeholders, and execute. Do not attempt to modify or "improve" the templates — they are pre-validated patterns designed to avoid known failure modes.
