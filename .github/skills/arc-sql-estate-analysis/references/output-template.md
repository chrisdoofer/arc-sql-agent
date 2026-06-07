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
  - Runtime validation checklist (required before confirming Enterprise → Standard downgrade is safe):
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
  - Downgrade safety status:
- Opportunity 2:
- Opportunity 3:

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

# Enterprise downgrade audit

- Instances / databases audited:
- Audit method: Arc Run Command executing `sys.dm_db_persisted_sku_features`

## Persisted feature findings

| Instance | Database | Feature name | Feature ID | Finding |
|----------|----------|--------------|------------|---------|
| | | | | No persisted Enterprise features detected / Feature detected — see interpretation |

## Target edition interpretation (SQL Server 2022 Standard)

- Feature(s) found and Standard edition support:
  - Feature name: [feature]  |  Supported in Standard: Yes / No / Verify required
- Interpretation notes (cite the SQL Server 2022 edition comparison matrix; use "requires verification" where uncertain):

## Remaining human validation required

- Items that must be confirmed before actioning a downgrade:
  - Item 1:
  - Item 2:

## Downgrade confidence

- Per-instance or per-database confidence level (High / Medium / Low):
  - Instance / Database: [name]  |  Confidence: [level]  |  Rationale:
- Overall downgrade recommendation: [Conditional — confirm items above before proceeding / Not recommended — persisted features present / Insufficient data — audit could not be executed]

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
