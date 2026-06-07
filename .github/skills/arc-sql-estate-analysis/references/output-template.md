# Executive Summary

- Summary point 1
- Summary point 2
- Summary point 3
- Summary point 4
- Summary point 5


# Estate summary

- Scope of estate analysed:
- Key version / edition findings:
- End-of-support or end-of-life exposure:
- Host / platform summary:

- Licensing position:
  - Licensing model (Server/CAL / Core / Unknown):
  - Software Assurance status (Enabled / Not enabled / Unknown):
  - Billing mode (Paid / PAYG / Free / Unknown):
  - Evidence / notes (cite explicit source signals; use "not confirmed" or "mixed signals" if fields are ambiguous or conflicting):

- Backup / monitoring / security posture:


# Key optimisation opportunities

- Opportunity 1:
  - Persisted feature findings:
  - Target edition support interpretation:
  - Runtime validation checklist:
    - See "Enterprise downgrade audit" section for detailed validation steps
  - Downgrade safety status:

- Opportunity 2:

- Opportunity 3:


# Enterprise downgrade audit

- Instances / databases audited:
- Audit method:
  Arc Run Command executing `sys.dm_db_persisted_sku_features`

---

## Structured audit results

| machineName | instanceName | databaseName | featureName | executionStatus | errorMessage |
|-------------|--------------|--------------|-------------|-----------------|--------------|
|             |              |              |             |                 |              |

---

## Persisted feature findings (summary)

- Total databases audited:
- Databases with persisted features:
- Databases with no persisted features:
- Failed audits (if any):

---

## Target edition support interpretation (SQL Server 2022 Standard)

- Interpret persisted feature findings against SQL Server 2022 Standard edition support:

- Feature(s) identified (if any):
  - Feature name: [feature]  
    - Supported in Standard: Yes / No / Verify required

- Interpretation notes:
  - If no features are returned:
    - state clearly that no persisted edition-restricted features were returned by the DMV
    - treat this as positive evidence, not final proof

---

## Runtime feature validation checklist (required before downgrade)

- Index operations (for example online index rebuild / create activity):
  - Why it matters:
  - How to validate:

- HA / DR configuration (for example Always On AG versus Basic AG):
  - Why it matters:
  - How to validate:

- Partitioning operations (for example partition switching / sliding window):
  - Why it matters:
  - How to validate:

- Workload governance (Resource Governor):
  - Why it matters:
  - How to validate:

- Compression usage for performance-critical workloads:
  - Why it matters:
  - How to validate:

---

## Downgrade readiness classification

- GREEN:
  - No persisted features detected
  - No runtime blockers identified
  - Safe to proceed

- AMBER:
  - No persisted features detected
  - Runtime validation outstanding
  - Proceed after validation

- RED:
  - Persisted features detected OR audit failed
  - Do not proceed without remediation

- Current status:
  - [GREEN / AMBER / RED]

---

## Downgrade confidence

- Per-instance or per-database confidence level:
  - Instance / Database: [name]  
    Confidence: [High / Medium / Low]  
    Rationale:

- Overall recommendation:
  - Conditional — confirm runtime validation before proceeding  
  - Not recommended — persisted blockers present  
  - Insufficient data — audit execution incomplete  

---

## Final decision guidance

- Enterprise → Standard downgrade:
  - Recommended / Conditional / Not recommended

- Decision rationale:
  - Based on persisted feature audit
  - Runtime validation status
  - Remaining risks and unknowns


# Quick wins

- Quick win 1:
  - Why it matters:
  - Expected benefit:
  - Confidence:

- Quick win 2:
  - Why it matters:
  - Expected benefit:
  - Confidence:

- Quick win 3:
  - Why it matters:
  - Expected benefit:
  - Confidence:


# Strategic moves

- Strategic move 1:
  - Why it matters:
  - Dependency / blocker:
  - Expected long-term benefit:
  - Confidence:

- Strategic move 2:
  - Why it matters:
  - Dependency / blocker:
  - Expected long-term benefit:
  - Confidence:

- Strategic move 3:
  - Why it matters:
  - Dependency / blocker:
  - Expected long-term benefit:
  - Confidence:


# Azure target recommendations

- Candidate workloads for Azure SQL Managed Instance:
  - Readiness status:
  - If Not Ready, blocker details:
  - Why it is blocked:
  - Remediation:

- Candidate workloads for SQL Server on Azure Virtual Machines:

- Candidate workloads for Arc-enabled SQL Server PAYG as an interim or transition path:

- Preferred target and rationale:


# Risks and blockers

- Risk 1:
- Risk 2:
- Risk 3:


# Data gaps / follow-up questions

- Missing field or evidence 1:
- Missing field or evidence 2:
- Missing field or evidence 3:
