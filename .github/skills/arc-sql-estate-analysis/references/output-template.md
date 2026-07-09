# Part 1 — Executive Briefing

_Audience: CIO / IT Director / business decision-maker. Concise, business-framed narrative. No per-database or per-instance raw tables. Every point is framed through reliability, cost, security, and end-of-support risk lenses — and connects to Azure migration or modernisation as the outcome._

## Executive Summary

- Summary point 1
- Summary point 2
- Summary point 3
- Summary point 4
- Summary point 5
- Enterprise → Standard downgrade readiness (if applicable): [GREEN / AMBER / RED]


## Estate at a glance

_Headline counts only — no per-instance or per-database tables. Full distributions are in Part 2._

- Total SQL Server instances:
- Total host machines:
- Editions: {N} Enterprise | {N} Standard | {N} Express | {N} Other
- End-of-support / end-of-life exposure: {N} instances on EoS versions (SQL 2014 / 2016 / 2017)
- Security posture headline: {N} Critical CVEs | {N} High CVEs | Max CVSS: {score} (or: No Security Insights data available)
- Downgrade candidates: {N} Enterprise → Standard (GREEN: {N} | AMBER: {N} | RED: {N}) _(if applicable)_


## Key risks and issues

_High-level, framed by reliability / cost / security. No per-machine tables._

- **Reliability:** {key reliability risk — e.g. EoS exposure, unpatched OS, no HA/DR, backup gaps}
- **Cost:** {key cost risk — e.g. over-licensed Enterprise editions, PAYG exposure, unconfirmed AHB eligibility}
- **Security:** {key security risk — e.g. Critical/High CVEs, missing patches, unencrypted data at rest}
- **End-of-support:** {EoS/EoL instances and associated risk — e.g. no security updates, MI/VM migration urgency}


## Strategic migration and modernisation opportunities

_Summary-level view. Full detail with execution steps is in Part 2._

- **Enterprise → Standard downgrade opportunity:** GREEN: {N} | AMBER: {N} | RED: {N}
  - Headline direction: {e.g. "Downgrading {N} eligible instances before migration reduces Azure licensing cost and enables Azure Hybrid Benefit eligibility"}
- **Azure migration opportunities:** {brief summary — e.g. "{N} instances assessed as Ready for Azure SQL MI; {N} require remediation before MI"}
- **Licensing / AHB opportunity:** {e.g. "Declared SA-covered cores support AHB eligibility for {N} instances — confirm to avoid PAYG exposure on Azure"}
- **Quick wins:** {e.g. "{N} low-effort improvements that directly improve Azure migration readiness"}


## Recommended Azure direction

_Target options at a glance. Per-instance SKU detail, TCO, and sequencing are in Part 2._

- **Primary target:** {Azure SQL Managed Instance / SQL Server on Azure VM / Mixed}
  - Indicative benefit: {e.g. "Removes on-premises infrastructure management overhead; improves reliability through managed HA/DR and automatic patching"}
- **Interim option:** {Arc-enabled SQL Server PAYG as transition step, if applicable}
- **Migration wave outline:** {e.g. "Wave 1: {N} instances ready now; Wave 2: {N} instances pending remediation"}
- **Azure Hybrid Benefit position:** {eligible / partially eligible / not confirmed — brief note}


---

# Part 2 — Technical Detail & Execution Guide

_Audience: DBA / Security / Infrastructure Engineer. Full depth for action. Contains all existing sections with per-instance and per-database detail, execution guidance, and appendices._

## Estate summary

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


## Key optimisation opportunities

- Opportunity 1:
  - Downgrade readiness: [GREEN / AMBER / RED]
  - Persisted feature findings:
  - Runtime validation results summary:
  - Target edition support interpretation:
  - SA / AHB interpretation:
  - TCO note: {always frame as impact on Azure migration cost — e.g. "reduces target Azure licensing by X" or "enables AHB eligibility for Azure target"}
  - Downgrade safety status:
  - Remediation: {one or two concise customer-ready steps tied to the evidenced blocker or optimisation}
  - Reference: {authoritative Microsoft URL for this recommendation — for example Query Store / Backup Compression / end-of-support / Azure Hybrid Benefit}

- Opportunity 2:
  - Remediation:
  - Reference:

- Opportunity 3:
  - Remediation:
  - Reference:


## Enterprise downgrade audit

_**Tier 1 (≤10 instances):** use full inline detail as shown below._
_**Tier 2 (11–50 instances) and Tier 3 (51+ instances):** open with the summary counts block and compact GREEN listing, then show the structured audit tables for AMBER and RED records only. Full DMV results for GREEN instances move to Appendix B._
_**Tier 3 additional:** if AMBER/RED findings exceed 10, show top 10 ordered by severity (RED first) and state "Showing top 10 of {total} AMBER/RED findings — see Appendix B for complete list."_

### Tier 2/3 summary block (use for 11+ instances at the top of this section)

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

### Structured audit results

| machineName | instanceName | databaseName | featureName | executionStatus | errorMessage |
|-------------|--------------|--------------|-------------|-----------------|--------------|
|             |              |              |             |                 |              |

---

### Persisted feature findings (summary)

- Total databases audited:
- Databases with persisted features:
- Databases with no persisted features:
- Failed audits (if any):

---

### Runtime validation results (Arc Run Command)

| machineName | instanceName | checkName | result | executionStatus | errorMessage |
|-------------|--------------|-----------|--------|-----------------|--------------|
|             |              |           |        |                 |              |

- Required checks:
  - alwaysOnAvailabilityGroups
  - resourceGovernor
  - partitionedTables
  - onlineIndexOperations

---

### Target edition support interpretation (SQL Server 2022 Standard default)

- Interpret persisted feature findings against SQL Server 2022 Standard edition support:

- Feature(s) identified (if any):
  - Feature name: [feature]  
    - Supported in Standard: Yes / No / Verify required

- Interpretation notes:
  - If no features are returned:
    - state clearly that no persisted edition-restricted features were returned by the DMV
    - treat this as positive evidence, not final proof

---

### Runtime validation interpretation

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

### Downgrade readiness classification

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

### Downgrade confidence

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

### Final decision guidance

- Enterprise → Standard downgrade:
  - Recommended / Conditional / Not recommended

- Decision rationale:
  - Based on persisted feature audit
  - Runtime validation execution status and blockers
  - Remaining risks and unknowns

- Remediation note:
  - {Tie the remediation directly to the detected blocker(s) and chosen target edition (for example Standard edition) — for example remove unsupported features, retain Enterprise for blocked workloads, or change the Azure target before migration.}
- Reference:
  - {authoritative Microsoft Learn URL for the editions/features support matrix of the chosen target SQL Server version}


## SQL on Azure VM best practices alignment

_**Tier 1 (≤10 instances):** use full per-machine detail tables as shown in "Detailed findings" below._
_**Tier 2 (11–50 instances) and Tier 3 (51+ instances):** replace per-machine detail tables with the estate-wide heatmap table shown below. Keep the pre-migration remediation checklist for Critical and High findings only. Per-machine detail tables move to Appendix C._
_**Tier 3 additional:** show only the top 10 failing checks in the heatmap (ordered by machines-affected count descending); state "Showing top 10 of {total} failing checks — see Appendix C for complete list." Add a percentage column to the heatmap: `{N}/{total} ({pct}%)`._

- Execution depth (select one): [Tier 1 only (Resource Graph) | Tier 1+2 (Resource Graph + Log Analytics BPA) | Tier 1+2+3 (full scan with Arc Run Command fallback)]
- Machines scanned:
- Total checks executed:
- Pass: | Fail: | Warning: | Not assessed:

### Summary by category

| Category | Pass | Fail | Warning | Not assessed |
|----------|------|------|---------|--------------|
| Storage | | | | |
| Instance configuration | | | | |
| Security | | | | |
| HADR | | | | |
| Operations | | | | |

### Estate-wide findings heatmap (Tier 2/3 — use instead of per-machine detail tables below)

_Sort by severity descending (Critical → High → Medium → Low → Informational), then by machines-affected count descending within each severity band._
_Tier 3: add `({pct}%)` to the machines-affected column and truncate to top 10 with a "see Appendix C" note._
_Use the authoritative Microsoft URL mapped to each check ID. If a specific check has no dedicated page, use the SQL Server on Azure VM best-practices checklist._

| Check ID | Check name | Category | Severity | Machines affected | Reference |
|----------|------------|----------|----------|-------------------|-----------|
|          |            |          |          |                   |           |

_Per-machine BPA detail tables → Appendix C._

### Detailed findings

_Use this section for Tier 1 (≤10 instances). For Tier 2/3, move per-machine detail to Appendix C and use the heatmap above instead._

#### Critical and High severity findings

| Machine | Instance | Check ID | Check | Status | Severity | Current value | Expected value | Remediation | Reference |
|---------|----------|----------|-------|--------|----------|---------------|----------------|-------------|-----------|
|         |          |          |       |        |          |               |                |             |           |

#### Medium and Low severity findings

| Machine | Instance | Check ID | Check | Status | Severity | Current value | Expected value | Remediation | Reference |
|---------|----------|----------|-------|--------|----------|---------------|----------------|-------------|-----------|
|         |          |          |       |        |          |               |                |             |           |

#### Informational

| Machine | Instance | Check ID | Check | Status | Severity | Detail | Reference |
|---------|----------|----------|-------|--------|----------|--------|-----------|
|         |          |          |       |        |          |        |           |

### Pre-migration remediation checklist

1. {Machine} — {Critical/High remediation action}  
   Reference: {authoritative Microsoft URL for the cited check}
2. {Machine} — {next remediation action}  
   Reference: {authoritative Microsoft URL for the cited check}
3. {Machine} — {next remediation action}  
   Reference: {authoritative Microsoft URL for the cited check}


## Security posture — vulnerability exposure

_This section is present only when an Azure Migrate project was selected and Security Insights data was queried. Omit entirely if no Azure Migrate project is in scope._

**Data provenance:** _Security vulnerability data sourced from Azure Migrate Security Insights via the `machinesinventoryinsightsresources` Azure Resource Graph table (`inventoryInsights/vulnerabilities` resource types). This is a preview/undocumented surface — treat findings as indicative and validate via the Azure Migrate portal. Microsoft has not published a committed API schema for this data._

### Severity distribution summary

| Severity | Vulnerability records | Distinct CVEs | Max CVSS |
|----------|-----------------------|---------------|----------|
| Critical |                       |               |          |
| High     |                       |               |          |
| Medium   |                       |               |          |
| Low      |                       |               |          |
| **Total**|                       |               |          |

### Top CVEs by CVSS score

| CVE ID | CVSS | Severity | Age (days) | Affected software scope |
|--------|------|----------|------------|-------------------------|
|        |      |          |            |                         |

### Per-machine vulnerability summary (correlated Arc-enabled SQL machines)

| Machine | Total CVEs | Critical | High | Max CVSS | Migration priority impact |
|---------|------------|----------|------|----------|---------------------------|
|         |            |          |      |          |                           |

_Machines with Critical or High CVEs are flagged as elevated priority in Azure target recommendations._
_Machines that could not be correlated to discovered Security Insights records are listed in Data gaps / follow-up questions._

### Patch/remediation guidance by affected component family

| Component family | Recommended remediation | Reference |
|------------------|-------------------------|-----------|
| SQL Server engine / shared components | Apply the latest supported cumulative update or GDR for the affected major version before migration, or accelerate upgrade/migration if the version is out of support. | https://learn.microsoft.com/en-us/troubleshoot/sql/releases/sqlserver-builds |
| SQL Server out-of-support versions | Move to a supported SQL Server version or Azure target; if immediate migration is not possible, evaluate Extended Security Updates as a time-bound mitigation. | https://learn.microsoft.com/en-us/sql/sql-server/end-of-support/sql-server-end-of-support-overview |
| Extended Security Updates (ESU) | Use ESU only as an interim risk-reduction step while the migration or upgrade plan is executed. | https://learn.microsoft.com/en-us/sql/sql-server/end-of-support/sql-server-extended-security-updates |
| Other Microsoft component families (for example Windows Server or .NET) | Filter the Microsoft Security Update Guide by CVE and affected product family, then apply the relevant Microsoft patch guidance for that component. | https://msrc.microsoft.com/update-guide/ |


## Quick wins

- Quick win 1:
  - Why it matters:
  - Expected benefit:
  - Confidence:
  - Remediation:
  - Reference:

- Quick win 2:
  - Why it matters:
  - Expected benefit:
  - Confidence:
  - Remediation:
  - Reference:

- Quick win 3:
  - Why it matters:
  - Expected benefit:
  - Confidence:
  - Remediation:
  - Reference:


## Strategic moves

- Strategic move 1:
  - Why it matters:
  - Dependency / blocker:
  - Expected long-term benefit:
  - Confidence:
  - Remediation:
  - Reference:

- Strategic move 2:
  - Why it matters:
  - Dependency / blocker:
  - Expected long-term benefit:
  - Confidence:
  - Remediation:
  - Reference:

- Strategic move 3:
  - Why it matters:
  - Dependency / blocker:
  - Expected long-term benefit:
  - Confidence:
  - Remediation:
  - Reference:


## Azure target recommendations

_**Tier 1 (≤10 instances):** use full per-instance narrative as shown below._
_**Tier 2 (11–50 instances) and Tier 3 (51+ instances):** open with the action-grouped summary table, then follow with migration sequencing and SKU right-sizing at a group level. Per-instance TCO and licensing notes move to Appendix D._

### Action-grouped summary (Tier 2/3 — use instead of per-instance narrative below)

| Migration target  | Instances | Recommended action             | Confidence | Reference |
|-------------------|-----------|--------------------------------|------------|-----------|
| Azure SQL MI      |           | Ready — migrate in Wave 1      |            | https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/assessment-overview |
| Azure SQL MI      |           | Remediation needed before MI   |            | https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/assessment-overview |
| SQL on Azure VM   |           | Lift-and-shift candidates      |            | https://learn.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/performance-guidelines-best-practices-checklist |
| Further assess    |           | Additional data required       |            | https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/assessment-overview |

_Per-instance TCO notes and licensing position → Appendix D._

Include Azure Hybrid Benefit references in the licensing / TCO notes wherever AHB affects the recommendation: https://learn.microsoft.com/en-us/azure/cost-management-billing/azure-hybrid-benefits/

### Per-instance detail (Tier 1 — use for ≤10 instances)

- Candidate workloads for Azure SQL Managed Instance:
  - Readiness status:
  - Licensing / AHB note:
  - TCO note: {frame as Azure target cost impact, not on-prem savings}
  - If Not Ready, blocker details:
  - Why it is blocked:
  - Remediation:
  - Reference: https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/assessment-overview

- Candidate workloads for SQL Server on Azure Virtual Machines:
  - Licensing / AHB note:
  - TCO note: {frame as Azure target cost impact, not on-prem savings}
  - Remediation:
  - Reference: https://learn.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/performance-guidelines-best-practices-checklist

- Candidate workloads for Arc-enabled SQL Server PAYG as an interim or transition path:
  - Licensing / AHB note:
  - TCO note: {frame as transition step towards Azure migration, not standalone on-prem optimisation}
  - Remediation:
  - Reference: https://learn.microsoft.com/en-us/azure/cost-management-billing/azure-hybrid-benefits/

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


## Risks and blockers

- Risk 1:
- Risk 2:
- Risk 3:


## Data gaps / follow-up questions

_If Software Assurance status is `Not confirmed` or `Unknown`, add a follow-up asking the user to confirm active Software Assurance coverage and covered Standard / Enterprise core counts._

_If migration assessment shows populated `skuRecommendationResults` or `serverAssessments`, use that data even when `assessmentUploadTime = null`, and disclose that the freshness timestamp is unavailable or inconsistent._

_Only if `assessment.enabled = true`, `assessmentUploadTime = null`, and recommendation fields are not populated, report: "Assessment collected but ARM sync pending — check Azure portal Migration > Assessments blade for latest results, or trigger 'Run Assessment' to force sync." Do NOT report this as "no assessment data exists"._

- Missing field or evidence 1:
- Missing field or evidence 2:
- Missing field or evidence 3:


## Appendix

_This section is present for **Tier 2 (11–50 instances) and Tier 3 (51+ instances) only**. Omit entirely for Tier 1 (≤10 instances)._
_For HTML/PDF export (Tier 3), wrap each sub-section in `<details><summary>…</summary>` so content is collapsible. In markdown output, use headings only — all content must remain visible._

### Appendix A — Full machine inventory

| Machine name | OS | SQL version | Edition | vCores | Status | Assessment status |
|-------------|-----|-------------|---------|--------|--------|------------------|
|             |     |             |         |        |        |                  |

### Appendix B — Enterprise downgrade audit: GREEN instance details

_Full per-database DMV audit results for instances classified GREEN. AMBER/RED detail is in the main report body._

| machineName | instanceName | databaseName | featureName | executionStatus | errorMessage |
|-------------|--------------|--------------|-------------|-----------------|--------------|
|             |              |              |             |                 |              |

### Appendix C — BPA alignment: per-machine detail

_Full check-by-check BPA findings for each machine. Estate-wide heatmap is in the main report body._

| Machine | Instance | Check ID | Check | Status | Severity | Current value | Expected value | Remediation | Reference |
|---------|----------|----------|-------|--------|----------|---------------|----------------|-------------|-----------|
|         |          |          |       |        |          |               |                |             |           |

### Appendix D — Azure target recommendation details

_Per-instance TCO notes, licensing position, and AHB eligibility. Action-grouped summary is in the main report body._

| Instance | Machine | Target | Readiness | Licensing / AHB note | TCO note |
|----------|---------|--------|-----------|----------------------|----------|
|          |         |        |           |                      |          |
