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
  - Software Assurance status (Enabled / Not confirmed / Unknown):
  - Declared SA-covered cores:
    - Standard edition:
    - Enterprise edition:
  - Billing mode (Paid / PAYG / Free / Unknown):
  - Azure Hybrid Benefit position:
    - Confirmed eligible cores:
    - Unconfirmed or uncovered cores:
  - Evidence / notes (cite explicit source signals; use "not confirmed" or "mixed signals" if fields are ambiguous or conflicting):

- Backup / monitoring / security posture:

- Workload utilisation baselines (from Azure Migrate, if available):
  - Source: Azure Migrate project "{projectName}" — assessment "{assessmentName}"
  - Collection period: {startDate} to {endDate}
  - Confidence rating: {confidenceRating}%

  | Machine | Avg CPU % | Avg Memory % | Data source |
  |---------|-----------|--------------|-------------|
  |         |           |              | Azure Migrate |

- Application dependency summary (from Azure Migrate, if available):
  - Dependency analysis type: Agentless / Not available
  - Collection period: last 30 days

  | SQL Instance | Inbound connections (top 5) | Outbound connections (top 5) |
  |-------------|---------------------------|----------------------------|
  |             |                           |                            |


# Key optimisation opportunities

- Opportunity 1:
  - Downgrade readiness: [GREEN / AMBER / RED]
  - Persisted feature findings:
  - Runtime validation results summary:
  - Target edition support interpretation:
  - SA / AHB interpretation:
  - TCO note: {always frame as impact on Azure migration cost — e.g. "reduces target Azure licensing by X" or "enables AHB eligibility for Azure target"}
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
- Compression interpretation:
  - SQL Server 2022 Standard supports compression
  - SQL Server Standard gained compression support in SQL Server 2016 SP1
  - If targeting pre-2016 SP1 Standard, treat compression as a potential blocker and validate explicitly

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


# SQL on Azure VM best practices alignment

- Execution depth (select one): [Tier 1 only (Resource Graph) | Tier 1+2 (Resource Graph + Log Analytics BPA) | Tier 1+2+3 (full scan with Arc Run Command fallback)]
- Machines scanned:
- Total checks executed:
- Pass: | Fail: | Warning: | Not assessed:

## Summary by category

| Category | Pass | Fail | Warning | Not assessed |
|----------|------|------|---------|--------------|
| Storage | | | | |
| Instance configuration | | | | |
| Security | | | | |
| HADR | | | | |
| Operations | | | | |

## Detailed findings

### Critical and High severity findings

| Machine | Instance | Check ID | Check | Status | Severity | Current value | Expected value | Remediation |
|---------|----------|----------|-------|--------|----------|---------------|----------------|-------------|
|         |          |          |       |        |          |               |                |             |

### Medium and Low severity findings

| Machine | Instance | Check ID | Check | Status | Severity | Current value | Expected value | Remediation |
|---------|----------|----------|-------|--------|----------|---------------|----------------|-------------|
|         |          |          |       |        |          |               |                |             |

### Informational

| Machine | Instance | Check ID | Check | Status | Severity | Detail |
|---------|----------|----------|-------|--------|----------|--------|
|         |          |          |       |        |          |        |

## Pre-migration remediation checklist

1. {Machine} — {Critical/High remediation action}
2. {Machine} — {next remediation action}
3. {Machine} — {next remediation action}


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
  - Licensing / AHB note:
  - TCO note: {frame as Azure target cost impact, not on-prem savings}
  - If Not Ready, blocker details:
  - Why it is blocked:
  - Remediation:

- Candidate workloads for SQL Server on Azure Virtual Machines:
  - Licensing / AHB note:
  - TCO note: {frame as Azure target cost impact, not on-prem savings}

- Candidate workloads for Arc-enabled SQL Server PAYG as an interim or transition path:
  - Licensing / AHB note:
  - TCO note: {frame as transition step towards Azure migration, not standalone on-prem optimisation}

- Preferred target and rationale:

- SKU right-sizing confidence (when Azure Migrate utilisation data is available):
  - Utilisation data available: Yes / No
  - If Yes: sizing recommendation validated against {collection period} performance baselines
  - If No: sizing based on configuration only — recommend deploying Azure Migrate for utilisation-based validation

- Migration sequencing recommendation (when Azure Migrate dependency data is available):
  - Migration wave 1: {instances with no inbound SQL dependencies — safe to migrate first}
  - Migration wave 2: {instances dependent on wave 1 targets}
  - Cross-instance dependencies: {SQL-to-SQL dependencies that require coordinated migration}
  - If dependency data not available: "Application dependency mapping not available — recommend enabling Azure Migrate dependency analysis to inform migration sequencing"


# Risks and blockers

- Risk 1:
- Risk 2:
- Risk 3:


# Data gaps / follow-up questions

_If Software Assurance status is `Not confirmed` or `Unknown`, add a follow-up asking the user to confirm active Software Assurance coverage and covered Standard / Enterprise core counts._

_If migration assessment shows `assessment.enabled = true` but `assessmentUploadTime = null`, report as: "Assessment collected but ARM sync pending — check Azure portal Migration > Assessments blade for latest results, or trigger 'Run Assessment' to force sync." Do NOT report this as "no assessment data exists"._

- Missing field or evidence 1:
- Missing field or evidence 2:
- Missing field or evidence 3:
