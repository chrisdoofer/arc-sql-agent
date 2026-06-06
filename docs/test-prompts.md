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

