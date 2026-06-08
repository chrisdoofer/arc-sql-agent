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
   - accept freeform numeric input for both prompts
   - store the declared values separately as Standard SA-covered cores and Enterprise SA-covered cores

3. If the user selects `No` or `Unsure`:
   - record Software Assurance status as `Not confirmed` for `No`
   - record Software Assurance status as `Unknown` for `Unsure`
   - continue the analysis, but state that Azure Hybrid Benefit eligibility could not be confirmed
   - add the missing SA confirmation to `Data gaps / follow-up questions`

4. Use the declared Software Assurance response during analysis:
   - populate the `Software Assurance status` field in Estate summary from the declared answer
   - use declared Standard and Enterprise SA-covered core counts to assess Azure Hybrid Benefit eligibility
   - factor declared SA-covered cores into TCO comparisons for Azure target recommendations
   - if Enterprise SA-covered cores are declared but the recommendation favours Standard edition, highlight that SA entitlements may need reassignment or repurposing

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

4. If live Azure scope is validated, collect Arc-enabled SQL estate data from the confirmed tenant / subscription scope:
   - SQL Server instances
   - databases
   - Arc-enabled host machines
   - any available assessment / readiness / backup / security metadata

5. If uploaded data is used instead:
   - infer schema from the uploaded file
   - map fields to the analysis model where possible
   - clearly state any missing columns or unsupported inputs


## Phase 5 - Enterprise downgrade audit

1. You MUST attempt an Enterprise downgrade audit before making any Enterprise → Standard recommendation.

2. Use a real execution path after tenant/subscription scope has been validated:
   - identify target Arc-enabled SQL instances from the validated scope dataset
   - for each target instance, enumerate relevant user databases (`database_id > 4`) that are online; include read-only databases because they can still return persisted feature evidence
   - execute the downgrade DMV in each user database using Arc Run Command (or equivalent approved execution method)
   - set database context via the execution method's database parameter/context option for each database (do not rely on a `USE` statement as the only context selector)
   - run:
     SELECT feature_name
     FROM sys.dm_db_persisted_sku_features;

3. Capture results in a structured per-database output record using this minimum schema:
   - machineName
   - instanceName
   - databaseName
   - featureName
   - executionStatus
   - errorMessage
   - field names are mandatory and must use this exact camelCase naming
   - downstream processing depends on exact key matches; do not rename or reformat these keys

4. Populate structured output as follows:
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

5. Treat this step as a REQUIRED data acquisition step:
   - do not skip execution due to partial data availability
   - do not proceed as if the audit was completed unless results are actually obtained

6. Handle results as follows:
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

7. The downgrade recommendation MUST distinguish between:
   - persisted feature evidence
   - target edition support interpretation
   - runtime / operational feature usage results
   - remaining business-impact validation required

8. You MUST execute a separate runtime feature validation stage via Arc Run Command alongside the DMV findings before presenting any Enterprise → Standard downgrade as safe to proceed:
   - treat the DMV audit as persisted feature validation only
   - execute runtime checks sequentially per machine (avoid concurrent Run Command conflicts on the same host)
   - execute the following runtime queries on each relevant instance:
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
   - adapt `Invoke-Sqlcmd` parameters to host module capability:
     - older environments may not support `-TrustServerCertificate`
     - detect support by checking `Get-Command Invoke-Sqlcmd` parameter metadata for `TrustServerCertificate` before command construction
     - include `-TrustServerCertificate` only when supported/required by the host
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

9. You MUST classify each Enterprise → Standard downgrade readiness using the following classification model:
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

10. The classification MUST be surfaced in:
   - Executive Summary (include classification status for any downgrade opportunities)
   - Key optimisation opportunities (for Enterprise → Standard recommendations)
   - Enterprise downgrade audit section (detailed classification)

11. You MUST NOT:
   - claim "no Enterprise features in use" without DMV evidence
   - provide Medium or High confidence downgrade recommendations without successful audit execution or equivalent evidence

12. Execution reliability considerations:

- You MUST consider execution reliability when using Arc Run Command or equivalent execution methods.

- Execution sequencing:
  - Prefer sequential execution per machine.
  - Avoid creating multiple Run Command executions concurrently on the same machine, as this may result in execution conflicts (for example HCRP500 errors).

- Execution environment variability:
  - Be aware that execution environments may differ by host version.
  - Older SQL Server hosts may use earlier versions of the SqlServer PowerShell module.
  - Adapt command parameters accordingly (for example, some environments may not support -TrustServerCertificate).

- Script execution approach:
  - Prefer simple, single-command execution patterns.
  - Avoid multi-line script constructs where transmission or parsing reliability is uncertain.

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

3. Identify optimisation opportunities, including:
   - edition optimisation (e.g. Enterprise → Standard downgrade)
   - rightsizing opportunities
   - operational improvements (e.g. backup, monitoring, security)
   - Do not use indirect signals (e.g. database properties such as isMemoryOptimizationEnabled) as proof of Enterprise feature usage.
   - Treat such signals as indicative only and require DMV confirmation for downgrade decisions.
   - For Enterprise → Standard downgrade candidates, present:
     - persisted feature findings from `sys.dm_db_persisted_sku_features`
     - runtime validation execution results from Arc Run Command checks
     - target edition support interpretation (including compression support for selected target version)
   - GREEN readiness can be used only when persisted and runtime technical checks are completed and clean

4. When interpreting licensing:
   - Treat licensing model, Software Assurance status, and billing mode as separate dimensions (not a single "license type" field)
   - Assess each dimension independently from source evidence
   - Report licensing model only when explicitly evidenced (for example: Server/CAL, Core, Unknown)
   - Do not assume Software Assurance status from licenseType alone
   - Prefer the user's declared Phase 3 response for Software Assurance status over ambiguous Azure metadata
   - Report Software Assurance as Enabled / Not confirmed / Unknown based on the declared response when available; otherwise use explicit source signals only
   - Report billing mode as Paid / PAYG / Free / Unknown based on explicit signals only
   - Do not infer Server/CAL from Paid billing or Software Assurance signals
   - Use declared Standard and Enterprise SA-covered core counts to determine whether Azure Hybrid Benefit applies fully, partially, or cannot be confirmed
   - If declared SA-covered cores are lower than the target Azure core requirement, state that only the covered portion appears eligible for Azure Hybrid Benefit and treat the remainder as licence-included / PAYG exposure unless other explicit evidence exists
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
   - explicitly state whether Azure Hybrid Benefit appears eligible based on the declared SA-covered cores
   - reflect the declared SA position in TCO comparisons and PAYG versus licence-included guidance
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
- Never describe an Enterprise → Standard downgrade as fully safe unless runtime feature validation has also been completed.
- Prefer concise, customer-ready wording.
- Apply confidence inline to each recommendation only in:
  - Key optimisation opportunities
  - Azure target recommendations
- Use only these confidence levels:
  - High = strong direct evidence
  - Medium = reasonable inference with some gaps
  - Low = limited data or assumptions required
 
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
4. Enterprise downgrade audit
5. Azure target recommendations
6. Risks and blockers
7. Data gaps / follow-up questions
