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

8. If the validation query fails, returns an unexpected scope, or live access cannot be trusted for tenant / subscription isolation:
   - stop immediately and report a scope validation error
   - in the error response, include requested tenant/subscription scope, observed scope from returned resources, and reason validation failed
   - do not produce estate analysis from unverified scope data (including unintended cross-tenant or cross-subscription results)
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

5. If uploaded data is used instead:
   - infer schema from the uploaded file
   - map fields to the analysis model where possible
   - clearly state any missing columns or unsupported inputs


## Phase 4 - Enterprise downgrade audit

1. You MUST attempt an Enterprise downgrade audit before making any Enterprise → Standard recommendation.

2. For each relevant user database on each Arc-enabled SQL instance:
   - attempt to execute the following query using an approved execution path (for example Arc Run Command or equivalent):
   
     SELECT feature_name
     FROM sys.dm_db_persisted_sku_features;

3. Treat this step as a REQUIRED data acquisition step:
   - do not skip execution due to partial data availability
   - do not proceed as if the audit was completed unless results are actually obtained

4. Handle results as follows:
   - If rows are returned:
     - surface the feature names clearly
     - treat them as potential downgrade blockers until interpreted against SQL Server 2022 Standard support
   - If no rows are returned:
     - explicitly state that the DMV returned no persisted edition-restricted features
     - treat this as positive evidence, but NOT conclusive proof that Enterprise is unnecessary
   - If execution fails or cannot be performed:
     - explicitly state that the Enterprise downgrade audit could not be executed
     - do not claim that no Enterprise features are in use
     - downgrade confidence for any Enterprise → Standard recommendation must be Low

5. The downgrade recommendation MUST distinguish between:
   - persisted feature evidence
   - target edition support interpretation
   - remaining human validation required

6. You MUST NOT:
   - claim "no Enterprise features in use" without DMV evidence
   - provide Medium or High confidence downgrade recommendations without successful audit execution or equivalent evidence


## Phase 5 - Analyse estate

1. Summarise the estate by host, instance, version, and edition where possible.

2. Flag end-of-support or end-of-life exposure.

3. Identify optimisation opportunities, including:
   - edition optimisation (e.g. Enterprise → Standard downgrade)
   - rightsizing opportunities
   - operational improvements (e.g. backup, monitoring, security)

4. When interpreting licensing:
   - Treat licensing model, Software Assurance status, and billing mode as separate dimensions (not a single "license type" field)
   - Assess each dimension independently from source evidence
   - Report licensing model only when explicitly evidenced (for example: Server/CAL, Core, Unknown)
   - Do not assume Software Assurance status from licenseType alone
   - Report Software Assurance as Enabled / Not enabled / Unknown based on explicit signals only
   - Report billing mode as Paid / PAYG / Free / Unknown based on explicit signals only
   - Do not infer Server/CAL from Paid billing or Software Assurance signals
   - If multiple signals are inconsistent or incomplete, mark licensing as Unknown or Mixed, use cautious wording (for example "appears", "not confirmed"), and surface this explicitly as a data gap

5. Identify combined optimisation opportunities that reduce total cost of ownership (TCO), including:
   - combining licensing optimisation (e.g. edition downgrade)
   - with Azure cost optimisation (e.g. PAYG via Arc, Azure Hybrid Benefit, or lower-cost Azure SKUs)
   - prioritising changes that can be applied together for maximum impact

6. Classify recommendations into:
   - Quick wins = low effort, immediate cost or risk reduction
   - Strategic moves = higher effort changes that provide medium- to long-term optimisation or Azure migration value

7. Recommend candidate Azure target options, for example:
   - Azure SQL Managed Instance
   - SQL Server on Azure Virtual Machines
   - Arc-enabled SQL Server PAYG as an interim transition option
   - When Azure SQL Managed Instance readiness metadata is available:
     - report the readiness state for each MI candidate
     - if a workload is marked Not Ready, retrieve the blocker details from the source data
     - explain briefly why the blocker prevents MI readiness
     - provide concise remediation steps tied to the evidenced blocker
     - if blocker detail is not available, state that clearly and add it to Data gaps / follow-up questions instead of inferring a reason

8. Separate confirmed findings from assumptions, unknowns, or missing fields.

9. Produce the final answer using the structure in `references/output-template.md`.

# Guardrails

- Keep findings evidence-based.
- Do not claim utilisation, savings, or migration suitability unless the source data supports it.
- If required fields are missing, state that plainly under Data gaps / follow-up questions.
- Do not infer Azure SQL Managed Instance blockers or remediation without explicit readiness evidence.
- Never recommend Enterprise → Standard downgrade with Medium or High confidence unless the Enterprise downgrade audit has executed successfully or equivalent evidence is explicitly available.
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
- Never proceed to analysis if tenant or subscription scope cannot be confidently validated.
- If returned resources appear to belong to a different tenant or subscription than requested, stop and report the issue.
- Always prioritise correctness of scope over completeness of output.

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

# Output requirements

Always produce the sections below in order:

1. Executive Summary (3–5 concise bullet points for CIO/IT Director audience, highlighting key risks, optimisation opportunities, and Azure direction)
2. Estate summary
3. Key optimisation opportunities
4. Azure target recommendations
5. Risks and blockers
6. Data gaps / follow-up questions
