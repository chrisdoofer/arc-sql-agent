# Executive Summary

- Summary point 1
- Summary point 2
- Summary point 3
- Summary point 4
- Summary point 5
- Enterprise → Standard downgrade readiness (if applicable): [GREEN / AMBER / RED]


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
  - Downgrade readiness: [GREEN / AMBER / RED]
  - Persisted feature findings:
  - Runtime validation results summary:
  - Target edition support interpretation:
  - Downgrade safety status:

- Opportunity 2:

- Opportunity 3:


# Enterprise downgrade audit

- Instances / databases audited:
- Audit method:
  Arc Run Command executing `sys.dm_db_persisted_sku_features` and required runtime validation queries

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

## Runtime validation results (Arc Run Command)

| machineName | instanceName | checkName | result | executionStatus | errorMessage |
|-------------|--------------|-----------|--------|-----------------|--------------|
|             |              |           |        |                 |              |

- Required checks:
  - alwaysOnAvailabilityGroups
  - resourceGovernor
  - partitionedTables
  - onlineIndexOperations

---

## Target edition support interpretation (SQL Server 2022 Standard default)

- Interpret persisted feature findings against SQL Server 2022 Standard edition support:

- Feature(s) identified (if any):
  - Feature name: [feature]  
    - Supported in Standard: Yes / No / Verify required

- Interpretation notes:
  - If no features are returned:
    - state clearly that no persisted edition-restricted features were returned by the DMV
    - treat this as positive evidence, not final proof
  - Compression interpretation:
    - SQL Server 2022 Standard supports compression
    - SQL Server Standard gained compression support in SQL Server 2016 SP1
    - If targeting pre-2016 SP1 Standard, treat compression as a potential blocker and validate explicitly

---

## Runtime validation interpretation

- Always On availability groups:
  - Basic AG-only compatible or blocker identified:
- Resource Governor:
  - Enabled/disabled assessment:
- Partitioning:
  - Support status for chosen target version:
- Online index operations:
  - Runtime maintenance impact:

---

## Downgrade readiness classification

- GREEN:
  - DMV audit executed successfully with no persisted features detected
  - Runtime validation completed with no blockers identified
  - Technically ready to proceed (subject to business approval/change window)

- AMBER:
  - DMV audit executed successfully with no persisted features detected
  - Runtime validation incomplete, failed, or status unknown
  - Proceed after validation

- RED:
  - Persisted features detected in successful DMV audit OR audit failed or could not be completed OR confirmed runtime blockers
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
  - Recommended — persisted and runtime technical checks are clean
  - Conditional — runtime validation incomplete or pending business decision
  - Not recommended — persisted blockers present
  - Insufficient data — audit execution incomplete

---

## Final decision guidance

- Enterprise → Standard downgrade:
  - Recommended / Conditional / Not recommended

- Decision rationale:
  - Based on persisted feature audit
  - Runtime validation execution status and blockers
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
