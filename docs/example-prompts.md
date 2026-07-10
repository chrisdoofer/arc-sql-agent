# Example prompts

## Prompt 1 - basic assessment
Analyse this Arc-enabled SQL estate and recommend Azure optimisation paths.

## Prompt 2 - focus on EOL and rightsizing
Review this Arc-enabled SQL estate, identify end-of-life exposure and rightsizing opportunities, and suggest Azure landing options.

## Prompt 3 - customer-ready output
Assess this Arc-enabled SQL Server estate and produce a customer-ready summary with optimisation opportunities, Azure targets, blockers, and data gaps.

## Prompt 4 - branded PDF export
Assess this Arc-enabled SQL Server estate, generate the standard report, and then run `/export-pdf` to save a branded PDF to the working directory.

## Prompt 5 - include Azure Migrate utilisation and dependency data
Analyse this Arc-enabled SQL estate. Check if there's an Azure Migrate project in the tenant and include utilisation baselines and application dependency mapping in the analysis.

## Prompt 6 - migration sequencing with dependency analysis
Assess this SQL Server estate for Azure migration. I have Azure Migrate deployed with dependency analysis — please use that data to recommend migration wave sequencing based on application dependencies.

## Prompt 7 - right-sizing validation with Azure Migrate
Review this Arc-enabled SQL estate and validate SKU right-sizing recommendations using Azure Migrate performance data. I want to see actual CPU and memory utilisation alongside the sizing recommendations.

## Prompt 8 - include dependency CSV export from Azure Migrate
Analyse this Arc-enabled SQL estate. I've exported the dependency data from Azure Migrate as a CSV — here it is. Please include application dependency mapping in the analysis and recommend migration wave sequencing.

## Prompt 9 - retrieve dependencies directly via the Dependency Map API
Analyse this Arc-enabled SQL estate. I have an Azure Migrate Dependency Map set up — pull the dependency data directly via the `Microsoft.DependencyMap` API (no portal CSV export) and use it to recommend migration wave sequencing.

## Prompt 10 - unattended end-to-end analysis (zero further interaction)

> ⚠️ **WARNING — use with care.** This prompt grants **standing approval** for the skill to make **write changes to your Arc-enabled machines without asking again**: it installs/upgrades the Arc Run Command extension and creates, updates, and deletes Run Command resources (the reusable `estate-audit-*` slots), and executes the built-in DMV and runtime audit scripts against your SQL instances.
> There are **no per-step confirmations** once it starts.
> - Only use against an estate you **own and are authorized to audit**.
> - Confirm the **tenant and subscription scope** are correct before submitting — scope validation still runs, but standing approval means mistakes execute automatically within the validated scope.
> - Runs against **all** in-scope Enterprise DB-engine instances.
> - Prefer the interactive prompts (Prompts 1–9) for production estates or when you want to review each script first.
>
> Replace the `<...>` placeholders with your values.

Run the Arc-enabled SQL estate analysis unattended, end to end, with no further questions — treat every decision below as pre-answered and do not prompt me again.

- Tenant: <tenant-id-or-dns>
- Subscription scope: <all subscriptions | these subscription IDs: ...>
- Azure Migrate: use project <project-name> (or auto-select the only project in scope; if none, continue without it). Include utilisation baseline, application dependency mapping via the Microsoft.DependencyMap API, and Security Insights.
- Software Assurance: <Yes|No|Unsure> — Standard SA-covered cores: <n>, Enterprise SA-covered cores: <n>.
- Run the SQL on Azure VM best-practices alignment scan: yes, including the full Arc Run Command scan if Resource Graph/BPA coverage is incomplete.
- Enterprise downgrade audit: I pre-authorize all required Arc Run Command write operations on the in-scope machines — extension install/upgrade, and create/update/delete of the reusable estate-audit-* command slots — using the skill's built-in Pattern 1 (DMV) and Pattern 2 (runtime) reference scripts only. Run both stages across all Enterprise DB-engine instances. Do not ask me to approve individual machines or scripts; instead list every write operation you performed in the final report.
- Dependency data: pull directly via the Microsoft.DependencyMap API (no portal CSV prompt); if unavailable, note as a data gap and continue.
- Output: produce the full two-part report and export the branded HTML report to the working directory.

Standing-authorization phrase: "Run unattended — I pre-authorize all Arc Run Command write operations described in Phase 5 using the skill's built-in reference scripts."

If any required value above is missing or scope cannot be validated, stop and tell me rather than guessing.
