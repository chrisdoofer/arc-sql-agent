> ## Authoring principle — single source of truth (read before writing any section)
>
> This report has two deliberate layers: **Part 1** (executive) and **Part 2** (technical). Restating a Part 2 fact at executive level in Part 1 is expected. **Repeating the same fact multiple times _within_ Part 2 is not** — it is the primary cause of report bloat.
>
> **Rule:** every finding has exactly one **authoritative home section** where it is stated in full (evidence, numbers, confidence, remediation, reference). Every other mention must be either a **one-clause headline** or an explicit **cross-reference** ("see §Section name") — never a re-explanation.
>
> | Finding | Authoritative home (state in full once) | Everywhere else |
> |---|---|---|
> | Enterprise→Standard downgrade (per-instance GREEN/AMBER/RED, DMV + runtime detail) | **Enterprise downgrade audit** | Exec Summary & Strategic opps: headline counts only; Key optimisation: one line + confidence |
> | BPA config fixes (max memory, Query Store, auto-close/shrink, backup compression, storage layout, Defender) | **SQL on Azure VM BPA alignment** + its remediation checklist | Quick wins: reference the checklist, do **not** re-list; Risks: do not re-list |
> | Vulnerabilities / CVEs / patch debt | **Security exposure — patch assessment and CVE mapping** | Exec/At a glance/Key risks: one-line headline; Azure target & Risks: single pointer |
> | Azure target readiness, SKU, cost | **Azure target recommendations** (+ Appendix D) | Recommended direction (Part 1): exec-level; Estate summary groupings: light readiness table only |
> | Licensing / SA / AHB cores | **Licensing position** (in Estate summary) | Exec & Strategic: one-line; Key optimisation: AHB as a single opportunity |
> | Sizing confidence & assessment coverage caveats | **Data gaps / follow-up questions** | Others: brief "(see Data gaps)" only |
>
> **Quick wins** and **Strategic moves** are **classification views**, not new content: each entry is a single line that points to the item's home section (effort + confidence + pointer). Do not reproduce the "Why it matters / Expected benefit / Remediation / Reference" detail that already lives in the home section.
>
> Before finalising, scan for any fact that appears in full in more than one Part 2 section and collapse the extra copies to a headline or cross-reference.

# Part 1 — Executive Briefing

_Concise, business-framed narrative. No per-database or per-instance raw tables. Every point is framed through reliability, cost, security, and end-of-support risk lenses — and connects to Azure migration or modernisation as the outcome._

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
- Security posture headline: {N} machines with missing security/critical updates | {N} High/Medium-confidence CVEs mapped (Max CVSS: {score}) (or: patch assessment data unavailable — Azure Update Manager not enabled)
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

_Full depth for action. Contains all existing sections with per-instance and per-database detail, execution guidance, and appendices._

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

- Application dependency summary (from Azure Monitor VM Insights or optional Azure Migrate data, if available):
  - Dependency analysis type: VM Insights (Log Analytics) / Dependency Map API / Agentless (portal CSV) / Not available
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


## Security exposure — patch assessment and CVE mapping

_Core section — always present. Built from Azure Update Manager assessment data (surfaced via Azure Resource Graph `patchassessmentresources`), Microsoft Security Update Guide (MSRC) KB→CVE mapping, and NVD CVE enrichment. Azure Migrate is **not** required (optional enrichment only). When Azure Update Manager assessment data is unavailable for the scope, still render this section and report the gap under Patch Assessment Coverage._

**Evidence labelling:** _Confirmed facts_ come from Azure Resource Graph / Azure Update Manager. _Mapped CVEs_ come from MSRC or a trusted advisory. _CVE metadata_ (CVSS etc.) comes from NVD. _Risk narratives_ are generated interpretations. Headline counts use **High + Medium** confidence mappings only unless low-confidence matches are explicitly enabled.

### Patch Assessment Coverage

| Metric | Value |
|--------|-------|
| Total Arc machines in scope | |
| Machines with recent assessment data | |
| Machines with no assessment data | |
| Unsupported / unknown assessment states | |

| Machine | OS | Last assessment timestamp | Assessment state |
|---------|----|---------------------------|------------------|
|         |    |                           |                  |

### Missing Patch Exposure

| Machine | Missing updates (total) | Missing security | Missing critical |
|---------|-------------------------|------------------|------------------|
|         |                         |                  |                  |

_Top machines by patch debt (missing security + critical):_

| Rank | Machine | Missing security + critical |
|------|---------|-----------------------------|
| 1    |         |                             |

### CVE Exposure from Missing Patches

_Headline metrics below use High + Medium confidence mappings only. Low-confidence (title/product/version) matches, if any, are listed in the Appendix and excluded from these counts by default._

| Metric | Value |
|--------|-------|
| CVEs mapped from missing patches (High + Medium) | |
| Critical CVEs | |
| High CVEs | |
| Unmapped security patches (patch debt, no CVE mapping) | |

| Machine | Mapped CVEs | Critical | High | Max CVSS | Unmapped security patches |
|---------|-------------|----------|------|----------|---------------------------|
|         |             |          |      |          |                           |

### Migration Pressure Findings

_Customer-ready statements per machine (labelled as generated interpretation of the evidence above):_

| Machine | Finding |
|---------|---------|
| | This server has missing security updates associated with known CVEs. |
| | This server has patch assessment data but missing CVE mapping, indicating patch debt without vulnerability enrichment. |
| | This server has no recent patch assessment, which is an operational visibility gap. |
| | This server has missing critical or security updates and should be prioritised for remediation or migration planning. |

### Evidence and Limitations

| Item | Detail |
|------|--------|
| Data source | Azure Update Manager assessment data via Azure Resource Graph `patchassessmentresources` (assessment-only) |
| Query timestamp | {when the ARG query was run} |
| Assessment timestamp | {machine assessment `lastModifiedDateTime` range} |
| Mapping source | Microsoft Security Update Guide / MSRC (primary); NVD (CVE metadata enrichment) |
| Confidence level | Headline uses High + Medium; Low retained in Appendix only |
| Unmapped records | {count of missing patches with no CVE mapping — kept visible as patch debt} |
| External API failures | {MSRC / NVD failures, if any — did not fail the estate assessment} |
| Known limitations | Not every missing update maps cleanly to a CVE; Linux package updates often have no KB; assessment data is retained in Resource Graph for ~7 days. |

_Machines with mapped Critical/High CVEs (High/Medium confidence) or with missing critical/security patches are flagged as elevated priority in Azure target recommendations — CVE exposure and patch debt are cited separately._


## Quick wins

_Low-effort actions already detailed in their home sections. One line each — classify by effort/confidence and point to the home section. Do **not** restate the full finding here._

- {action} — home: {§Key optimisation opportunities / §BPA alignment / §Enterprise downgrade audit}. Effort: Low. Confidence: {level}.
- {action} — home: {section}. Effort: Low. Confidence: {level}.
- {action} — home: {section}. Effort: Low. Confidence: {level}.


## Strategic moves

_Higher-effort moves already detailed in their home sections. One line each — point to the home section and note the key dependency/blocker. Do **not** restate the full finding here._

- {move} — home: {§Azure target recommendations / §Enterprise downgrade audit / §Licensing position}. Effort: High. Dependency: {blocker}. Confidence: {level}.
- {move} — home: {section}. Effort: High. Dependency: {blocker}. Confidence: {level}.
- {move} — home: {section}. Effort: High. Dependency: {blocker}. Confidence: {level}.


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

- Migration sequencing recommendation (when application dependency data is available):
  - Migration wave 1: {instances with no inbound SQL dependencies — safe to migrate first}
  - Migration wave 2: {instances dependent on wave 1 targets}
  - Cross-instance dependencies: {SQL-to-SQL dependencies that require coordinated migration}
  - If dependency data not available: "Application dependency mapping not available — recommend enabling Azure Monitor VM Insights (Map) at least 24 hours before the engagement, or providing optional Azure Migrate dependency data, to inform migration sequencing"


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

### Unattended execution log (include only when Unattended mode performed Phase 5 write operations)

_Required for sanctioned Unattended mode runs because scripts are not shown before execution. List every standing-authorized write action performed after the fact._

| Machine | Operation | Slot name | Script pattern | Result |
|---------|-----------|-----------|----------------|--------|
|         |           |           |                |        |


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
