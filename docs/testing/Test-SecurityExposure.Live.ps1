<#
.SYNOPSIS
    Network-gated live validation of the external CVE providers (MSRC + NVD).

.DESCRIPTION
    Exercises the real MSRC Security Update Guide and NVD CVE API 2.0 endpoints through
    Get-MsrcKbCveMapping and Get-NvdCveEnrichment, then verifies caching and offline replay.
    Requires outbound HTTPS to api.msrc.microsoft.com and services.nvd.nist.gov. This is NOT
    part of the deterministic unit suite (Test-SecurityExposure.ps1) because it needs network.

    Assessment-only: performs read-only GETs. No install/deploy surface is touched.

.EXAMPLE
    pwsh -NoProfile -File docs/testing/Test-SecurityExposure.Live.ps1
    pwsh -NoProfile -File docs/testing/Test-SecurityExposure.Live.ps1 -Kb 5031364 -PublishedDate 2023-10-10
#>
[CmdletBinding()]
param(
    [string]   $Kb = '5031364',                    # real 2023-10 Windows cumulative update
    [datetime] $PublishedDate = '2023-10-10',
    [string]   $CachePath = (Join-Path ([System.IO.Path]::GetTempPath()) 'arcsql-cve-cache')
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\..\.github\skills\arc-sql-estate-analysis\references\scripts\ArcSqlSecurityExposure.psm1'
Import-Module (Resolve-Path $modulePath).Path -Force

$script:Passed = 0; $script:Failed = 0
function Assert-True($name, $cond) {
    if ($cond) { $script:Passed++; Write-Host "  [PASS] $name" -ForegroundColor Green }
    else       { $script:Failed++; Write-Host "  [FAIL] $name" -ForegroundColor Red }
}

if (Test-Path -LiteralPath $CachePath) { Remove-Item -LiteralPath $CachePath -Recurse -Force }

Write-Host "== MSRC KB -> CVE (live) ==" -ForegroundColor Cyan
$mappings = Get-MsrcKbCveMapping -KbId $Kb -PublishedDate $PublishedDate -PatchName "Test $Kb" -CachePath $CachePath
$mapped = @($mappings | Where-Object { $_.mappingStatus -eq 'Mapped' })
Write-Host ("  KB{0} -> {1} mapped CVEs (doc {2})" -f $Kb, $mapped.Count, (Get-MsrcDocumentId $PublishedDate))
Assert-True 'MSRC returned at least one mapped CVE' ($mapped.Count -gt 0)
Assert-True 'MSRC mapping is High confidence'       ($mapped[0].confidence -eq 'High')
Assert-True 'MSRC match method = KbToCveMicrosoft'  ($mapped[0].matchMethod -eq 'KbToCveMicrosoft')
Assert-True 'MSRC source = MSRC'                     ($mapped[0].source -eq 'MSRC')
Assert-True 'MSRC sourceUrl populated'              ([bool]$mapped[0].sourceUrl)
Assert-True 'CVE id looks like a CVE'              ($mapped[0].cveId -match '^CVE-\d{4}-\d+$')
Assert-True 'High mapping is headline-eligible'    (Test-HeadlineEligible (Get-CveMappingConfidence $mapped[0].matchMethod))

Write-Host "`n== NVD enrichment (live) ==" -ForegroundColor Cyan
$cve = $mapped[0].cveId
$e = Get-NvdCveEnrichment -CveId $cve -CachePath $CachePath
Write-Host ("  {0}: CVSS {1} {2} ({3})" -f $e.cveId, $e.cvssBaseScore, $e.cvssBaseSeverity, $e.enrichmentStatus)
Assert-True 'NVD enrichment succeeded'   ($e.enrichmentStatus -in @('Ok','Cached'))
Assert-True 'NVD base score present'     ($null -ne $e.cvssBaseScore)
Assert-True 'NVD severity present'       ([bool]$e.cvssBaseSeverity)
Assert-True 'NVD vector present'         ([bool]$e.cvssVector)
Assert-True 'NVD source = NVD'           ($e.source -eq 'NVD')
if ($env:NVD_API_KEY) { Write-Host "  (used NVD_API_KEY for higher rate limit)" -ForegroundColor DarkGray }

Write-Host "`n== Cache + offline replay ==" -ForegroundColor Cyan
Assert-True 'MSRC response cached to disk' (Test-Path (Join-Path $CachePath ('msrc_' + (Get-MsrcDocumentId $PublishedDate) + '.json')))
Assert-True 'NVD response cached to disk'  (Test-Path (Join-Path $CachePath ('nvd_' + $cve + '.json')))
$eOffline = Get-NvdCveEnrichment -CveId $cve -CachePath $CachePath -Offline
Assert-True 'Offline NVD served from cache' ($eOffline.enrichmentStatus -eq 'Cached' -and $eOffline.cvssBaseScore -eq $e.cvssBaseScore)
$miss = Get-NvdCveEnrichment -CveId 'CVE-0000-00000' -CachePath $CachePath -Offline
Assert-True 'Offline cache miss reported, not thrown' ($miss.enrichmentStatus -eq 'OfflineCacheMiss')

Write-Host "`n== Graceful failure (bad month, no throw) ==" -ForegroundColor Cyan
$bad = Get-MsrcKbCveMapping -KbId $Kb -PublishedDate '1899-01-01' -CachePath $CachePath
Assert-True 'Missing MSRC doc -> Error status, no throw' (@($bad)[0].mappingStatus -in @('Error','Unmapped'))

Write-Host "`n========================================"
Write-Host ("Passed: {0}  Failed: {1}" -f $script:Passed, $script:Failed) -ForegroundColor ($(if ($script:Failed) { 'Red' } else { 'Green' }))
if ($script:Failed) { exit 1 }
