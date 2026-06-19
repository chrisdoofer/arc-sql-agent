---

# Regression Test Prompts (Do not modify)

⚠️ These prompts are used for regression testing. Do not modify without updating expected behaviour.

## Test 1 – Generic estate
Analyse an Arc-enabled SQL estate and recommend Azure optimisation paths.

## Test 2 – EOL-heavy estate
Assess an Arc-enabled SQL estate with multiple SQL Server 2016 instances and identify risk and prioritised actions.

## Test 3 – Cost optimisation focus
Review this Arc-enabled SQL estate and identify cost optimisation and licensing improvement opportunities.

## Test 4 – Customer-ready output
Assess this Arc-enabled SQL Server estate and produce a customer-ready recommendation summary.

## Test 5 – Incomplete data scenario
Analyse this partial SQL estate dataset and clearly identify data gaps and assumptions.

## Test 6 – Tenant-scoped query with false-negative protection

Connect to tenant <tenant-id> and analyse an Arc-enabled SQL estate.

User expectation: Arc-enabled SQL resources exist in the selected subscription.

✅ Expected behaviour:

1. Scope selection (workflow validation)
- List subscriptions in the specified tenant
- Ask the user to confirm the subscription scope
- Do NOT proceed to analysis before confirmation

2. Initial validation (scope correctness)
- Perform validation query
- Confirm tenant and subscription alignment

3. False negative detection (resilience validation)
- If query returns no resources:
  - DO NOT assume no data exists
  - Ask the user to confirm expectation

4. Recovery behaviour (tool reliability)
- Retry using:
  - alternative query structure
  - relaxed filters
  - fallback execution method (e.g. Azure CLI)

5. Final behaviour
- Use validated dataset (from MCP or fallback)
- Proceed with structured analysis
- ## Test – Tenant-scoped query with false-negative protection

Connect to tenant <tenant-id> and analyse an Arc-enabled SQL estate.

User expectation: Arc-enabled SQL resources exist in the selected subscription.

✅ Expected behaviour:

1. Scope selection (workflow validation)
- List subscriptions in the specified tenant
- Ask the user to confirm the subscription scope
- Do NOT proceed to analysis before confirmation

2. Initial validation (scope correctness)
- Perform validation query
- Confirm tenant and subscription alignment

3. False negative detection (resilience validation)
- If query returns no resources:
  - DO NOT assume no data exists
  - Ask the user to confirm expectation

4. Recovery behaviour (tool reliability)
- Retry using:
  - alternative query structure
  - relaxed filters
  - fallback execution method (e.g. Azure CLI)

5. Final behaviour
- Use validated dataset (from MCP or fallback)
- Proceed with structured analysis
- Clearly state if fallback method was used

## Test 7 – Fallback behaviour
If live Azure scope cannot be validated, offer Excel / JSON / CSV upload instead of producing an untrusted analysis.


## Test 8 – Wrong-scope protection

Connect to tenant <tenant-id> and analyse an Arc-enabled SQL estate. 

Requirements:
- Do not proceed with analysis unless tenant and subscription scope is validated
- If returned resources do not belong to the requested tenant or subscription, stop and report a scope error
- Do not produce analysis using unverified or cross-tenant results
- Offer fallback to Excel, JSON, or CSV input if validation fails

## Test 9 – MI readiness blocker explanation

Assess an Arc-enabled SQL estate where Azure SQL Managed Instance readiness metadata marks a workload as Not Ready.

✅ Expected behaviour:

- Retrieve the blocker detail from the readiness evidence
- Explain why the workload is marked Not Ready
- Provide concise remediation steps
- If blocker detail is missing, say so and treat it as a data gap
- Keep the existing output sections and keep wording concise

## Test 10 – Licensing signal ambiguity handling

Analyse this Arc-enabled SQL estate where:
- `licenseType` is present but licensing model is not explicitly stated
- Software Assurance evidence is partial and inconsistent across hosts
- Billing signal shows Paid for some resources and PAYG for others

✅ Expected behaviour:
- Report licensing model, Software Assurance, and billing mode as separate attributes
- Do not infer Server/CAL unless explicitly confirmed in source data
- Use Unknown or Mixed where evidence is incomplete or inconsistent
- Use cautious wording such as "appears" or "not confirmed"

## Test 11 – Enterprise downgrade DMV execution outcomes

Assess an Arc-enabled SQL estate and evaluate Enterprise → Standard opportunities.

✅ Expected behaviour:
- Before executing the DMV audit script via Arc Run Command, present the full consolidated script content in a markdown code block showing: target machine, instance name, purpose, estimated execution time, and the complete script (Pattern 1 — DMV audit)
- Request approval via `ask_user` with choices: `["Approve and execute", "Skip this check", "Modify script first"]` before submitting the script
- Before executing the runtime validation script, present the full consolidated runtime script in a markdown code block with the same header fields; request approval separately
- When the same script template targets multiple machines, offer batch approval: `["Approve for all listed machines", "Approve individually per machine", "Skip all"]`
- If the user selects **Skip this check** or **Skip all**: set `executionStatus = Skipped` for affected machines; note the declined check in output; downgrade confidence falls to Low
- If the user selects **Modify script first**: collect modifications, re-present the updated script in full, and request approval again before executing
- Never submit a script via Arc Run Command without first showing the user the full script content and receiving explicit approval
- Execute `sys.dm_db_persisted_sku_features` against relevant user databases on validated Arc-enabled SQL instances using Arc Run Command (or equivalent approved execution path)
- Clearly separate persisted feature validation from runtime / operational feature usage validation
- Return structured per-database audit records containing:
  - `machineName`
  - `instanceName`
  - `databaseName`
  - `featureName`
  - `executionStatus`
  - `errorMessage`
- Distinguish clearly between:
  - successful execution with returned feature rows
  - successful execution with no persisted features (`featureName = null`, `executionStatus = Succeeded`)
  - failed execution (`executionStatus = Failed` with captured error)
- Execute runtime validation checks via Arc Run Command for:
  - Always On availability groups
  - Resource Governor
  - partitioned tables
  - SQL Agent job steps using `ONLINE=ON` index operations
- Return structured per-check runtime records containing:
  - `machineName`
  - `instanceName`
  - `checkName`
  - `result`
  - `executionStatus`
  - `errorMessage`
- Interpret compression support against target downgrade version:
  - SQL Server 2022 Standard is the default downgrade target and supports compression
  - If a pre-2016 SP1 Standard target is chosen, treat compression as a potential blocker
  - For pre-2016 SP1 targets, validate compression usage explicitly (for example, check `sys.partitions.data_compression_desc` for PAGE/ROW compression)
- Do not present the downgrade as fully safe unless runtime validation is also completed
- Keep downgrade confidence Low when execution fails or cannot be completed
- Include downgrade readiness classification (GREEN / AMBER / RED) in:
  - Executive Summary
  - Key optimisation opportunities
  - Enterprise downgrade audit section
- Apply classification logic:
  - GREEN = no persisted features + runtime validation completed with no blockers
  - AMBER = no persisted features + runtime validation not yet completed
  - RED = persisted features present OR audit failed OR confirmed runtime blockers

## Test 12 – Software Assurance declaration flow

Assess this Arc-enabled SQL estate and provide Azure licensing guidance.

✅ Expected behaviour:
- After tenant and subscription scope validation, ask: `Do you have active Software Assurance coverage on any SQL Server licences in this estate?`
- Offer choices: `Yes`, `No`, `Unsure`
- If the user answers `Yes`, ask for:
  - SQL Server Standard edition cores covered by Software Assurance
  - SQL Server Enterprise edition cores covered by Software Assurance
- Use the declared Software Assurance status in Estate summary
- Use declared core counts to assess Azure Hybrid Benefit eligibility and TCO guidance
- If the answer is `No` or `Unsure`, continue analysis but state that AHB eligibility is not confirmed
- Add missing Software Assurance confirmation to `Data gaps / follow-up questions`

## Test 13 – Assessment telemetry sync-pending handling

Assess an Arc-enabled SQL estate where:
- Instance A has `assessment.enabled = true`, `assessmentUploadTime = null`, and `skuRecommendationResults = null`
- Instance B has `assessment.enabled = true`, `assessmentUploadTime` populated, and non-null `skuRecommendationResults`
- The Azure portal shows assessment details for both instances

✅ Expected behaviour:
- Do not classify Instance A as "no assessment exists"
- Classify Instance A as sync-pending and state that assessment data may exist in the portal telemetry plane
- Use ARM `skuRecommendationResults` / `serverAssessments` for Instance B because sync is complete
- If asked about programmatic telemetry retrieval, state that no documented public API is currently available unless validated evidence is returned in-session
- Recommend portal "Run Assessment" or waiting for scheduled sync for sync-pending instances

## Test 14 – Script review and approval before Arc Run Command execution

Assess an Arc-enabled SQL estate with two Enterprise instances (ArcBox-SQL and ARCBOX-SQL2016) and evaluate Enterprise → Standard downgrade opportunities.

✅ Expected behaviour:
- Before submitting the DMV audit script to either machine, present the full script content (Pattern 1 — DMV audit) in a markdown code block
- Presentation includes: target machine name, instance name, purpose description, estimated execution time, and the untruncated script
- Because two machines share the same script template, offer batch approval: `["Approve for all listed machines", "Approve individually per machine", "Skip all"]`
- Before submitting the runtime validation script, present the full consolidated runtime script (Pattern 2) separately, with the same header fields
- If the user declines the DMV audit: set `executionStatus = Skipped` for both machines; note the declined check in output; downgrade confidence falls to Low for both machines
- If the user selects **Modify script first**: collect changes, re-present the updated script in full, then request approval again
- Never encode and submit a script via `az rest --method PUT` (or any Arc Run Command path) unless the full script has been presented and the user has explicitly approved execution

❌ Failure indicators:
- Agent submits a run command without first displaying the script content
- Agent shows only a summary or description instead of the full script
- Agent proceeds with execution after the user selects Skip or declines
- Agent does not offer batch approval when multiple machines share the same script template
