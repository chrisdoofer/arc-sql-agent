# Prerequisites

## Required Software

| Tool | Purpose | Installation |
|------|---------|-------------|
| **GitHub Copilot CLI** | Agent runtime | [Install guide](https://docs.github.com/en/copilot/github-copilot-in-the-cli) |
| **Azure CLI** (`az`) | Fallback queries and Arc Run Command execution | [Install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| **Azure CLI extensions** | | |
| — `resource-graph` | Azure Resource Graph queries | `az extension add --name resource-graph` |
| — `connectedmachine` | Arc Run Command execution | `az extension add --name connectedmachine` |

---

## Azure Tenant Access

The operator running the analysis must be authenticated to the target Azure tenant:

```bash
az login --tenant <tenant-id-or-domain>
```

If the operator has access to multiple tenants, the correct tenant **must** be specified explicitly. The agent will resolve available subscriptions and confirm scope before proceeding.

---

## Required RBAC Permissions

### Minimum permissions for estate inventory (read-only)

| Scope | Role / Permission | Purpose |
|-------|-------------------|---------|
| Subscription(s) | **Reader** | Read Arc-enabled SQL instances, databases, and machines via Resource Graph |
| Subscription(s) | `Microsoft.ResourceGraph/resources/read` | Execute Resource Graph queries |
| Resource Group(s) with Arc resources | `Microsoft.HybridCompute/machines/read` | Read Arc machine properties (OS, cores, RAM) |
| Resource Group(s) with Arc resources | `Microsoft.AzureArcData/sqlServerInstances/read` | Read SQL instance inventory |
| Resource Group(s) with Arc resources | `Microsoft.AzureArcData/sqlServerInstances/databases/read` | Read database inventory |

### Additional permissions for Enterprise downgrade audit

| Scope | Role / Permission | Purpose |
|-------|-------------------|---------|
| Resource Group(s) with Arc machines | `Microsoft.HybridCompute/machines/runcommands/write` | Create Arc Run Commands |
| Resource Group(s) with Arc machines | `Microsoft.HybridCompute/machines/runcommands/read` | Read Run Command results |
| Resource Group(s) with Arc machines | `Microsoft.HybridCompute/machines/runcommands/delete` | Clean up Run Commands after execution |

> **Note:** The Enterprise downgrade audit executes `SELECT feature_name FROM sys.dm_db_persisted_sku_features` on each user database via Arc Run Command. This is a read-only DMV query with no side effects on the target SQL Server.

### Recommended built-in roles

| Scenario | Recommended Role | Scope |
|----------|-----------------|-------|
| Inventory only (no audit) | **Reader** | Subscription |
| Full analysis with audit | **Reader** + **Azure Connected Machine Resource Administrator** | Subscription + Resource Group |

---

## Arc-enabled SQL Server Requirements

The target estate must have:

| Requirement | Detail |
|-------------|--------|
| Arc agent installed and connected | Machine status = `Connected` |
| SQL Server extension deployed | `microsoft.azurearcdata` extension active |
| SQL Server instances discovered | Visible in Azure Resource Graph as `microsoft.azurearcdata/sqlserverinstances` |
| Network connectivity | Arc agent must be able to communicate with Azure (outbound HTTPS 443) |

### For Enterprise downgrade audit (optional but recommended)

| Requirement | Detail |
|-------------|--------|
| PowerShell `SqlServer` module | Must be installed on the Arc-enabled host |
| SQL Server connectivity | `Invoke-Sqlcmd` must be able to connect to `localhost` using Windows Authentication |
| Run Command handler | `microsoft.cplat.core.runcommandhandlerwindows` extension must be present |

---

## Fallback: Offline Analysis

If live Azure access is unavailable, the skill accepts uploaded estate data in:

- **Excel** (`.xlsx`) — one row per instance or database
- **JSON** — exported from Azure Resource Graph or custom tooling
- **CSV** — tabular export with headers

The agent will infer schema from the uploaded file and map fields to the analysis model. Missing columns are reported transparently under "Data gaps".

---

## Network and Firewall

No inbound connectivity is required to Arc-enabled machines. All communication is outbound from the Arc agent to Azure. The analysis operator connects to Azure APIs only — never directly to on-premises SQL Servers.

```
Operator workstation → Azure Resource Graph API (HTTPS 443)
                     → Azure ARM API (HTTPS 443)

Arc-enabled host → Azure (outbound HTTPS 443, established by Arc agent)
               ← Run Command delivered via Arc channel (no inbound firewall rules needed)
```
