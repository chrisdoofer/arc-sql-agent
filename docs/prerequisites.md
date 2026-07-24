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

> **Note:** The Enterprise downgrade audit executes read-only DMV/metadata queries via Arc Run Command, including `sys.dm_db_persisted_sku_features` and runtime validation queries (Always On AG, Resource Governor, partitioning, and `ONLINE=ON` SQL Agent job checks). These queries have no side effects on the target SQL Server.

### Additional permissions for security exposure (Azure Update Manager, assessment-only)

| Scope | Role / Permission | Purpose |
|-------|-------------------|---------|
| Subscription(s) | `Microsoft.ResourceGraph/resources/read` | Read Azure Update Manager assessment data (`patchassessmentresources`) via Resource Graph |
| Resource Group(s) with Arc machines | `Microsoft.HybridCompute/machines/patchAssessmentResults/read` | Read per-machine patch assessment results and missing software patches |
| Resource Group(s) with Arc machines | `Microsoft.HybridCompute/machines/assessPatches/action` _(optional)_ | Trigger an on-demand **assessment** only (never installation) if fresh assessment data is required |

> **Assessment-only:** the security-exposure feature reads missing-patch assessment data and
> never installs patches, creates maintenance configurations, or schedules update deployments.
> No `installPatches` / maintenance-configuration write permissions are required or used. To
> populate assessment data, enable Azure Update Manager **periodic assessment** on the Arc
> machines (assessment-only); assessment records are retained in Resource Graph for ~7 days.
> External CVE lookups (MSRC / NVD) are outbound HTTPS calls that use no Azure RBAC.

### Recommended built-in roles

| Scenario | Recommended Role | Scope |
|----------|-----------------|-------|
| Inventory only (no audit) | **Reader** | Subscription |
| Full analysis with audit | **Reader** + **Azure Connected Machine Resource Administrator** | Subscription + Resource Group |

---

## CVE enrichment & secrets (optional)

CVE enrichment adds CVSS scores, severity, vectors, CWEs, and references to the security-exposure
section. **It is optional and needs no setup to get started:**

- **No API key is required.** The primary KB→CVE mapping source, the **Microsoft Security Update
  Guide (MSRC)**, is fully public and needs no key.
- **NVD works without a key too**, but the public NVD CVE API is rate-limited to **5 requests /
  30 s**. An optional **free** NVD API key raises this to **50 requests / 30 s**, which speeds up
  enrichment on large estates (without a key the agent caps/queues NVD lookups to stay polite).

So the friction-free default is: do nothing. Add a key only if you want faster, uncapped NVD
enrichment across a big estate.

### Obtain a free NVD API key

Request one from NIST: <https://nvd.nist.gov/developers/request-an-api-key>. Enter your email and
organisation, accept the terms, then click the one-time activation link in the email to reveal the
key (a UUID). Save it immediately — it is shown once.

### How to store the key

The provider reads the key from the `-ApiKey` parameter or the `NVD_API_KEY` environment variable
and **never** writes it to the cache, logs, or output. Choose the store that fits how you run the
agent:

| Where you run the agent | Recommended store | Why |
|---|---|---|
| Local interactive (most common) | **PowerShell SecretManagement + SecretStore vault** | Encrypted at rest; no plaintext on disk; retrieved at runtime |
| Quick / one-off local run | `NVD_API_KEY` environment variable | Simplest; ephemeral to the shell session |
| Automation (GitHub Actions / Copilot coding agent) | **GitHub Actions secret / Copilot environment secret** → injected as `NVD_API_KEY` | The right place for a "GitHub secret"; only accessible when running *inside* GitHub, not for local CLI runs |
| ❌ Never | Committed config, hardcoded value, tracked `.env` | The key is low-sensitivity, but secrets must never be committed |

**Environment variable (simplest):**

```powershell
$env:NVD_API_KEY = '<your-key>'   # current shell only
```

**PowerShell SecretManagement vault (persistent, encrypted — best for local operators):**

```powershell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
Register-SecretVault -Name ArcSql -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
Set-Secret -Name NVD_API_KEY -Secret '<your-key>'          # store once, encrypted

# At runtime, load it into the environment just before an analysis:
$env:NVD_API_KEY = Get-Secret -Name NVD_API_KEY -AsPlainText
```

**GitHub Actions / Copilot coding agent (automation only):** add a repository or environment
secret named `NVD_API_KEY` (Settings → Secrets and variables), then surface it as an environment
variable in the job:

```yaml
    env:
      NVD_API_KEY: ${{ secrets.NVD_API_KEY }}
```

> A GitHub secret is only reachable when the agent runs **inside** GitHub Actions or the Copilot
> coding agent. For a local Copilot CLI run on a workstation, use the SecretManagement vault or an
> environment variable instead.

### Outbound endpoints for CVE enrichment

The external CVE lookups are outbound HTTPS only (no Azure RBAC). Allow-list these if egress is
restricted:

| Endpoint | Purpose |
|---|---|
| `https://api.msrc.microsoft.com` | MSRC Security Update Guide — KB→CVE mapping (no key) |
| `https://services.nvd.nist.gov` | NVD CVE API 2.0 — CVE metadata enrichment (optional key) |

Responses are cached locally (`cveEnrichment.cachePath`) and can be replayed in an offline mode, so
repeat runs and air-gapped analysis do not re-hit the external APIs.

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
