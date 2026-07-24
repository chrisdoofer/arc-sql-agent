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

### Optional enrichment permissions

These permissions are only required if you enable optional enrichment paths (Azure Migrate assessment data, Dependency Map, or telemetry probing). All are in addition to the core permissions above.

| Scope | Role / Permission | Purpose | Required? |
|-------|-------------------|---------|-----------|
| Subscription | `Microsoft.Migrate/assessmentProjects/*/read` | Azure Migrate SQL assessment enrichment (readiness, utilisation, cost) | Optional — covered by **Reader** |
| RG with Dependency Map | `Microsoft.DependencyMap/maps/read` | Discover dependency maps | Optional — covered by **Reader** |
| RG with Dependency Map | `Microsoft.DependencyMap/maps/exportDependencies/action` | Run dependency export | Optional — **NOT covered by Reader** (POST action) |
| RG with Dependency Map | `Microsoft.DependencyMap/maps/getDependencyViewForFocusedMachine/action` | Run focused-machine dependency view | Optional — **NOT covered by Reader** (POST action) |
| RG with Arc SQL | `Microsoft.AzureArcData/sqlServerInstances/getTelemetry/action` | Migration-assessment telemetry probe | Optional — probe only; often returns 400 if telemetry not collected |

> **Dependency Map POST actions:** `exportDependencies` and `getDependencyViewForFocusedMachine` are
> ARM POST actions. A pure **Reader** role cannot execute them. If you need dependency-map export or
> focused-machine views, you must grant these two actions explicitly — they are not inherited from
> any built-in read-only role.

### Permissions the agent must NOT be granted

The agent operates in **assessment-only** mode. The following permissions must never be granted and are not required for any analysis function. Granting them would permit actions that are explicitly out of scope.

| Permission that must never be granted | Why |
|---------------------------------------|-----|
| `Microsoft.Maintenance/maintenanceConfigurations/write` | Would enable patch-install scheduling — blocked by design; assessment-only mode forbids it |
| `Microsoft.HybridCompute/machines/installPatches/action` | Patch installation — explicitly out of scope for an assessment-only agent |

> These exclusions reinforce the assessment-only patch guardrail at the RBAC layer. If you are
> deploying the custom role below, verify neither permission appears in the `actions` list.

### Recommended built-in roles

| Scenario | Recommended Role | Scope |
|----------|-----------------|-------|
| Inventory only (no audit) | **Reader** | Subscription |
| Full analysis with audit | **Reader** + **Azure Connected Machine Resource Administrator** | Subscription + Resource Group |

> **Note:** **Azure Connected Machine Resource Administrator** is a broad built-in role. For a
> tighter least-privilege fit, use the custom role definition below instead.

### Least-privilege custom role (recommended alternative)

The following custom role grants exactly the permissions the agent needs and nothing more. It is the recommended alternative to the broad built-in **Azure Connected Machine Resource Administrator**.

**Role definition (JSON):**

```json
{
  "Name": "Arc SQL Estate Analyser",
  "IsCustom": true,
  "Description": "Least-privilege role for the Arc SQL estate analysis agent. Assessment-only; no patch install or maintenance scheduling.",
  "Actions": [
    "Microsoft.HybridCompute/machines/read",
    "Microsoft.HybridCompute/machines/runcommands/read",
    "Microsoft.HybridCompute/machines/runcommands/write",
    "Microsoft.HybridCompute/machines/runcommands/delete",
    "Microsoft.HybridCompute/machines/patchAssessmentResults/read",
    "Microsoft.HybridCompute/machines/assessPatches/action",
    "Microsoft.AzureArcData/sqlServerInstances/read",
    "Microsoft.AzureArcData/sqlServerInstances/databases/read",
    "Microsoft.ResourceGraph/resources/read"
  ],
  "NotActions": [
    "Microsoft.Maintenance/maintenanceConfigurations/write",
    "Microsoft.HybridCompute/machines/installPatches/action"
  ],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": [
    "/subscriptions/<subscription-id>"
  ]
}
```

**Deploy with Azure CLI:**

```bash
# Save the JSON above as arc-sql-analyser-role.json, then:
az role definition create --role-definition arc-sql-analyser-role.json

# Assign to the operator identity scoped to the target resource group(s):
az role assignment create \
  --assignee <user-or-sp-object-id> \
  --role "Arc SQL Estate Analyser" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<rg-name>

# For inventory-only (Reader is sufficient), assign Reader at subscription level separately:
az role assignment create \
  --assignee <user-or-sp-object-id> \
  --role "Reader" \
  --scope /subscriptions/<subscription-id>
```

> The `NotActions` block explicitly excludes patch-installation and maintenance-configuration write
> permissions as a defence-in-depth measure, reinforcing the assessment-only guardrail.

### Setting up PIM eligibility (one-time, admin)

This section covers **step 2** of the three-step PIM workflow — creating a PIM *eligible* assignment for the `Arc SQL Estate Analyser` role. Step 1 (role definition) is the `az role definition create` above; step 3 (operator self-activation) is covered in the [Identity & authentication model](#identity--authentication-model) section below.

> **Prerequisites**
> - **Entra ID P2** license (or Entra Suite / Microsoft 365 E5) — required for Azure resource PIM. Verify via Entra admin center → Licenses.
> - An admin with the **Privileged Role Administrator** or **Owner** role at the target subscription or resource group scope, to create the eligible assignment.
> - The `Arc SQL Estate Analyser` role definition from the section above must already exist in the subscription.

#### Option A — Portal (simplest)

1. Open **Entra admin center** → **Privileged Identity Management** → **Azure resources**.
2. Select the target scope (subscription or resource group).
3. Choose **Roles** → **Add assignments**.
4. Select **Arc SQL Estate Analyser** as the role.
5. Set assignment type to **Eligible** (not Active).
6. Select the operator (user, group, or service principal).
7. Set the maximum eligibility duration (e.g. 6 or 12 months) and click **Assign**.

The operator can now self-activate just-in-time from **PIM → My roles** (see [activation snippet below](#identity--authentication-model)).

#### Option B — PowerShell (`Az.Resources`)

> There is **no first-class core `az` CLI command** for Azure-resource PIM eligibility. Use the Az.Resources PowerShell module or the `az rest` path below.

```powershell
# Install / import the module if not already present:
Install-Module Az.Resources -Scope CurrentUser -Force
Import-Module Az.Resources

# Resolve the role definition ID:
$role = Get-AzRoleDefinition -Name "Arc SQL Estate Analyser"

# Scope: subscription or resource group:
$scope = "/subscriptions/<subscription-id>/resourceGroups/<rg-name>"

# Operator object ID (user, group, or service principal):
$principalId = "<operator-object-id>"

# Eligibility window — 12-month expiry from now:
$scheduleInfo = New-Object Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleEligibilityScheduleRequestPropertiesScheduleInfo
$scheduleInfo.StartDateTime = [System.DateTime]::UtcNow
$scheduleInfo.Expiration = New-Object Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleEligibilityScheduleRequestPropertiesScheduleInfoExpiration
$scheduleInfo.Expiration.Type = "AfterDuration"
$scheduleInfo.Expiration.Duration = "P365D"

New-AzRoleEligibilityScheduleRequest `
  -Name (New-Guid).Guid `
  -Scope $scope `
  -PrincipalId $principalId `
  -RoleDefinitionId $role.Id `
  -RequestType "AdminAssign" `
  -ScheduleInfo $scheduleInfo
```

#### Option C — Azure CLI (`az rest`)

> There is **no first-class core `az` CLI command** for Azure-resource PIM eligibility. This `az rest` call hits the ARM `roleEligibilityScheduleRequests` API directly.

```bash
SCOPE="/subscriptions/<subscription-id>/resourceGroups/<rg-name>"
ROLE_DEF_ID=$(az role definition list --name "Arc SQL Estate Analyser" --query "[0].name" -o tsv)
PRINCIPAL_ID="<operator-object-id>"
REQUEST_GUID=$(python3 -c "import uuid; print(uuid.uuid4())")

az rest \
  --method PUT \
  --url "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/roleEligibilityScheduleRequests/${REQUEST_GUID}?api-version=2020-10-01" \
  --body "{
    \"properties\": {
      \"roleDefinitionId\": \"${SCOPE}/providers/Microsoft.Authorization/roleDefinitions/${ROLE_DEF_ID}\",
      \"principalId\": \"${PRINCIPAL_ID}\",
      \"requestType\": \"AdminAssign\",
      \"scheduleInfo\": {
        \"startDateTime\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
        \"expiration\": {
          \"type\": \"AfterDuration\",
          \"duration\": \"P365D\"
        }
      }
    }
  }"
```

#### Fallback — standing assignment (no PIM / no Entra ID P2)

If Entra ID P2 licensing or PIM is unavailable, use a **standing least-privilege assignment** of the same `Arc SQL Estate Analyser` custom role via the `az role assignment create` command already documented above. This is less ideal than JIT elevation (the role is permanently active rather than time-boxed), but the scope is still narrow and the permissions remain assessment-only.

---

## Identity & authentication model

Choose the identity type that matches how you run the agent:

| Run context | Recommended identity | Rationale |
|-------------|---------------------|-----------|
| **Interactive / consulting on a workstation** (common case) | Operator Entra ID user via `az login`; least-privilege role granted just-in-time via Entra PIM, scoped to specific subs/RGs | Named-user audit trail; MFA + Conditional Access enforced; time-bound elevation for the write-capable audit role. Managed identity is not available on a laptop. |
| **Unattended, hosted in Azure** (VM / Container App / Cloud Shell) | Managed identity (system- or user-assigned) with the custom role | No secret to store or rotate; only works when the agent runs on an Azure resource |
| **CI / GitHub Actions / Copilot coding agent** | Workload identity federation (OIDC) — service principal with no stored secret | Secretless, short-lived federated tokens; no rotation burden |
| ❌ **Avoid** | Long-lived service principal client secret | Standing credential = rotation burden + leak risk; prefer certificate or federated credential instead |

**Recommendation:** For interactive field and consulting runs, use the operator's own user context (`az login`). Managed identity is unreachable from a workstation. Apply least privilege via Entra PIM just-in-time elevation so that the write permissions the DMV audit requires (Run Command create/delete) exist only for the duration of the engagement. Reserve managed identity and workload identity federation for Azure-hosted or automated runs.

```bash
# Interactive login (workstation):
az login --tenant <tenant-id>

# Verify the active identity and subscription:
az account show

# If using PIM, activate the "Arc SQL Estate Analyser" role assignment before running:
# (Portal: Entra ID → Privileged Identity Management → My roles → Activate)
```

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
