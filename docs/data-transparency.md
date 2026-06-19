# Data Transparency

This document provides full transparency on the data collected, accessed, and reported by the Arc SQL Estate Analyser. It is intended to reassure consumers (customers, security teams, compliance officers) about exactly what the solution touches.

---

## Principles

1. **Read-only by default** — All inventory data is collected via read-only Azure Resource Graph queries. No modifications are made to any Azure resources, SQL Server configurations, or databases.
2. **Explicit user approval for write operations** — Any operation that modifies Azure resources (creating, updating, or deleting Arc Run Command resources, or installing extensions) requires explicit user approval via `ask_user` before it is executed. If the user declines, the operation is skipped and any downstream impact is noted in the output.
3. **Minimal remote execution** — The only write-like operations are creating temporary Arc Run Command resources to execute read-only DMV queries, and deleting those resources after use. Both actions require prior user approval.
4. **No data exfiltration** — All data remains within the Azure control plane and the operator's local session. No data is sent to third-party services.
5. **No direct SQL connectivity** — The operator never connects directly to SQL Server. All remote queries are mediated through the Arc agent's secure channel.

---

## Data Collected

### From Azure Resource Graph (read-only queries)

| Resource Type | Fields Collected | Purpose |
|---------------|-----------------|---------|
| `microsoft.azurearcdata/sqlserverinstances` | name, resourceGroup, subscriptionId, location, version, edition, vCore, cores, licenseType, status, currentVersion, patchLevel, instanceName, serviceType, isHadrEnabled, alwaysOnRole, backupPolicy, azureDefenderStatus, monitoring, migration.assessment | Instance inventory, version/edition analysis, security posture, migration readiness |
| `microsoft.azurearcdata/sqlserverinstances/databases` | name, sizeMB, recoveryMode, state, isReadOnly, isEncrypted, compatibilityLevel, collationName, backupInformation, databaseOptions, databaseCreationDate | Database inventory, backup compliance, encryption status |
| `microsoft.hybridcompute/machines` | name, location, osName, osVersion, osSku, status, detectedProperties (cores, RAM, hypervisor, processor) | Host platform analysis, sizing assessment |

> **Migration assessment note:** When `assessment.enabled = true` but `assessmentUploadTime = null`, assessment output is treated as **sync-pending** (not "no assessment"). This indicates the extension has likely collected results in the telemetry plane, but ARM summary fields (e.g., `skuRecommendationResults`) are not yet synced. Users should check the Azure portal assessment blade or trigger **Run Assessment** to refresh sync.

### From Arc Run Command (remote execution)

| Query Executed | Target | Fields Returned | Purpose |
|----------------|--------|-----------------|---------|
| `SELECT feature_name FROM sys.dm_db_persisted_sku_features` | Each user database (database_id > 4) on Enterprise instances | feature_name (if any) | Detect persisted Enterprise-only features |
| `SELECT ag.name AS ag_name, ar.replica_server_name, ar.availability_mode_desc FROM sys.availability_groups ag JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id` | Enterprise instances | ag_name, replica_server_name, availability_mode_desc | Detect Always On AG runtime usage |
| `SELECT is_enabled FROM sys.resource_governor_configuration` | Enterprise instances | is_enabled | Detect Resource Governor runtime usage |
| `SELECT OBJECT_SCHEMA_NAME(p.object_id) AS schema_name, OBJECT_NAME(p.object_id) AS table_name, COUNT(DISTINCT p.partition_number) AS partition_count FROM sys.partitions p WHERE p.partition_number > 1 AND p.index_id IN (0,1) GROUP BY p.object_id` | Enterprise instances | schema_name, table_name, partition_count | Detect partitioned table usage |
| `SELECT j.name AS job_name, js.command FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobsteps js ON j.job_id = js.job_id WHERE js.command LIKE '%ONLINE%=%ON%'` | Enterprise instances | job_name, command | Detect maintenance jobs relying on online index operations |

> Arc Run Command executes read-only metadata queries only. These checks do not modify data, schema, or SQL Server configuration.

### From Azure Subscription API (read-only)

| Data | Purpose |
|------|---------|
| Subscription ID, display name, state, tenant ID | Scope resolution and validation |

---

## Data NOT Collected

The following data is explicitly **not** accessed or collected:

| Category | Detail |
|----------|--------|
| ❌ Table data | No user/application data is read from any database |
| ❌ Credentials | No passwords, connection strings, or keys are accessed |
| ❌ Query plans | No execution plans or query text is captured |
| ❌ User information | No database users, logins, or AD accounts are enumerated |
| ❌ Network traffic | No packet capture or network analysis is performed |
| ❌ Application code | No stored procedures, functions, or application objects are read |
| ❌ Backup content | No backup files are accessed — only backup *policy metadata* from Arc |
| ❌ Performance data | No wait stats, DMV perf counters, or trace data is collected |

---

## Where Data Resides

| Location | Content | Persistence |
|----------|---------|-------------|
| Operator's local session | Full analysis report output | Session duration only |
| Azure Resource Manager | Arc Run Command resources (temporary) | Deleted after retrieval |
| Azure Resource Graph | Existing resource metadata (read-only) | Unchanged by this solution |

---

## Arc Run Command Lifecycle

```
0. SCRIPT REVIEW    → Full script content presented to user in a markdown code block; purpose and target machine shown
1. USER APPROVAL    → ask_user confirmation required; choices: Approve and execute / Skip this check / Modify script first
2. CREATE run command    → Temporary ARM resource created (only if Approved)
3. EXECUTE on host      → PowerShell script runs locally on Arc machine
4. READ results         → Output retrieved via ARM API
5. DELETE run command    → Temporary resource cleaned up (requires separate user approval)
```

The Run Command resource exists only for the duration of execution and result retrieval. The executed script is a single `Invoke-Sqlcmd` call with no file system access, no network calls, and no side effects.

The full script content is always shown to the user before submission — no script is ever submitted silently. Batch approval is offered when the same script template runs across multiple machines.

If the user declines any approval step, that operation is skipped, the gap is noted in the output, and the analysis continues with the data available.

---

## Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Scope isolation | Tenant and subscription scope is validated before any data collection. Cross-tenant results are rejected. |
| Script transparency | Every script executed via Arc Run Command is presented to the user in full (as a markdown code block) before submission, along with target machine, instance name, and purpose. No script is ever submitted silently. |
| Explicit write approval | All ARM write operations (extension install, run command create/update/delete) require explicit `ask_user` approval before execution. Declined operations are skipped gracefully. |
| Privilege escalation | Only standard read permissions are used. Run Command requires explicit RBAC grant (`Microsoft.HybridCompute/machines/runcommands/write`). |
| SQL Server impact | The DMV query is metadata-only, non-blocking, and has zero performance impact. |
| Data in transit | All communication uses HTTPS 443 via Azure ARM APIs and the Arc agent secure channel. |
| Operator access | The operator sees only the structured report output. Raw data is not persisted beyond the session. |

---

## Audit Trail

All operations are recorded in standard Azure activity logs:

- Azure Resource Graph queries: logged under the operator's identity
- Arc Run Command create/delete: logged as ARM operations with the operator's principal ID
- Subscription list: logged as a standard ARM read operation

No additional logging infrastructure is required. Existing Azure Monitor activity logs provide full traceability.

---

## Compliance Notes

- **GDPR:** No personal data is collected. Instance names, database names, and machine names are infrastructure metadata, not personal data.
- **SOC 2:** All access is authenticated, authorised via RBAC, and auditable via Azure activity logs.
- **No data leaves tenant boundary:** All queries execute within the Azure control plane of the target tenant. The report is generated locally on the operator's machine.
