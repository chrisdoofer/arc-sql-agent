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

## Test 11 – Enterprise downgrade audit

Assess an Arc-enabled SQL estate that includes Enterprise edition instances.

✅ Expected behaviour:

1. Audit execution
   - Attempt to run `sys.dm_db_persisted_sku_features` via Arc Run Command against each relevant user database on Enterprise edition instances
   - Record results per database; record any execution failure (connectivity, permission) with the failure reason

2. Output with persisted features detected
   - If the DMV returns one or more rows, surface each `feature_name` value clearly
   - Treat each feature as a potential downgrade blocker pending interpretation against SQL Server 2022 Standard
   - Do not recommend a downgrade for that database until each feature has been assessed
   - Set downgrade confidence to Low for that instance / database

3. Output with clean DMV result (no rows)
   - If the DMV returns no rows, record this as positive evidence
   - Do not claim the downgrade is safe without additional human confirmation
   - Set downgrade confidence to High only when no other Enterprise-specific signals are present; Medium when coverage is incomplete

4. Output when audit cannot be executed
   - Do not issue a downgrade recommendation based on inventory heuristics alone
   - Record the failure reason in the Enterprise downgrade audit section
   - Surface the gap under Data gaps / follow-up questions
   - Set downgrade confidence to Low

5. Output structure
   - Include a dedicated "Enterprise downgrade audit" section (after Key optimisation opportunities, before Azure target recommendations)
   - The section must clearly separate: persisted feature findings, target edition interpretation, and remaining human validation required
   - Use cautious, customer-safe wording; do not over-claim downgrade suitability
