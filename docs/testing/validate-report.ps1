<#
.SYNOPSIS
    Validates the estate-report.html output against expected regression test assertions.

.DESCRIPTION
    Run this script after a full estate analysis to verify all features are working.
    Returns a pass/fail summary with details on any failures.

.PARAMETER ReportPath
    Path to the HTML report file. Defaults to estate-report.html in the repo root.

.PARAMETER MigrateEnrichmentEnabled
    Assert optional Azure Migrate enrichment content (Migrate project reference, utilisation
    metrics, SQL-assessment collection, dependency-CSV export prompt). Off by default because
    Azure Migrate is optional enrichment; the core path uses Azure Update Manager (security)
    and Azure Monitor VM Insights (dependency). Pass this switch only for a run that enabled
    Migrate enrichment (e.g. the regression-test-prompt run).

.EXAMPLE
    pwsh docs/testing/validate-report.ps1
    pwsh docs/testing/validate-report.ps1 -ReportPath "C:\path\to\estate-report.html"
    pwsh docs/testing/validate-report.ps1 -MigrateEnrichmentEnabled   # also assert optional Azure Migrate enrichment content
#>

param(
    [string]$ReportPath,
    [switch]$MigrateEnrichmentEnabled
)

if (-not $ReportPath) {
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if (-not $repoRoot) { $repoRoot = (Get-Location).Path }
    $ReportPath = Join-Path $repoRoot "estate-report.html"
}

$ErrorActionPreference = "Continue"

# --- Helpers ---
function Test-Assertion {
    param(
        [string]$Name,
        [string]$Category,
        [bool]$Passed,
        [string]$Detail = ""
    )
    [PSCustomObject]@{
        Category = $Category
        Name     = $Name
        Passed   = $Passed
        Detail   = $Detail
    }
}

function Test-ContentContains {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Name,
        [string]$Category,
        [switch]$Regex
    )
    if ($Regex) {
        $found = $Content -match $Pattern
    } else {
        $found = $Content.Contains($Pattern)
    }
    Test-Assertion -Name $Name -Category $Category -Passed $found -Detail $(if (-not $found) { "Pattern not found: $Pattern" } else { "" })
}

# --- Load report ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Arc SQL Estate Analysis - Report Validator" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if (-not (Test-Path $ReportPath)) {
    Write-Host "ERROR: Report not found at: $ReportPath" -ForegroundColor Red
    Write-Host "Run the full analysis first, then re-run this validator." -ForegroundColor Yellow
    exit 1
}

$reportContent = Get-Content $ReportPath -Raw
$reportLower = $reportContent.ToLower()
Write-Host "Report loaded: $ReportPath ($([math]::Round((Get-Item $ReportPath).Length / 1KB, 1)) KB)" -ForegroundColor Gray
Write-Host "Azure Migrate enrichment assertions: $(if ($MigrateEnrichmentEnabled) { 'ENABLED' } else { 'disabled (core path — AUM + VM Insights)' })`n" -ForegroundColor Gray

$results = @()

# --- Section 1: Required Sections ---
$requiredSections = @(
    "Part 1",
    "Part 2",
    "Executive Summary",
    "Estate at a glance",
    "Key risks",
    "Strategic migration",
    "Recommended Azure direction",
    "Estate summary",
    "Key optimisation opportunities",
    "Enterprise downgrade audit",
    "SQL on Azure VM best practices alignment",
    "Quick wins",
    "Strategic moves",
    "Azure target recommendations",
    "Risks and blockers",
    "Data gaps",
    "Security exposure"
)

foreach ($section in $requiredSections) {
    $results += Test-ContentContains -Content $reportContent -Pattern $section -Name "Section present: $section" -Category "Structure"
}

# --- Section 2: Estate Data ---
$results += Test-ContentContains -Content $reportContent -Pattern "ArcBox-SQL" -Name "Machine: ArcBox-SQL found" -Category "Estate Data"
$results += Test-ContentContains -Content $reportContent -Pattern "ARCBOX-SQL2016" -Name "Machine: ARCBOX-SQL2016 found" -Category "Estate Data" -Regex
$results += Test-ContentContains -Content $reportContent -Pattern "SSIS" -Name "Instance: SSIS_2022 referenced" -Category "Estate Data"
$results += Test-ContentContains -Content $reportContent -Pattern "Enterprise" -Name "Edition: Enterprise mentioned" -Category "Estate Data"

# --- Section 3: Assessment Data ---
# Migrate/assessment readiness is reported as one of several states. Live SQL assessment
# (assessedSqlInstances) commonly returns ConditionallySuitable (mapped to "Conditionally
# ready"), so do NOT hard-code "NotReady" — accept any recognised readiness classification.
$results += Test-ContentContains -Content $reportContent -Pattern '(?:NotReady|Not ready|Conditionally ready|ConditionallySuitable|Conditionally suitable|Ready|Suitable)' -Name "MI/VM readiness classification present" -Category "Assessment" -Regex
$results += Test-ContentContains -Content $reportContent -Pattern "Ready" -Name "MI/VM readiness: Ready state found" -Category "Assessment"
# Check for SKU recommendation or cost data
$results += Test-ContentContains -Content $reportContent -Pattern '(?:vCore|cost|SQL_\w+|General Purpose|Business Critical)' -Name "SKU recommendations present" -Category "Assessment" -Regex

# --- Section 4: Azure Migrate (optional enrichment — only asserted when enabled) ---
# Azure Migrate is optional enrichment (off by default). The canonical core path uses
# Azure Update Manager (security) + Azure Monitor VM Insights (dependency). Only enforce
# Migrate-specific content when the run explicitly enabled Migrate enrichment.
if ($MigrateEnrichmentEnabled) {
    $results += Test-ContentContains -Content $reportContent -Pattern "ArcBoxMigrate" -Name "Migrate project: ArcBoxMigrate referenced" -Category "Azure Migrate (optional)"
    $results += Test-ContentContains -Content $reportContent -Pattern '(?:utilisation|utilization|CPU.*%|memory.*%)' -Name "Utilisation data present" -Category "Azure Migrate (optional)" -Regex
    $results += Test-ContentContains -Content $reportContent -Pattern '(?:confidence|collection period)' -Name "Confidence/collection period disclosed" -Category "Azure Migrate (optional)" -Regex
    # Dependency prompt evidence
    $results += Test-ContentContains -Content $reportContent -Pattern '(?:dependency|dependencies)' -Name "Dependency analysis referenced" -Category "Azure Migrate (optional)" -Regex
}

# --- Section 4b: Application dependency (core path — VM Insights first) ---
# The report must address application dependency via the canonical VM Insights path, or
# clearly state it is unavailable with enablement guidance. Passes with or without Migrate.
$dependencyAddressed = $reportContent -match '(?i)(VM Insights|VMConnection|VMProcess|application dependency|dependency mapping|dependency (?:analysis|data) (?:not available|unavailable)|enabl\w+ Azure Monitor VM Insights)'
$results += Test-Assertion -Name "Dependency analysis addressed (VM Insights or documented gap)" -Category "Dependency (core)" -Passed $dependencyAddressed -Detail $(if (-not $dependencyAddressed) { "Report does not address application dependency via Azure Monitor VM Insights, nor documents its absence with enablement guidance." } else { "" })

# --- Section 5: Enterprise Downgrade ---
$results += Test-ContentContains -Content $reportContent -Pattern "GREEN" -Name "Downgrade: GREEN classification present" -Category "Downgrade Audit"
$results += Test-ContentContains -Content $reportContent -Pattern "RED" -Name "Downgrade: RED classification present (SSIS)" -Category "Downgrade Audit"
$results += Test-ContentContains -Content $reportContent -Pattern '(?:no persisted|no enterprise|persisted.*features)' -Name "DMV: No persisted features language" -Category "Downgrade Audit" -Regex
$results += Test-ContentContains -Content $reportContent -Pattern '(?:Resource Governor|resource.governor)' -Name "Runtime: Resource Governor checked" -Category "Downgrade Audit" -Regex
$results += Test-ContentContains -Content $reportContent -Pattern '(?:partition|partitioned)' -Name "Runtime: Partitioned tables checked" -Category "Downgrade Audit" -Regex

# --- Section 6: BPA Alignment ---
$results += Test-ContentContains -Content $reportContent -Pattern '(?:best.practice|BPA|alignment)' -Name "BPA: Best practices section populated" -Category "BPA Alignment" -Regex
$results += Test-ContentContains -Content $reportContent -Pattern '(?:la-arcbox-001|Log Analytics|SqlAssessment)' -Name "BPA: Workspace/table referenced" -Category "BPA Alignment" -Regex
$results += Test-ContentContains -Content $reportContent -Pattern '(?:Pass|Fail|Warning|NotAssessed)' -Name "BPA: Status values present" -Category "BPA Alignment" -Regex

# --- Section 7: Licensing ---
$results += Test-ContentContains -Content $reportContent -Pattern '(?:Software Assurance|SA)' -Name "Licensing: SA referenced" -Category "Licensing" -Regex
$results += Test-ContentContains -Content $reportContent -Pattern '(?:Hybrid Benefit|AHB)' -Name "Licensing: Azure Hybrid Benefit mentioned" -Category "Licensing" -Regex

# --- Section 8: Issue Regression Tests (PASSING — previously fixed) ---
# Issue #71: Agent must prompt for dependency CSV export (not silently skip)
# The Migrate dependency-CSV export prompt is a Migrate-enrichment fallback — only assert
# it when Migrate enrichment is enabled (the core path uses VM Insights, see Section 4b).
if ($MigrateEnrichmentEnabled) {
    $results += Test-ContentContains -Content $reportContent -Pattern '(?:export.+dependenc|dependency.+CSV|dependency.+export|Manage Dependencies)' -Name "#71: Dependency CSV export prompt evidence" -Category "Regressions (fixed)" -Regex
}

# Issue #72: BPA parsing must return actual check IDs (not vague "data available" language)
# Live SqlAssessment_CL check IDs are descriptive names (e.g. DbBackupMedia, UnusedIndex,
# StatSamplingRate) or trace-flag IDs (TF174) — NOT a STOR-/INST- prefix taxonomy. Accept
# the legacy prefixes, trace-flag IDs, or descriptive CamelCase rule IDs.
$results += Test-ContentContains -Content $reportContent -Pattern '(?:STOR-|INST-|SEC-|HADR-|OPS-|TF\d+|[A-Z][a-z]+(?:[A-Z][a-z]+)+)' -Name "#72: BPA check IDs present (parsed successfully)" -Category "Regressions (fixed)" -Regex

# Issue #72 (secondary): BPA should not contain failure/retry language indicating parsing broke.
# The '.*' spanning patterns are anchored to a short adjacency window so unrelated later text
# (e.g. "CVE enrichment unavailable" elsewhere in the flattened single-line HTML) cannot
# false-match against an earlier "BPA" token.
$bpaParseFailure = $reportContent -match '(?:could not parse|parsing failed|empty\s+\S{0,30}\s*BPA|BPA\s+\S{0,30}\s*unavailable)'
$results += Test-Assertion -Name "#72: No BPA parsing failure language" -Category "Regressions (fixed)" -Passed (-not $bpaParseFailure) -Detail $(if ($bpaParseFailure) { "Report contains BPA parsing failure indicators" } else { "" })

# --- Section 9: Security Exposure (core — shipped, must pass) ---
# The security-exposure section is a CORE, always-present section built from Azure Update
# Manager assessment data (no Azure Migrate required), with a source chain referencing
# Update Manager missing patches, MSRC KB→CVE mapping, and NVD enrichment. Shipped via
# PRs #106–#115 (issue #82); these are permanent regression checks and MUST pass.

# Issue #82: Security exposure section present
$securityPostureSection = $reportContent -match '(?i)(security exposure|patch assessment|vulnerability exposure|missing patch)'
$results += Test-Assertion -Name "#82: Security exposure section present" -Category "Security Exposure (core)" -Passed $securityPostureSection -Detail $(if (-not $securityPostureSection) { "Report does not contain a security-exposure / patch-assessment section. This is a core section built from Azure Update Manager assessment data." } else { "" })

# Issue #82 (secondary): section must reference the source chain (Update Manager / MSRC / NVD).
$securityProvenance = $reportContent -match '(?i)(patchassessmentresources|update manager|security update guide|\bMSRC\b|\bNVD\b)'
$results += Test-Assertion -Name "#82: Security exposure source chain referenced" -Category "Security Exposure (core)" -Passed $securityProvenance -Detail $(if (-not $securityProvenance) { "Report does not reference the Azure Update Manager + MSRC/NVD source chain for security exposure." } else { "" })

# Issue #82 (assessment-only): report must not claim/perform patch installation.
$patchInstallLanguage = $reportContent -match '(?i)(installed the .* patch|deployed .* update|scheduled .* update deployment|created .* maintenance configuration)'
$results += Test-Assertion -Name "#82: Assessment-only — no patch installation claimed" -Category "Security Exposure (core)" -Passed (-not $patchInstallLanguage) -Detail $(if ($patchInstallLanguage) { "Report contains patch-installation/deployment language. The security-exposure feature is assessment-only." } else { "" })

# --- Section 10: TDD — Open Issues (EXPECTED TO FAIL until fix lands) ---
# These assertions define the DESIRED state after each fix is merged.
# They SHOULD FAIL today. When they pass, the issue is resolved.

# Issue #71 (strict): The Migrate dependency-CSV prompt must result in user-response language.
# Migrate-enrichment fallback only — assert when Migrate enrichment is enabled.
if ($MigrateEnrichmentEnabled) {
    $depPromptFired = $reportContent -match '(?i)(user declined|no CSV provided|CSV not provided|user chose not to export|declined to export|not exported)'
    $results += Test-Assertion -Name "#71-TDD: Dependency prompt user-response recorded" -Category "TDD (open issues)" -Passed $depPromptFired -Detail $(if (-not $depPromptFired) { "No evidence the dependency CSV prompt fired and user response was recorded. Expected: 'user declined' / 'no CSV provided' language." } else { "" })
}

# Issue #72 (strict): BPA must produce BOTH machines' findings with severity ratings
# Current bug: parsing is fragile, sometimes only gets one machine or loses severity
# After fix: both ArcBox-SQL and ARCBOX-SQL2016 should have BPA check rows with severity
$bpaSection = ""
if ($reportContent -match '(?si)(best.practice|BPA alignment)(.+?)(Quick wins|Strategic moves)') {
    $bpaSection = $Matches[0]
}
$bpaBothMachines = ($bpaSection -match '(?i)ArcBox-SQL') -and ($bpaSection -match '(?i)ARCBOX.SQL2016')
$results += Test-Assertion -Name "#72-TDD: BPA findings for BOTH machines" -Category "TDD (open issues)" -Passed $bpaBothMachines -Detail $(if (-not $bpaBothMachines) { "BPA section does not contain findings for both ArcBox-SQL AND ARCBOX-SQL2016. Parsing may have failed for one machine." } else { "" })

# Issue #72 (strict): BPA severity must be paired with check IDs (structured output, not free text)
# After fix: each check should have a severity in the same table row. Accept legacy prefixes,
# trace-flag IDs, or descriptive CamelCase rule IDs, paired with a named severity or a numeric
# severity level (live SqlAssessment_CL uses numeric levels 1–3).
$bpaSeverityPaired = [regex]::Matches($bpaSection, '(?i)((?:STOR|INST|SEC|HADR|OPS)-\d+|TF\d+|[A-Z][a-z]+(?:[A-Z][a-z]+)+)\s*\|?\s*(Critical|High|Medium|Low|Informational|[1-3])\b')
$results += Test-Assertion -Name "#72-TDD: BPA check IDs paired with severity (5+ checks)" -Category "TDD (open issues)" -Passed ($bpaSeverityPaired.Count -ge 5) -Detail $(if ($bpaSeverityPaired.Count -lt 5) { "Only $($bpaSeverityPaired.Count) check-severity pairs found (need 5+). BPA parsing may not be producing structured output." } else { "" })

# --- Issue #73 / #104: Azure Migrate utilisation & SQL-assessment enrichment ---
# All Migrate-enrichment specific — only assert when Migrate enrichment is enabled.
if ($MigrateEnrichmentEnabled) {

# Issue #73 (strict): ARCBOX-SQL2016 must have actual utilisation METRICS (CPU/memory %)
# Current bug: report says "ARCBOX-SQL2016 not assessed" — machine missing from API response
# After fix: should show actual percentage values like "ARCBOX-SQL2016... XX% CPU... XX% memory"
$sql2016Metrics = $reportContent -match '(?i)ARCBOX.SQL2016.{0,200}?\d+\s*%'
$results += Test-Assertion -Name "#73-TDD: ARCBOX-SQL2016 has utilisation metrics (CPU/mem %)" -Category "TDD (open issues)" -Passed $sql2016Metrics -Detail $(if (-not $sql2016Metrics) { "ARCBOX-SQL2016 has no utilisation percentages. Expected: CPU% and memory% from Azure Migrate assessed machines." } else { "" })

# Issue #73: ARCBOX-SQL2016 must NOT contain "not assessed" language in Migrate section
$sql2016NotAssessed = $reportContent -match '(?i)ARCBOX.SQL2016.{0,100}?not assessed'
$results += Test-Assertion -Name "#73-TDD: ARCBOX-SQL2016 NOT marked 'not assessed'" -Category "TDD (open issues)" -Passed (-not $sql2016NotAssessed) -Detail $(if ($sql2016NotAssessed) { "ARCBOX-SQL2016 still marked 'not assessed' in Migrate section. Fix #73 should include this machine in assessed machines API call." } else { "" })

# --- Issue #104: SQL-specific assessment collection (sqlAssessments/{name}/assessedSqlInstances) ---
# These assertions validate that when a Finished Azure Migrate SQL assessment exists, the skill collects
# per-instance data from it and does NOT fall back to stale ARM-synced skuRecommendationResults or report
# a false utilisation data gap.

# #104-TDD: Report must reference the SQL assessment or assessedSqlInstances (evidence the primary path was taken)
$sqlAssessmentCollected = $reportContent -match '(?i)(sqlAssessment|allapplications-sql|assessedSqlInstances|SQL assessment.*Finished|Finished.*SQL assessment)'
$results += Test-Assertion -Name "#104-TDD: SQL assessment collection evidence present" -Category "TDD (open issues)" -Passed $sqlAssessmentCollected -Detail $(if (-not $sqlAssessmentCollected) { "No evidence the SQL assessment primary path (sqlAssessments/assessedSqlInstances) was attempted. Expected reference to SQL assessment or 'allapplications-sql' in report." } else { "" })

# #104-TDD: Report must NOT contain a utilisation data gap when assessedSqlInstances returned data
# A false utilisation gap is the primary symptom of falling back to stale ARM-synced data.
$utilisationGap = $reportContent -match '(?i)(utilisation.*not available|no utilisation.*data|utilization.*not available|no utilization.*data|utilisation.*gap|utilization.*gap)'
$results += Test-Assertion -Name "#104-TDD: No false utilisation data gap when SQL assessment available" -Category "TDD (open issues)" -Passed (-not $utilisationGap) -Detail $(if ($utilisationGap) { "Report contains a utilisation data gap despite a Finished SQL assessment being available. The skill should extract percentageCoresUtilization from assessedSqlInstances." } else { "" })

# #104-TDD: Report must use ConditionallySuitable/Conditionally ready language (not 'Not Ready') for MI readiness
# when the SQL assessment returns ConditionallySuitable for an instance (ArcBox-SQL was ConditionallySuitable for MI)
$conditionallySuitable = $reportContent -match '(?i)(Conditionally\s+ready|ConditionallySuitable|Conditionally\s+suitable)'
$results += Test-Assertion -Name "#104-TDD: ConditionallySuitable readiness mapped correctly (not 'Not Ready')" -Category "TDD (open issues)" -Passed $conditionallySuitable -Detail $(if (-not $conditionallySuitable) { "Report does not contain 'Conditionally ready' or 'ConditionallySuitable' language. Expected when SQL assessment returns ConditionallySuitable for MI target. Must NOT be reported as 'Not Ready'." } else { "" })

# #104-TDD: Report must correlate instances via linkages.workloadName (evidence: Arc machine name appears in Migrate section)
# workloadName gives the exact Arc machine name - it must appear in the utilisation/assessment context
$migrateSection = ""
if ($reportContent -match '(?si)(Azure Migrate|utilisation baseline|SQL assessment)(.+?)(Quick wins|Strategic moves|Data gaps)') {
    $migrateSection = $Matches[0]
}
# Guard: if section capture is empty, fall back to full report for correlation check
$searchScope = if ($migrateSection.Length -gt 10) { $migrateSection } else { $reportContent }
$arcMachineCorrelated = ($searchScope -match '(?i)ArcBox-SQL')
$results += Test-Assertion -Name "#104-TDD: Arc machine name correlated via linkages.workloadName in assessment context" -Category "TDD (open issues)" -Passed $arcMachineCorrelated -Detail $(if (-not $arcMachineCorrelated) { "ArcBox-SQL not found in Azure Migrate/utilisation context. Expected Arc machine name to appear via linkages.workloadName correlation from assessedSqlInstances." } else { "" })

} # end if ($MigrateEnrichmentEnabled) — Migrate utilisation & SQL-assessment enrichment

# --- Issue #78: Adaptive report formatting ---
# These assertions validate adaptive formatting behaviour. Because the regression test estate (ArcBox-SQL +
# ARCBOX-SQL2016) is a 2-instance estate (Tier 1), we assert that NO Tier 2/3 aggregated structures are
# present and that the report uses full inline detail. Add Tier 2/3 assertions here when a medium/large
# estate regression dataset is available.

# #78-TDD: Report must declare estate size and tier
$estateTierDeclared = $reportContent -match '(?i)(estate size|tier 1|tier 2|tier 3|aggregated report format|instances across.*machines)'
$results += Test-Assertion -Name "#78-TDD: Estate size/tier declaration present" -Category "TDD (adaptive formatting)" -Passed $estateTierDeclared -Detail $(if (-not $estateTierDeclared) { "Report does not contain an estate size or tier declaration. Expected: 'Estate size: N instances' or 'Tier 1/2/3' label in Estate summary." } else { "" })

# Tier detection: the Tier-1 enforcement assertions below only apply to a Tier 1 (<=10 instance)
# estate. A Tier 2/3 estate legitimately uses aggregated structures and an Appendix (see
# references/output-template.md), so only enforce "no appendix / no action-grouped table" when the
# report actually declares Tier 1 and does not declare Tier 2/3.
$isTier1 = ($reportContent -match '(?i)tier\s*1') -and -not ($reportContent -match '(?i)tier\s*[23]')

if ($isTier1) {
    # #78-TDD (Tier 1 enforcement): small estate MUST NOT produce an Appendix section
    $appendixPresent = $reportContent -match '(?i)<h[1-6][^>]*>Appendix</h[1-6]>|(?m)^#{1,6}\s+Appendix'
    $results += Test-Assertion -Name "#78-TDD: No Appendix for Tier 1 estate" -Category "TDD (adaptive formatting)" -Passed (-not $appendixPresent) -Detail $(if ($appendixPresent) { "Appendix section found in a Tier 1 (small estate) report. Appendix must only appear for Tier 2/3 (11+ instances)." } else { "" })

    # #78-TDD (Tier 1 enforcement): small estate MUST NOT use action-grouped migration target table
    # Match the specific pipe-delimited markdown table header OR the HTML table header for the action-grouped table.
    # This pattern is deliberately specific (pipe-delimited, matching the exact column sequence) to avoid
    # false positives from general narrative text that mentions "Migration target" or "Machines".
    $actionGroupedTable = $reportContent -match '(?i)(\|\s*Migration target\s*\|\s*Machines\s*\|\s*Instances\s*\||\<th[^>]*>\s*Migration target\s*<\/th>)'
    $results += Test-Assertion -Name "#78-TDD: No action-grouped inventory table for Tier 1 estate" -Category "TDD (adaptive formatting)" -Passed (-not $actionGroupedTable) -Detail $(if ($actionGroupedTable) { "Action-grouped migration target table found in a Tier 1 report. This table is only for Tier 2/3 (11+ instances)." } else { "" })
}

# --- Section 9: Branding/Formatting ---
$results += Test-ContentContains -Content $reportContent -Pattern "Microsoft" -Name "Branding: Microsoft wordmark" -Category "Formatting"
$results += Test-ContentContains -Content $reportContent -Pattern "Confidential" -Name "Branding: Confidential watermark" -Category "Formatting"
$results += Test-ContentContains -Content $reportContent -Pattern '(?:0078d4|005a9e)' -Name "Branding: Azure blue gradient colours" -Category "Formatting" -Regex
$results += Test-ContentContains -Content $reportContent -Pattern '<svg' -Name "Branding: Inline SVG present" -Category "Formatting"

# --- Results Summary ---
Write-Host "`n----------------------------------------" -ForegroundColor Cyan
Write-Host "  RESULTS SUMMARY" -ForegroundColor Cyan
Write-Host "----------------------------------------`n" -ForegroundColor Cyan

$categories = $results | Group-Object Category
foreach ($cat in $categories) {
    $passed = ($cat.Group | Where-Object Passed).Count
    $total = $cat.Group.Count
    $colour = if ($passed -eq $total) { "Green" } else { "Yellow" }
    Write-Host "  $($cat.Name): $passed/$total passed" -ForegroundColor $colour

    $failures = $cat.Group | Where-Object { -not $_.Passed }
    foreach ($fail in $failures) {
        Write-Host "    FAIL: $($fail.Name)" -ForegroundColor Red
        if ($fail.Detail) { Write-Host "          $($fail.Detail)" -ForegroundColor DarkRed }
    }
}

$totalPassed = ($results | Where-Object Passed).Count
$totalTests = $results.Count
$allPassed = $totalPassed -eq $totalTests

Write-Host "`n========================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "  ALL TESTS PASSED: $totalPassed/$totalTests" -ForegroundColor Green
} else {
    Write-Host "  TESTS FAILED: $totalPassed/$totalTests passed" -ForegroundColor Red
}
Write-Host "========================================`n" -ForegroundColor Cyan

# Exit with appropriate code for CI integration
if ($allPassed) { exit 0 } else { exit 1 }
