<#
.SYNOPSIS
    Validates the estate-report.html output against expected regression test assertions.

.DESCRIPTION
    Run this script after a full estate analysis to verify all features are working.
    Returns a pass/fail summary with details on any failures.

.PARAMETER ReportPath
    Path to the HTML report file. Defaults to estate-report.html in the repo root.

.EXAMPLE
    pwsh docs/testing/validate-report.ps1
    pwsh docs/testing/validate-report.ps1 -ReportPath "C:\path\to\estate-report.html"
#>

param(
    [string]$ReportPath
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
Write-Host "Report loaded: $ReportPath ($([math]::Round((Get-Item $ReportPath).Length / 1KB, 1)) KB)`n" -ForegroundColor Gray

$results = @()

# --- Section 1: Required Sections ---
$requiredSections = @(
    "Executive Summary",
    "Estate summary",
    "Key optimisation opportunities",
    "Enterprise downgrade audit",
    "SQL on Azure VM best practices alignment",
    "Quick wins",
    "Strategic moves",
    "Azure target recommendations",
    "Risks and blockers",
    "Data gaps"
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
$results += Test-ContentContains -Content $reportContent -Pattern "NotReady" -Name "MI readiness: NotReady state found" -Category "Assessment"
$results += Test-ContentContains -Content $reportContent -Pattern "Ready" -Name "MI/VM readiness: Ready state found" -Category "Assessment"
# Check for SKU recommendation or cost data
$results += Test-ContentContains -Content $reportContent -Pattern '(?:vCore|cost|SQL_\w+|General Purpose|Business Critical)' -Name "SKU recommendations present" -Category "Assessment" -Regex

# --- Section 4: Azure Migrate ---
$results += Test-ContentContains -Content $reportContent -Pattern "ArcBoxMigrate" -Name "Migrate project: ArcBoxMigrate referenced" -Category "Azure Migrate"
$results += Test-ContentContains -Content $reportContent -Pattern '(?:utilisation|utilization|CPU.*%|memory.*%)' -Name "Utilisation data present" -Category "Azure Migrate" -Regex
$results += Test-ContentContains -Content $reportContent -Pattern '(?:confidence|collection period)' -Name "Confidence/collection period disclosed" -Category "Azure Migrate" -Regex
# Dependency prompt evidence
$results += Test-ContentContains -Content $reportContent -Pattern '(?:dependency|dependencies)' -Name "Dependency analysis referenced" -Category "Azure Migrate" -Regex

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

# --- Section 8: Issue Regression Tests ---
# Issue #71: Agent must prompt for dependency CSV export (not silently skip)
# The report should contain explicit language about the dependency export prompt being offered
$results += Test-ContentContains -Content $reportContent -Pattern '(?:export.+dependenc|dependency.+CSV|dependency.+export|Manage Dependencies)' -Name "#71: Dependency CSV export prompt evidence" -Category "Regressions" -Regex

# Issue #72: BPA parsing must return actual check IDs (not vague "data available" language)
# If BPA parsed correctly, we should see specific check ID prefixes in the output
$results += Test-ContentContains -Content $reportContent -Pattern '(?:STOR-|INST-|SEC-|HADR-|OPS-)' -Name "#72: BPA check IDs present (parsed successfully)" -Category "Regressions" -Regex

# Issue #72 (secondary): BPA should not contain failure/retry language indicating parsing broke
$bpaParseFailure = $reportContent -match '(?:could not parse|parsing failed|empty.*BPA|BPA.*unavailable)'
$results += Test-Assertion -Name "#72: No BPA parsing failure language" -Category "Regressions" -Passed (-not $bpaParseFailure) -Detail $(if ($bpaParseFailure) { "Report contains BPA parsing failure indicators" } else { "" })

# Issue #73: ARCBOX-SQL2016 must appear in the Azure Migrate utilisation section
# Extract the section between "Azure Migrate" / "utilisation" and the next major heading
$migrateSection = ""
if ($reportContent -match '(?si)(Azure Migrate|[Uu]tilisation.*baseline)(.+?)(Risks and blockers|Data gaps|Enterprise downgrade)') {
    $migrateSection = $Matches[0]
}
$sql2016InMigrate = $migrateSection -match 'ARCBOX.SQL2016'
$results += Test-Assertion -Name "#73: ARCBOX-SQL2016 in Migrate utilisation data" -Category "Regressions" -Passed $sql2016InMigrate -Detail $(if (-not $sql2016InMigrate) { "ARCBOX-SQL2016 not found in Azure Migrate utilisation section — likely still missing from assessed machines API" } else { "" })

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
