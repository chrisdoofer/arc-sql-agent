<#
.SYNOPSIS
    Tests for the security-exposure pipeline helpers (Azure Update Manager + CVE intel).
.DESCRIPTION
    Self-contained test runner (no Pester dependency). Exercises the deterministic logic
    described in ../../.github/skills/arc-sql-estate-analysis/references/security-exposure.md:
    Resource Graph parsing, assessment-summary parsing, software-patch parsing, KB
    extraction (single / multiple / missing), unmapped handling, confidence classification,
    low-confidence suppression, headline eligibility, and the assessment-only guardrail.

    Run:  pwsh -File docs/testing/Test-SecurityExposure.ps1
    Exit code 0 = all passed, 1 = failures.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\..\.github\skills\arc-sql-estate-analysis\references\scripts\ArcSqlSecurityExposure.psm1'
Import-Module (Resolve-Path $modulePath).Path -Force

$script:pass = 0
$script:fail = 0

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:pass++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red
    }
}

function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    Assert-True $Name ($Expected -eq $Actual) "(expected '$Expected', got '$Actual')"
}

Write-Host "`n== KB extraction ==" -ForegroundColor Cyan

$single = Get-KbIdFromText '2023-10 Cumulative Update for Windows Server 2022 (KB5031364)'
Assert-Equal 'single KB extracted' 'KB5031364' ($single -join ',')

$multi = Get-KbIdFromText 'Rollup KB5031364 supersedes KB5030216 and kb 5029247'
Assert-Equal 'multiple KBs extracted (deduped, ordered)' 'KB5031364,KB5030216,KB5029247' ($multi -join ',')

$leadingZero = Get-KbIdFromText 'KB0891234'
Assert-Equal 'leading zeros stripped' 'KB891234' ($leadingZero -join ',')

$none = Get-KbIdFromText 'openssl 3.0.2-0ubuntu1.10 security update'
Assert-Equal 'no KB -> empty array (not error)' 0 $none.Count

$dup = Get-KbIdFromText 'KB5031364' 'patch KB5031364'
Assert-Equal 'duplicate KB across fields deduped' 'KB5031364' ($dup -join ',')

Write-Host "`n== Assessment summary parsing (Windows Arc) ==" -ForegroundColor Cyan

$summaryRecord = [pscustomobject]@{
    id             = '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.HybridCompute/machines/SQL01/patchAssessmentResults/latest'
    name           = 'latest'
    type           = 'microsoft.hybridcompute/machines/patchassessmentresults'
    subscriptionId = 's1'
    resourceGroup  = 'rg1'
    tenantId       = 't1'
    properties     = [pscustomobject]@{
        osType                            = 'Windows'
        lastModifiedDateTime              = '2026-07-20T02:00:00Z'
        assessmentState                   = 'Succeeded'
        availablePatchCountByClassification = [pscustomobject]@{ security = 5; critical = 2; updateRollup = 1; other = 0 }
    }
}
$summary = ConvertFrom-AumSummary $summaryRecord
Assert-Equal 'summary osType' 'Windows' $summary.osType
Assert-Equal 'summary securityPatchCount' 5 $summary.securityPatchCount
Assert-Equal 'summary criticalPatchCount' 2 $summary.criticalPatchCount
Assert-Equal 'summary availablePatchCount (sum of classifications)' 8 $summary.availablePatchCount
Assert-Equal 'summary source label' 'AzureUpdateManagerResourceGraph' $summary.source
Assert-Equal 'summary machineName from id path (not "latest")' 'SQL01' $summary.machineName
Assert-Equal 'summary machineResourceId trims patchAssessmentResults' '/subscriptions/s1/resourceGroups/rg1/providers/Microsoft.HybridCompute/machines/SQL01' $summary.machineResourceId

Write-Host "`n== Assessment summary parsing (properties as JSON string) ==" -ForegroundColor Cyan
$summaryRecord2 = [pscustomobject]@{
    id = '/subscriptions/s1/x/patchAssessmentResults/latest'; name='SQL02'; type='t'; subscriptionId='s1'; resourceGroup='rg1'; tenantId='t1'
    properties = '{"osType":"Linux","lastModifiedDateTime":"2026-07-19T00:00:00Z","assessmentState":"Succeeded","availablePatchCountByClassification":{"security":3,"other":4}}'
}
$summary2 = ConvertFrom-AumSummary $summaryRecord2
Assert-Equal 'JSON-string properties parsed (osType)' 'Linux' $summary2.osType
Assert-Equal 'JSON-string properties parsed (security)' 3 $summary2.securityPatchCount

Write-Host "`n== Software patch parsing (Windows, with KB) ==" -ForegroundColor Cyan
$winPatch = [pscustomobject]@{
    id = '/subscriptions/s1/resourceGroups/rg1/providers/microsoft.hybridcompute/machines/SQL01/patchAssessmentResults/latest/softwarePatches/kb5031364'
    name = 'kb5031364'; type = 'microsoft.hybridcompute/machines/patchassessmentresults/softwarepatches'
    subscriptionId='s1'; resourceGroup='rg1'; tenantId='t1'
    properties = [pscustomobject]@{ patchName='2023-10 CU (KB5031364)'; kbId='KB5031364'; classifications='Security'; osType='Windows'; lastModifiedDateTime='2026-07-20T02:00:00Z'; rebootBehavior='CanRequestReboot' }
}
$mp = ConvertFrom-AumSoftwarePatch $winPatch
Assert-Equal 'windows patch KB extracted' 'KB5031364' ($mp.kbIds -join ',')
Assert-Equal 'windows patch classification' 'Security' $mp.classification
Assert-Equal 'windows patch reboot hint' 'CanRequestReboot' $mp.rebootRequiredHint
Assert-Equal 'windows patch source' 'AzureUpdateManagerResourceGraph' $mp.source

Write-Host "`n== Software patch parsing (Linux, no KB -> Unmapped, not dropped) ==" -ForegroundColor Cyan
$linuxPatch = [pscustomobject]@{
    id = '/subscriptions/s1/resourceGroups/rg1/providers/microsoft.hybridcompute/machines/PG01/patchAssessmentResults/latest/softwarePatches/openssl'
    name = 'openssl'; type = 'microsoft.hybridcompute/machines/patchassessmentresults/softwarepatches'
    subscriptionId='s1'; resourceGroup='rg1'; tenantId='t1'
    properties = [pscustomobject]@{ patchName='openssl'; version='3.0.2-0ubuntu1.10'; classifications='Security'; osType='Linux'; lastModifiedDateTime='2026-07-19T00:00:00Z' }
}
$lp = ConvertFrom-AumSoftwarePatch $linuxPatch
Assert-Equal 'linux patch has no KB' 0 $lp.kbIds.Count
Assert-Equal 'linux patch retained (packageVersion present)' '3.0.2-0ubuntu1.10' $lp.packageVersion
Assert-True  'linux security patch is unmapped candidate but retained' (($lp.kbIds.Count -eq 0) -and ($lp.classification -eq 'Security'))

Write-Host "`n== osType derivation (softwarepatches rows carry no osType) ==" -ForegroundColor Cyan
# Real AUM softwarepatches rows do NOT include osType in properties; it must be resolved
# from the summary pass (OsTypeLookup) or inferred.
$winNoOs = [pscustomobject]@{
    id = '/subscriptions/s1/resourceGroups/rg1/providers/microsoft.hybridcompute/machines/SQL01/patchAssessmentResults/latest/softwarePatches/1'
    name = '1'; type = 'microsoft.hybridcompute/machines/patchassessmentresults/softwarepatches'
    subscriptionId='s1'; resourceGroup='rg1'; tenantId='t1'
    properties = [pscustomobject]@{ patchName='Security Update for SQL Server 2022 (KB5102334)'; classifications='Security'; lastModifiedDateTime='2026-07-20T02:00:00Z' }
}
$lookup = @{ '/subscriptions/s1/resourceGroups/rg1/providers/microsoft.hybridcompute/machines/SQL01' = 'Windows' }
$mpLookup = ConvertFrom-AumSoftwarePatch $winNoOs -OsTypeLookup $lookup
Assert-Equal 'osType resolved from summary lookup' 'Windows' $mpLookup.osType
Assert-Equal 'KB still extracted without kbId prop' 'KB5102334' ($mpLookup.kbIds -join ',')

# No lookup, KB present -> infer Windows.
$mpInferWin = ConvertFrom-AumSoftwarePatch $winNoOs
Assert-Equal 'osType inferred Windows when KB present' 'Windows' $mpInferWin.osType

# No lookup, no KB, package version present -> infer Linux.
$linNoOs = [pscustomobject]@{
    id = '/subscriptions/s1/resourceGroups/rg1/providers/microsoft.hybridcompute/machines/PG01/patchAssessmentResults/latest/softwarePatches/apport'
    name = 'apport'; type = 'microsoft.hybridcompute/machines/patchassessmentresults/softwarepatches'
    subscriptionId='s1'; resourceGroup='rg1'; tenantId='t1'
    properties = [pscustomobject]@{ patchName='apport'; version='2.20.11'; classifications='Other'; lastModifiedDateTime='2026-07-19T00:00:00Z' }
}
$mpInferLin = ConvertFrom-AumSoftwarePatch $linNoOs
Assert-Equal 'osType inferred Linux when only version present' 'Linux' $mpInferLin.osType

# No lookup, no KB, no version -> Unknown (not blank).
$unkNoOs = [pscustomobject]@{
    id = '/subscriptions/s1/resourceGroups/rg1/providers/microsoft.hybridcompute/machines/X01/patchAssessmentResults/latest/softwarePatches/z'
    name = 'z'; type = 'microsoft.hybridcompute/machines/patchassessmentresults/softwarepatches'
    subscriptionId='s1'; resourceGroup='rg1'; tenantId='t1'
    properties = [pscustomobject]@{ patchName='mystery'; classifications='Other'; lastModifiedDateTime='2026-07-19T00:00:00Z' }
}
$mpUnk = ConvertFrom-AumSoftwarePatch $unkNoOs
Assert-Equal 'osType Unknown when undeterminable' 'Unknown' $mpUnk.osType

Write-Host "`n== Confidence classification ==" -ForegroundColor Cyan
Assert-Equal 'direct MSRC KB->CVE = High' 'High'   (Get-CveMappingConfidence 'KbToCveMicrosoft')
Assert-Equal 'vendor advisory explicit KB = Medium' 'Medium' (Get-CveMappingConfidence 'VendorAdvisoryExplicitKb')
Assert-Equal 'title/product/version = Low' 'Low'    (Get-CveMappingConfidence 'TitleProductVersion')
Assert-Equal 'no mapping = None' 'None'             (Get-CveMappingConfidence '')
Assert-Equal 'unknown method = None' 'None'         (Get-CveMappingConfidence 'SomethingElse')

Write-Host "`n== Headline eligibility (low-confidence suppression) ==" -ForegroundColor Cyan
Assert-True  'High eligible for headline'   (Test-HeadlineEligible 'High')
Assert-True  'Medium eligible for headline' (Test-HeadlineEligible 'Medium')
Assert-True  'Low suppressed by default'    (-not (Test-HeadlineEligible 'Low'))
Assert-True  'Low allowed when explicitly enabled' (Test-HeadlineEligible 'Low' -AllowLowConfidenceMatches)
Assert-True  'None never eligible'          (-not (Test-HeadlineEligible 'None' -AllowLowConfidenceMatches))

Write-Host "`n== Assessment-only guardrail ==" -ForegroundColor Cyan
$expectedMsg = 'Patch installation is disabled for this agent. Assessment-only mode is enforced.'

# Read-only assessment operations must pass through.
$assessOk = $true
try { Assert-AssessmentOnly 'patchassessmentresources'; Assert-AssessmentOnly 'GET machines/patchAssessmentResults/latest' } catch { $assessOk = $false }
Assert-True 'assessment/read operations pass through' $assessOk

foreach ($op in @('installPatches', 'Microsoft.Maintenance/maintenanceConfigurations', 'patchInstallationResources', 'scheduleUpdateDeployment', 'applyUpdates')) {
    $threw = $false; $msg = ''
    try { Assert-AssessmentOnly $op } catch { $threw = $true; $msg = $_.Exception.Message }
    Assert-True "blocked: $op throws" $threw
    Assert-Equal "blocked: $op exact message" $expectedMsg $msg
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ("Passed: {0}  Failed: {1}" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
