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
