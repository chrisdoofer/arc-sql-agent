# Executive Summary

- Summary point 1
- Summary point 2
- Summary point 3
- Summary point 4
- Summary point 5
- Enterprise → Standard downgrade readiness (if applicable): [GREEN / AMBER / RED]


# Estate summary

_Estate size determination: count distinct SQL Server instances from the validated dataset. State the tier at the top of this section._
_**Tier 1 (≤10 instances):** use full inline detail as shown below._
_**Tier 2 (11–50 instances) and Tier 3 (51+ instances):** replace inline instance/machine names with the aggregated distribution block and action-grouped machine inventory table shown in the "Tier 2/3 aggregated format" subsection below. Then continue with the remaining subsections (licensing, backup, utilisation) unchanged._

<!-- Tier 1 inline detail (use for ≤10 instances) -->

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
  - Dependency analysis type: Dependency Map API / Agentless (portal CSV) / Not available
  - Collection period: last 30 days

  | SQL Instance | Inbound connections (top 5) | Outbound connections (top 5) |
  |-------------|---------------------------|----------------------------|
  |             |                           |                            |


## Tier 2 / Tier 3 aggregated format (use for 11+ instances instead of inline names above)

_Replace the "Scope of estate analysed" and "Host / platform summary" inline text with the distribution block below. All other subsections (licensing, backup, utilisation, dependencies) remain unchanged._

```
Estate size: {N} instances — Tier 2 (aggregated) report format applied.

SQL instances: {N} across {M} machines
  Editions:  {N} Enterprise | {N} Standard | {N} Express
  Versions:  {N}× SQL 2022 | {N}× SQL 2019 | {N}× SQL 2016 (EoS) | {N}× SQL 2014 (EoS)
  Status:    {N} Connected | {N} Unreachable | {N} Disconnected
```

_Replace `Tier 2 (aggregated)` with `Tier 3 (aggregated)` for estates with 51+ instances. Replace all `{N}` and `{M}` placeholders with actual counts from the validated dataset._

### Machine inventory — action-oriented groupings (Tier 2/3)

_Replace any flat per-machine listing with this action-grouped table. Full machine inventory (one row per machine) moves to Appendix A._

| Migration target                    | Machines | Instances | Key characteristic                |
|-------------------------------------|----------|-----------|-----------------------------------|
| Azure SQL MI (Ready)                |          |           | No blockers identified            |
| Azure SQL MI (Remediation needed)   |          |           | Known blockers — see Appendix A   |
| SQL on Azure VM                     |          |           | MI-blocked, VM-ready              |
| Requires further assessment         |          |           | Unreachable or no assessment data |

_Full machine inventory (name, OS, version, edition, vCores, status) → Appendix A._


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

_**Tier 1 (≤10 instances):** use full inline detail as shown below._
_**Tier 2 (11–50 instances) and Tier 3 (51+ instances):** open with the summary counts block and compact GREEN listing, then show the structured audit tables for AMBER and RED records only. Full DMV results for GREEN instances move to Appendix B._
_**Tier 3 additional:** if AMBER/RED findings exceed 10, show top 10 ordered by severity (RED first) and state "Showing top 10 of {total} AMBER/RED findings — see Appendix B for complete list."_

## Tier 2/3 summary block (use for 11+ instances at the top of this section)

```
Downgrade candidates: {N} Enterprise instances
  GREEN (ready):    {N}
  AMBER (pending):  {N}
  RED (blocked):    {N}
```

GREEN instances (no blockers — full DMV results in Appendix B):
- {instanceName} on {machineName}
- ...

_Then continue with the structured audit tables below for AMBER and RED records only._

---

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

_**Tier 1 (≤10 instances):** use full per-machine detail tables as shown in "Detailed findings" below._
_**Tier 2 (11–50 instances) and Tier 3 (51+ instances):** replace per-machine detail tables with the estate-wide heatmap table shown below. Keep the pre-migration remediation checklist for Critical and High findings only. Per-machine detail tables move to Appendix C._
_**Tier 3 additional:** show only the top 10 failing checks in the heatmap (ordered by machines-affected count descending); state "Showing top 10 of {total} failing checks — see Appendix C for complete list." Add a percentage column to the heatmap: `{N}/{total} ({pct}%)`._

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

## Estate-wide findings heatmap (Tier 2/3 — use instead of per-machine detail tables below)

_Sort by severity descending (Critical → High → Medium → Low → Informational), then by machines-affected count descending within each severity band._
_Tier 3: add `({pct}%)` to the machines-affected column and truncate to top 10 with a "see Appendix C" note._

| Check ID | Check name | Category | Severity | Machines affected |
|----------|------------|----------|----------|-------------------|
|          |            |          |          |                   |

_Per-machine BPA detail tables → Appendix C._

## Detailed findings

_Use this section for Tier 1 (≤10 instances). For Tier 2/3, move per-machine detail to Appendix C and use the heatmap above instead._

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

_**Tier 1 (≤10 instances):** use full per-instance narrative as shown below._
_**Tier 2 (11–50 instances) and Tier 3 (51+ instances):** open with the action-grouped summary table, then follow with migration sequencing and SKU right-sizing at a group level. Per-instance TCO and licensing notes move to Appendix D._

## Action-grouped summary (Tier 2/3 — use instead of per-instance narrative below)

| Migration target  | Instances | Recommended action             | Confidence |
|-------------------|-----------|--------------------------------|------------|
| Azure SQL MI      |           | Ready — migrate in Wave 1      |            |
| Azure SQL MI      |           | Remediation needed before MI   |            |
| SQL on Azure VM   |           | Lift-and-shift candidates      |            |
| Further assess    |           | Additional data required       |            |

_Per-instance TCO notes and licensing position → Appendix D._

## Per-instance detail (Tier 1 — use for ≤10 instances)

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

_If migration assessment shows populated `skuRecommendationResults` or `serverAssessments`, use that data even when `assessmentUploadTime = null`, and disclose that the freshness timestamp is unavailable or inconsistent._

_Only if `assessment.enabled = true`, `assessmentUploadTime = null`, and recommendation fields are not populated, report: "Assessment collected but ARM sync pending — check Azure portal Migration > Assessments blade for latest results, or trigger 'Run Assessment' to force sync." Do NOT report this as "no assessment data exists"._

- Missing field or evidence 1:
- Missing field or evidence 2:
- Missing field or evidence 3:


# Appendix

_This section is present for **Tier 2 (11–50 instances) and Tier 3 (51+ instances) only**. Omit entirely for Tier 1 (≤10 instances)._
_For HTML/PDF export (Tier 3), wrap each sub-section in `<details><summary>…</summary>` so content is collapsible. In markdown output, use headings only — all content must remain visible._

## Appendix A — Full machine inventory

| Machine name | OS | SQL version | Edition | vCores | Status | Assessment status |
|-------------|-----|-------------|---------|--------|--------|------------------|
|             |     |             |         |        |        |                  |

## Appendix B — Enterprise downgrade audit: GREEN instance details

_Full per-database DMV audit results for instances classified GREEN. AMBER/RED detail is in the main report body._

| machineName | instanceName | databaseName | featureName | executionStatus | errorMessage |
|-------------|--------------|--------------|-------------|-----------------|--------------|
|             |              |              |             |                 |              |

## Appendix C — BPA alignment: per-machine detail

_Full check-by-check BPA findings for each machine. Estate-wide heatmap is in the main report body._

| Machine | Instance | Check ID | Check | Status | Severity | Current value | Expected value | Remediation |
|---------|----------|----------|-------|--------|----------|---------------|----------------|-------------|
|         |          |          |       |        |          |               |                |             |

## Appendix D — Azure target recommendation details

_Per-instance TCO notes, licensing position, and AHB eligibility. Action-grouped summary is in the main report body._

| Instance | Machine | Target | Readiness | Licensing / AHB note | TCO note |
|----------|---------|--------|-----------|----------------------|----------|
|          |         |        |           |                      |          |
