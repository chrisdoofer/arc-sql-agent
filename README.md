# Arc SQL Estate Analyser

A GitHub Copilot skill and custom agent that performs live assessment of Arc-enabled SQL Server estates and produces structured optimisation and migration recommendations for Azure.

## What it does

- Connects to an Azure tenant and discovers Arc-enabled SQL Server instances, databases, and host machines
- Validates tenant/subscription scope before analysis (rejects cross-tenant data leaks)
- Executes Enterprise → Standard edition downgrade audits via Arc Run Command
- Produces a customer-ready report covering estate summary, optimisation opportunities, Azure target recommendations, risks, and data gaps
- Can export the final report as branded self-contained HTML or PDF (`/export-pdf`)
- Applies evidence-based confidence levels (High / Medium / Low) and downgrade readiness classifications (GREEN / AMBER / RED)

## Quick Start

```bash
# 1. Authenticate to your Azure tenant
az login --tenant <your-tenant-id>

# 2. Open the repository in GitHub Copilot CLI
cd arc-sql-estate-analysis

# 3. Run an analysis
#    Prompt: "Connect to tenant <tenant-id> and analyse Arc-enabled SQL estate"
```

## Documentation

| Document | Description |
|----------|-------------|
| [Solution Architecture](docs/architecture.md) | Component roles, data flow, design principles |
| [Prerequisites](docs/prerequisites.md) | Required software, RBAC permissions, Arc requirements |
| [Workflow Flowchart](docs/workflow-flowchart.md) | Step-by-step execution flow with decision points |
| [Data Transparency](docs/data-transparency.md) | Exactly what data is collected, where it goes, and what is NOT accessed |
| [Power BI Fabric refresh setup](powerbi/FABRIC-REFRESH-SETUP.md) | Post-publish cloud connection, privacy, gateway, and scheduled-refresh configuration |
| [Power BI licensing inputs](powerbi/LICENSING-INPUTS.md) | Configure Software Assurance evidence, edition-covered cores, and AHB reconciliation |
| [Security exposure pipeline](.github/skills/arc-sql-estate-analysis/references/security-exposure.md) | Azure Update Manager + external CVE intelligence design (assessment-only) |
| [Example Prompts](docs/example-prompts.md) | Sample prompts for different analysis scenarios |

## Key Technologies

| Technology | Role |
|-----------|------|
| GitHub Copilot CLI | Agent runtime and orchestration |
| Azure Resource Graph | Primary data source for inventory queries and Azure Update Manager patch-assessment data |
| Azure CLI | Fallback query execution and scope validation |
| Arc Run Command | Remote T-SQL execution for Enterprise downgrade audit |
| Azure Update Manager | Assessment-only source of missing-patch data (via Resource Graph); core of the security-exposure path |
| Microsoft Security Update Guide (MSRC) + NVD | External CVE intelligence — KB→CVE mapping and CVE metadata enrichment |
| Azure Arc-enabled SQL Server | Source estate being analysed |

> **CVE enrichment is optional and needs no setup to start** — MSRC (the primary KB→CVE source)
> needs no API key, and NVD works keyless. An optional free NVD API key only raises the NVD rate
> limit for faster enrichment on large estates. See [CVE enrichment & secrets](docs/prerequisites.md#cve-enrichment--secrets-optional)
> for how to obtain and safely store a key (env var, SecretManagement vault, or GitHub secret).

## Repository Structure

```
.github/
  agents/
    sql-estate-architect.agent.md    ← Agent persona (delegates to skill)
  skills/
    arc-sql-estate-analysis/
      SKILL.md                       ← Core analysis workflow and guardrails
      references/
        output-template.md           ← Canonical report structure
        branded-report-template.md   ← Branded self-contained HTML template for PDF export
        command-templates.md         ← PowerShell command templates for Arc Run Command execution
        security-exposure.md         ← Azure Update Manager + external CVE intelligence design (assessment-only)
        scripts/
          ArcSqlSecurityExposure.psm1 ← Deterministic helpers (KB extraction, confidence, assessment-only guardrail)
docs/
  architecture.md                    ← Solution architecture
  prerequisites.md                   ← Setup and RBAC requirements
  workflow-flowchart.md              ← Execution flowchart
  data-transparency.md              ← Data collection transparency
  example-prompts.md                 ← Example usage prompts
  testing/
    Test-SecurityExposure.ps1        ← Runnable unit tests for the security-exposure helpers
    Test-SecurityExposure.Live.ps1   ← Network-gated live MSRC/NVD provider validation
README.md                            ← This file
```

## Security & Data Handling

- **Read-only** — All inventory data is collected via read-only Resource Graph queries
- **Minimal execution** — A small set of read-only T-SQL metadata queries are run remotely for downgrade validation (`sys.dm_db_persisted_sku_features` plus runtime checks for AG, Resource Governor, partitioning, and `ONLINE=ON` job usage)
- **No user data accessed** — No table data, credentials, query plans, or application code is read
- **Scope-validated** — Analysis refuses to proceed if tenant/subscription scope cannot be verified
- **No data leaves tenant** — Everything runs within the Azure control plane; reports are generated locally

See [Data Transparency](docs/data-transparency.md) for full details.

## Licence

MIT
