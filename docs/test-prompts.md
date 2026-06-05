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

## Test 6 – Tenant-scoped live query

Connect to tenant <tenant-id> and analyse an Arc-enabled SQL estate.

✅ Expected behaviour:
- List subscriptions
- Ask for confirmation
- Do NOT analyse before confirmation


## Test 7 – Fallback behaviour
If live Azure scope cannot be validated, offer Excel / JSON / CSV upload instead of producing an untrusted analysis.
``
