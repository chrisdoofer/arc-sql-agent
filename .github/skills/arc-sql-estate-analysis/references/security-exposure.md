# Security exposure pipeline — Azure Update Manager + external CVE intelligence

This reference defines the **core security-exposure path** for the Arc SQL estate analyser.

The core path does **not** require Azure Migrate. It uses Azure Update Manager
assessment data (surfaced through Azure Resource Graph) as the source of truth for
missing patches, then enriches those patches with public vulnerability intelligence.

Azure Migrate Security Insights remains available only as an **optional enrichment
source** (`azureMigrate.enabled = false` by default). It is never required to produce
patch, CVE, vulnerability, or security-risk findings.

---

## 1. Core pipeline

```
Azure Arc-enabled servers
   → Azure Update Manager assessment-only data
   → Azure Resource Graph (patchassessmentresources)
   → missing software patch extraction
   → KB / update identifier extraction
   → Microsoft Security Update Guide (MSRC) KB→CVE mapping
   → NVD CVE enrichment (CVSS, severity, vector, dates, references)
   → dashboard-ready and report-ready security exposure outputs
```

Every stage is **read-only / assessment-only**. See §9 (Assessment-only guardrail).

---

## 2. Data sources and provenance

| Stage | Source | Trust label | Notes |
|-------|--------|-------------|-------|
| Missing patches, assessment status | Azure Resource Graph `patchassessmentresources` (Azure Update Manager) | **Confirmed fact** | Assessment data retained in Resource Graph for ~7 days; installation data (`patchinstallationresources`) for ~30 days. This feature reads assessment/missing-patch data only. |
| KB → CVE mapping | Microsoft Security Update Guide / MSRC (CVRF/CSAF API) | **Mapped (trusted)** | Primary mapping source for Microsoft KBs. `https://api.msrc.microsoft.com` — query by CVE, KB or monthly release. |
| CVE metadata | NVD CVE API 2.0 | **Enrichment** | CVSS score/severity/vector, published/modified dates, CWE, references, exploitability/impact scores. Used *after* candidate CVEs are known — never as the first mapping lookup. |
| Vulnerability records (optional) | Azure Migrate Security Insights (`machinesinventoryinsightsresources`) | **Optional enrichment** | Preview/undocumented surface. Off by default. Only additive; must not gate the section. |
| Risk narratives | Generated interpretation | **Inference (labelled)** | Clearly labelled as generated. Never fabricates CVEs. |

**Labelling rule:** output must distinguish *confirmed facts* (ARG / Update Manager) from
*mapped CVEs* (MSRC / trusted advisory), from *CVE metadata* (NVD), from *risk narratives*
(generated). Do not infer CVEs from a product name or version alone unless clearly marked
**Low** confidence and excluded from headline metrics by default.

---

## 3. Resource Graph query layer

Two record shapes are retrieved from `patchassessmentresources` (see
`command-templates.md` Templates 12–14 for the executable Azure CLI forms). Queries must
support **both Windows and Linux** Arc-enabled servers and must **not** assume every
record carries a KB number.

### 3a. Assessment summary records (per machine)

Records where `type !has "softwarepatches"`, e.g.
`microsoft.hybridcompute/machines/patchassessmentresults`. Collect:

- machine-level assessment status, assessment time / `lastModifiedDateTime`
- available patch count (total)
- `availablePatchCountByClassification.security`, `.critical`, and the remaining
  classification counts (`updateRollup`, `featurePack`, `servicePack`, `definition`,
  `updates`, `tools`, `other`)
- `osType`
- raw `properties`

### 3b. Individual missing software patch records

Records where `type has "softwarepatches"`, e.g.
`microsoft.hybridcompute/machines/patchassessmentresults/softwarepatches`. Collect:

- machine resource ID (prefix of `id` before `/patchAssessmentResults/`), machine name
- subscription ID, resource group, tenant ID
- assessment timestamp (`lastModifiedDateTime`)
- update title / `patchName`, update identifier (`name`)
- `kbId` if present (Windows), package `name`/`version` if present (Linux)
- `classifications`
- reboot behaviour if available (`rebootBehavior` / `rebootRequired`)
- severity hint if present
- raw update `properties` JSON

> **OS type note (verified live):** softwarepatches rows do **not** carry `osType` in their
> properties (0/249 rows in a live estate). Resolve `osType` by joining each patch to its
> machine's summary record on `machineResourceId` (the summary carries `osType`), or pass an
> `OsTypeLookup` to `ConvertFrom-AumSoftwarePatch`. When neither is available the parser
> infers OS: KB present → `Windows`, package version present → `Linux`, otherwise `Unknown`.

Windows records usually carry `kbId`; Linux records usually carry package `version` and no
KB. Never drop a record because it lacks a KB.

---

## 4. Data model

All objects below are produced locally from the query results above. `source` is set to
`AzureUpdateManagerResourceGraph` for the two assessment-derived models.

### PatchAssessmentSummary
`tenantId, subscriptionId, resourceGroup, machineResourceId, machineName, resourceType,
osType, assessmentTime, lastModifiedTime, assessmentStatus, availablePatchCount,
criticalPatchCount, securityPatchCount, otherPatchCount, source = AzureUpdateManagerResourceGraph`

### MissingPatch
`tenantId, subscriptionId, resourceGroup, machineResourceId, machineName, osType,
assessmentTime, patchName, patchId, kbIds[], classification, severityHint,
rebootRequiredHint, packageName, packageVersion, rawUpdateProperties,
source = AzureUpdateManagerResourceGraph`

### CveMapping
`mappingId, kbId, patchName, cveId, product, affectedComponent, source, sourceUrl,
matchMethod, confidence, mappingStatus, notes`

### CveEnrichment
`cveId, cvssVersion, cvssBaseScore, cvssBaseSeverity, cvssVector, cweIds[], publishedDate,
lastModifiedDate, description, references[], exploitabilityScore, impactScore,
source = NVD, enrichmentStatus`

### MachineSecurityExposure
`machineResourceId, machineName, osType, missingPatchCount, missingSecurityPatchCount,
missingCriticalPatchCount, mappedCveCount, criticalCveCount, highCveCount, maxCvssScore,
oldestMissingPatchAgeDays, unmappedSecurityPatchCount, evidenceConfidence, riskNarrative,
findings[]`

---

## 5. KB extraction / correlation layer

Extract KB identifiers from the missing-update `name`, `patchName` (title), `patchId`, and
raw `properties`. Requirements:

- Robust regex that matches `KB` followed by digits, case-insensitive:
  `(?i)KB\s*0*([0-9]{4,})` — a title may contain **multiple** KBs; capture all of them.
- If no KB is found, **keep the MissingPatch record** and set the CVE mapping status to
  `Unmapped` (not `Failed`). Absence of a KB must not fail the machine assessment.
- Linux packages have no KB — they are mapped (if at all) via advisory/package identity and
  otherwise remain `Unmapped` patch debt.

See `Get-KbIdFromText` in `scripts/ArcSqlSecurityExposure.psm1` for the reference
implementation and `Test-SecurityExposure.ps1` for its test cases.

---

## 6. External vulnerability intelligence providers

A provider abstraction wraps external lookups. Providers:

- **MsrcSecurityUpdateProvider** — primary Microsoft KB→CVE mapping via the Security Update
  Guide / MSRC CVRF API. The Microsoft patch world is KB/update-driven, so Microsoft's
  security update data is the correct primary source. Do **not** use NVD as the first
  lookup for mapping Microsoft KBs to CVEs.
- **NvdCveProvider** — enrichment of *already-identified* CVEs with CVSS/metadata.
- **OptionalLocalCacheProvider** — local cache / offline mode; reuse cached results when
  external calls are unavailable.

Provider requirements:

- API keys via environment variables or local config only — **never commit secrets**
  (`MSRC_API_KEY`, `NVD_API_KEY`).
- Request throttling, retry with backoff, local caching, and an offline mode that reuses
  cached data.
- External API failures are logged and represented in output status — they must **not**
  fail the whole estate assessment.
- Every mapping/enrichment result carries provenance: `source`, `sourceUrl` (where
  available), `matchMethod`, `confidence`, and `status`.

---

## 7. Confidence rules

| Confidence | Meaning |
|-----------|---------|
| **High** | Direct KB→CVE mapping from Microsoft security update data. |
| **Medium** | Direct CVE mapping from a trusted vendor advisory where the KB/update match is explicit. |
| **Low** | Title / product / version based matching only. |
| **None** | No mapping found (record remains visible as patch debt). |

**Headline rule:** executive summaries and dashboard headline metrics use only **High** and
**Medium** mappings by default. **Low** mappings may appear in detail/appendix output but
must not inflate headline risk numbers unless `cveEnrichment.allowLowConfidenceMatches = true`.

---

## 8. Risk scoring

Risk scoring identifies modernisation pressure **without overstating unsupported evidence**.
Inputs: missing critical patches, missing security patches, mapped critical CVEs, mapped high
CVEs, max CVSS, missing assessment data, stale assessment data, end-of-support OS,
end-of-support SQL, Defender posture (if already available), TDE posture (if already
available), unmapped security patch count.

**Patch evidence and CVE evidence are scored separately.** A machine with 20 missing security
patches but zero mapped CVEs is still risky (patch debt) but must **not** be described as
having confirmed CVE exposure. Confirmed CVE exposure requires a trusted mapping.

---

## 9. Assessment-only guardrail (enforced)

This feature is **assessment-only**. It must never:

- deploy or install patches;
- create maintenance configurations for patch installation;
- schedule update deployments;
- call `installPatches` or any equivalent update-installation API;
- write to `patchinstallationresources` / `maintenanceresources` for installation.

If this agent ever attempts to trigger patch installation, create a patch deployment, or
create a maintenance configuration for installation, it must **fail fast** with the exact
message:

```
Patch installation is disabled for this agent. Assessment-only mode is enforced.
```

`Assert-AssessmentOnly` in `scripts/ArcSqlSecurityExposure.psm1` implements this fail-fast
guard; any code path in this feature that could reach an install/deploy/maintenance-config
operation must route through it first. Pre-existing unrelated patch logic (if any) must be
preserved but must **not** be reachable from this feature.

---

## 10. Configuration

Settings that control this feature (defaults shown):

```jsonc
{
  "cveEnrichment": {
    "enabled": true,
    "providers": ["MsrcSecurityUpdateProvider", "NvdCveProvider", "OptionalLocalCacheProvider"],
    "cachePath": "./.cache/cve",
    "allowLowConfidenceMatches": false
  },
  "updateManager": {
    "assessmentOnly": true,
    "enablePeriodicAssessment": false,
    "excludePatchInstallation": true
  },
  "azureMigrate": {
    "enabled": false,
    "optionalOnly": true
  }
}
```

- The agent works even if Azure Migrate is not configured at all.
- `updateManager.assessmentOnly` and `updateManager.excludePatchInstallation` reinforce the
  §9 guardrail; they cannot be overridden to enable installation from this feature.
- `enablePeriodicAssessment` only refers to Update Manager *assessment* scheduling
  (read-only) — never installation.

---

## 11. Report sections (see `output-template.md`)

The security section is built around:

1. **Patch Assessment Coverage** — total Arc machines in scope, machines with recent
   assessment data, machines with no assessment data, last assessment timestamp per machine,
   unsupported/unknown assessment states.
2. **Missing Patch Exposure** — missing updates by machine, missing security updates by
   machine, missing critical updates by machine, top machines by patch debt.
3. **CVE Exposure from Missing Patches** — CVEs mapped from missing patches, critical CVEs,
   high CVEs, max CVSS by machine, unmapped security patches.
4. **Migration Pressure Findings** — customer-ready statements (see below).
5. **Evidence and Limitations** — data source, query timestamp, assessment timestamp,
   mapping source, confidence level, known limitations, unmapped records count, external API
   failures.

Migration Pressure Findings statement templates:

- "This server has missing security updates associated with known CVEs."
- "This server has patch assessment data but missing CVE mapping, indicating patch debt
  without vulnerability enrichment."
- "This server has no recent patch assessment, which is an operational visibility gap."
- "This server has missing critical or security updates and should be prioritised for
  remediation or migration planning."

---

## 12. Dashboard outputs and semantic model

Produce CSV or JSON outputs for downstream reporting (Power BI):

| Output | Grain | Key fields |
|--------|-------|-----------|
| `machine-patch-exposure.csv/json` | one row per machine | MachineSecurityExposure fields |
| `missing-patch-detail.csv/json` | one row per missing patch | MissingPatch fields |
| `patch-cve-mappings.csv/json` | one row per KB→CVE mapping | CveMapping fields |
| `cve-enrichment.csv/json` | one row per CVE | CveEnrichment fields |
| `executive-summary-metrics.csv/json` | one row (estate) | headline High/Medium metrics only |

Recommended semantic model:

- **Facts:** `FactMachinePatchAssessment`, `FactMissingPatch`, `FactPatchCveMapping`,
  `FactMachineCveExposure`
- **Dimensions:** `DimMachine`, `DimPatch`, `DimCve`, `DimSubscription`, `DimClassification`,
  `DimConfidence`
