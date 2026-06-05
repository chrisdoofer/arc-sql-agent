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

## Phase 2 - Validate live Azure scope before analysis

1. Before running full estate analysis, perform a lightweight validation query against the selected tenant / subscription scope:
   - confirm that Arc-enabled SQL Server resources or Arc-enabled machines are visible in the chosen scope
   - verify returned tenant and subscription identifiers match the requested scope
   - if returned resources do not belong to the requested tenant / subscription scope, treat the result as invalid and do not continue with analysis
   - Detect potential false-negative or unreliable query results:
   - If the validation query returns no resources but the user explicitly expects data:
     - treat the result as potentially unreliable
     - do not conclude that no resources exist yet

2. If query results are inconsistent, empty, or suspected to be incorrect:
   - attempt an alternative query approach before proceeding, such as:
     - adjusting the query structure
     - removing inline filters and relying on explicit subscription scoping
     - using an alternative execution method (e.g. Azure CLI)

3. Only proceed to analysis when:
   - at least one validated and consistent dataset has been obtained
   - or the agent has clearly confirmed that no data exists after multiple query attempts

4. If multiple query methods produce conflicting results:
   - prefer the dataset that:
     - aligns with explicit tenant and subscription scope
     - returns consistent and complete resource identifiers
   - clearly explain which data source was used and why

5. If the validation query fails, returns an unexpected scope, or live access cannot be trusted for tenant / subscription isolation:
   - clearly state that live Azure scope could not be validated
   - offer fallback input modes:
     - Excel export
     - JSON export
     - CSV export

## Phase 3 - Acquire estate data

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

3. If a fallback query method is used (e.g. Azure CLI):
   - treat the fallback result as the authoritative dataset if it resolves previous inconsistencies
   - clearly note that an alternative acquisition method was required

4. If live Azure scope is validated, collect Arc-enabled SQL estate data from the confirmed tenant / subscription scope:
   - SQL Server instances
   - databases
   - Arc-enabled host machines
   - any available assessment / readiness / backup / security metadata

5. If uploaded data is used instead:
   - infer schema from the uploaded file
   - map fields to the analysis model where possible
   - clearly state any missing columns or unsupported inputs

## Phase 4 - Analyse estate

1. Summarise the estate by host, instance, version, and edition where possible.
2. Flag end-of-support or end-of-life exposure.
3. Identify edition-related optimisation opportunities such as Enterprise-to-Standard downgrade candidates.
4. Review available sizing or utilisation indicators and note obvious rightsizing opportunities.
5. Recommend candidate Azure target options, for example:
   - Azure SQL Managed Instance
   - SQL Server on Azure Virtual Machines
   - Arc-enabled SQL Server PAYG as an interim transition option
6. Separate confirmed findings from assumptions, unknowns, or missing fields.
7. Produce the final answer using the structure in `references/output-template.md`.

# Guardrails

- Keep findings evidence-based.
- Do not claim utilisation, savings, or migration suitability unless the source data supports it.
- If required fields are missing, state that plainly under Data gaps / follow-up questions.
- Prefer concise, customer-ready wording.
- Apply confidence inline to each recommendation only in:
  - Key optimisation opportunities
  - Azure target recommendations
- Use only these confidence levels:
  - High = strong direct evidence
  - Medium = reasonable inference with some gaps
  - Low = limited data or assumptions required
 
## Tenant and scope guardrails

- Never assume that a tenant or subscription filter has been applied correctly just because it was passed to a tool.
- Always verify that returned resources belong to the tenant / subscription scope requested by the user before continuing with analysis.
- If returned resources belong to a different subscription or tenant than requested, stop and report a scope validation failure.
- Do not produce a full estate analysis until scope has been validated.
- If live tenant scope cannot be validated, offer fallback analysis via uploaded Excel, JSON, or CSV data.

## Tool reliability guardrails

- Do not assume that execution tools (e.g. Azure MCP, Resource Graph) correctly apply tenant or subscription scoping.
- Treat empty or unexpected query results as potentially unreliable when they conflict with user expectations.
- Always attempt to validate or corroborate query results before concluding that no resources exist.
- Use alternative query approaches or execution methods when initial results are inconsistent or suspect.
- Prefer validated, scope-aligned data over first-returned results.
- Clearly communicate when fallback methods are used to obtain reliable data.

# Output requirements

Always produce the sections below in order:

1. Executive Summary (3–5 concise bullet points for CIO/IT Director audience, highlighting key risks, optimisation opportunities, and Azure direction)
2. Estate summary
3. Key optimisation opportunities
4. Azure target recommendations
5. Risks and blockers
6. Data gaps / follow-up questions
