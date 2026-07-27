<#
.SYNOPSIS
    Deterministic helpers for the Arc SQL estate analyser security-exposure pipeline
    (Azure Update Manager + external CVE intelligence).

.DESCRIPTION
    Assessment-only. This module NEVER installs patches, creates maintenance
    configurations, or schedules update deployments. Any attempt to reach an
    install/deploy/maintenance-config operation must route through Assert-AssessmentOnly,
    which fails fast.

    Functions:
      - Get-KbIdFromText          Extract KB identifiers (supports multiple KBs, no-KB case)
      - ConvertFrom-AumSummary    Parse a patchassessmentresources summary ARG record
      - ConvertFrom-AumSoftwarePatch  Parse a softwarepatches ARG record into a MissingPatch
      - Get-CveMappingConfidence  Classify mapping confidence (High/Medium/Low/None)
      - Test-HeadlineEligible     Whether a mapping may contribute to headline metrics
      - Assert-AssessmentOnly     Fail-fast guardrail blocking patch installation paths
      - Get-MsrcDocumentId        Resolve the MSRC monthly CVRF document id from a date
      - Invoke-VulnApiRequest     Read-only HTTP GET with cache/offline/retry/backoff
      - Get-MsrcKbCveMapping      MSRC KB->CVE mapping (primary, High confidence)
      - Get-NvdCveEnrichment      NVD CVE metadata enrichment (CVSS/CWE/refs)

    See ../security-exposure.md for the full design.
#>

Set-StrictMode -Version Latest

$script:AssessmentOnlyError = 'Patch installation is disabled for this agent. Assessment-only mode is enforced.'

# Operations that this assessment-only feature must never perform.
$script:BlockedOperations = @(
    'installpatches',
    'installpatch',
    'patchinstallation',
    'patchinstallationresources',
    'createmaintenanceconfiguration',
    'maintenanceconfiguration',
    'maintenanceconfigurations',
    'scheduleupdatedeployment',
    'updatedeployment',
    'deploypatch',
    'applyupdates'
)

function Get-KbIdFromText {
    <#
    .SYNOPSIS
        Extract distinct KB identifiers from one or more text fields.
    .DESCRIPTION
        Case-insensitive; supports "KB1234567", "kb 1234567", and multiple KBs in one
        string. Leading zeros are stripped. Returns an empty array when no KB is present
        (a valid, non-failing outcome for Linux packages and KB-less Windows updates).
    .OUTPUTS
        [string[]] normalised KB identifiers, e.g. 'KB5031364'.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Text
    )

    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $Text) {
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        foreach ($m in [regex]::Matches($t, '(?i)KB\s*0*([0-9]{4,})')) {
            $kb = 'KB' + $m.Groups[1].Value
            if (-not $found.Contains($kb)) { $found.Add($kb) }
        }
    }
    return , $found.ToArray()
}

function ConvertFrom-AumSummary {
    <#
    .SYNOPSIS
        Parse a patchassessmentresources summary record (type !has "softwarepatches")
        into a PatchAssessmentSummary hashtable.
    #>
    param([Parameter(Mandatory)] $Record)

    $props = $Record.properties
    if ($props -is [string]) { $props = $props | ConvertFrom-Json }
    $byClass = if ($props -and $props.PSObject.Properties.Name -contains 'availablePatchCountByClassification') {
        $props.availablePatchCountByClassification
    } else { $null }

    $machineResourceId = ($Record.id -split '/patchAssessmentResults/')[0]
    $machineName = ($machineResourceId -split '/')[-1]

    $get = {
        param($obj, $name)
        if ($obj -and $obj.PSObject.Properties.Name -contains $name) { [int]$obj.$name } else { 0 }
    }
    $critical = & $get $byClass 'critical'
    $security = & $get $byClass 'security'
    $available = if ($byClass) {
        ($byClass.PSObject.Properties | ForEach-Object { $_.Value -as [int] } | Measure-Object -Sum).Sum
    } else { 0 }
    if ($null -eq $available) { $available = 0 }

    return [ordered]@{
        machineResourceId   = $machineResourceId
        machineName         = $machineName
        resourceType        = $Record.type
        subscriptionId      = $Record.subscriptionId
        resourceGroup       = $Record.resourceGroup
        tenantId            = $Record.tenantId
        osType              = if ($props) { [string]$props.osType } else { '' }
        assessmentTime      = if ($props) { [string]$props.lastModifiedDateTime } else { '' }
        lastModifiedTime    = if ($props) { [string]$props.lastModifiedDateTime } else { '' }
        assessmentStatus    = if ($props) {
            if ($props.PSObject.Properties.Name -contains 'status' -and $props.status) { [string]$props.status }
            elseif ($props.configurationStatus -and $props.configurationStatus.assessmentModeConfiguration -and $props.configurationStatus.assessmentModeConfiguration.status) { [string]$props.configurationStatus.assessmentModeConfiguration.status }
            elseif ($props.PSObject.Properties.Name -contains 'assessmentState' -and $props.assessmentState) { [string]$props.assessmentState }
            else { 'Unknown' }
        } else { 'Unknown' }
        availablePatchCount = [int]$available
        criticalPatchCount  = [int]$critical
        securityPatchCount  = [int]$security
        otherPatchCount     = [int]($available - $critical - $security)
        source              = 'AzureUpdateManagerResourceGraph'
    }
}

function ConvertFrom-AumSoftwarePatch {
    <#
    .SYNOPSIS
        Parse a softwarepatches record (type has "softwarepatches") into a MissingPatch
        hashtable. Never drops KB-less records.
    .PARAMETER OsTypeLookup
        Optional hashtable keyed by machineResourceId (case-insensitive) mapping to osType,
        built from the summary pass (ConvertFrom-AumSummary). softwarepatches records do NOT
        carry osType, so it is resolved here from the summary; if absent, it is inferred
        (KB present -> Windows; package version present -> Linux; otherwise Unknown).
    #>
    param(
        [Parameter(Mandatory)] $Record,
        [hashtable] $OsTypeLookup
    )

    $props = $Record.properties
    if ($props -is [string]) { $props = $props | ConvertFrom-Json }

    $field = {
        param($name)
        if ($props -and $props.PSObject.Properties.Name -contains $name) { [string]$props.$name } else { $null }
    }

    $machineResourceId = ($Record.id -split '/patchAssessmentResults/')[0]
    $patchName = & $field 'patchName'
    $kbFromProp = & $field 'kbId'
    $kbIds = Get-KbIdFromText $patchName $kbFromProp $Record.name

    $reboot = @((& $field 'rebootBehavior'), (& $field 'rebootRequired')) | Where-Object { $_ } | Select-Object -First 1

    $packageVersion = & $field 'version'
    $osType = & $field 'osType'
    if (-not $osType -and $OsTypeLookup) {
        foreach ($k in $OsTypeLookup.Keys) {
            if ($k -and $k -ieq $machineResourceId) { $osType = $OsTypeLookup[$k]; break }
        }
    }
    if (-not $osType) {
        if ($kbIds.Count -gt 0)       { $osType = 'Windows' }
        elseif ($packageVersion)      { $osType = 'Linux' }
        else                          { $osType = 'Unknown' }
    }

    return [ordered]@{
        machineResourceId   = $machineResourceId
        machineName         = ($Record.id -split '/')[8]
        subscriptionId      = $Record.subscriptionId
        resourceGroup       = $Record.resourceGroup
        tenantId            = $Record.tenantId
        osType              = $osType
        assessmentTime      = & $field 'lastModifiedDateTime'
        patchName           = $patchName
        patchId             = $Record.name
        kbIds               = $kbIds
        classification      = & $field 'classifications'
        severityHint        = & $field 'severity'
        rebootRequiredHint  = $reboot
        packageName         = & $field 'name'
        packageVersion      = $packageVersion
        rawUpdateProperties = $props
        source              = 'AzureUpdateManagerResourceGraph'
    }
}

function Get-CveMappingConfidence {
    <#
    .SYNOPSIS
        Classify a KB→CVE mapping's confidence.
    .PARAMETER MatchMethod
        One of: KbToCveMicrosoft (High), VendorAdvisoryExplicitKb (Medium),
        TitleProductVersion (Low), None (None). Unknown methods -> None.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] [AllowEmptyString()] [string] $MatchMethod)

    switch -Regex ($MatchMethod) {
        '^(KbToCveMicrosoft|MsrcDirect)$'                   { return 'High' }
        '^(VendorAdvisoryExplicitKb|AdvisoryKb)$'           { return 'Medium' }
        '^(TitleProductVersion|TitleMatch|ProductVersion)$' { return 'Low' }
        default { return 'None' }
    }
}

function Test-HeadlineEligible {
    <#
    .SYNOPSIS
        Whether a mapping confidence may contribute to headline / executive metrics.
    .DESCRIPTION
        High and Medium are eligible by default. Low is eligible only when
        -AllowLowConfidenceMatches is set (cveEnrichment.allowLowConfidenceMatches).
        None is never eligible.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Confidence,
        [switch] $AllowLowConfidenceMatches
    )
    switch ($Confidence) {
        'High'   { return $true }
        'Medium' { return $true }
        'Low'    { return [bool]$AllowLowConfidenceMatches }
        default  { return $false }
    }
}

function Assert-AssessmentOnly {
    <#
    .SYNOPSIS
        Fail-fast guardrail. Throws if the requested operation is a patch installation,
        patch deployment, or maintenance-configuration-for-installation operation.
    .DESCRIPTION
        Every code path in the security-exposure feature that could reach an
        install/deploy/maintenance-config operation MUST call this first. Read-only
        assessment operations pass through unchanged.
    .PARAMETER Operation
        The operation name, API action, or ARM resource type about to be invoked.
    #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Operation)

    $normalised = ($Operation -replace '[^a-zA-Z]', '').ToLowerInvariant()
    foreach ($blocked in $script:BlockedOperations) {
        if ($normalised -like "*$blocked*") {
            throw $script:AssessmentOnlyError
        }
    }
    if ($normalised -match 'installpatch|deployupdate|scheduleupdate') {
        throw $script:AssessmentOnlyError
    }
}

# ---------------------------------------------------------------------------
# External vulnerability intelligence providers
#   MsrcSecurityUpdateProvider  (KB -> CVE, primary mapping source)
#   NvdCveProvider              (CVE -> CVSS/CWE/... enrichment)
#   OptionalLocalCacheProvider  (transparent file cache + offline mode)
# All read-only HTTP GETs. No install/deploy surface.
# ---------------------------------------------------------------------------

# Minimum seconds between calls per host (courtesy throttle; NVD is stricter
# without an API key). Overridable per call.
$script:VulnHostLastCall = @{}

function Get-MsrcDocumentId {
    <#
    .SYNOPSIS
        Derive the MSRC monthly security-update document ID (e.g. "2023-Oct") from a
        patch's published/release date. MSRC CVRF documents are published per month.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory)] [datetime] $Date)
    $month = [System.Globalization.CultureInfo]::InvariantCulture.DateTimeFormat.GetAbbreviatedMonthName($Date.Month)
    return ('{0}-{1}' -f $Date.Year, $month)
}

function Invoke-VulnApiRequest {
    <#
    .SYNOPSIS
        Shared read-only HTTP GET for vulnerability providers with transparent file
        caching, offline mode, courtesy throttling, and retry-with-backoff.
    .DESCRIPTION
        Returns a status object: @{ status; data; source; sourceUrl; fromCache; error }.
        status is one of: Ok, Cached, OfflineCacheMiss, Error. Network/parse failures NEVER
        throw — they return status=Error so a single provider outage cannot fail the whole
        estate assessment. This function performs GETs only; it has no install surface.
    .PARAMETER CacheKey
        Stable key used for the on-disk cache file (sanitised).
    .PARAMETER Offline
        Serve only from cache; on a cache miss return status=OfflineCacheMiss.
    #>
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $CacheKey,
        [hashtable] $Headers,
        [string]   $CachePath,
        [switch]   $Offline,
        [int]      $MaxAttempts = 3,
        [double]   $MinIntervalSeconds = 0.0,
        [int]      $TimeoutSec = 60
    )

    $cacheFile = $null
    if ($CachePath) {
        $safe = ($CacheKey -replace '[^A-Za-z0-9._-]', '_')
        $cacheFile = Join-Path $CachePath ($safe + '.json')
    }

    # 1) Cache read (always preferred; mandatory in offline mode).
    if ($cacheFile -and (Test-Path -LiteralPath $cacheFile)) {
        try {
            $cached = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            return [ordered]@{ status='Cached'; data=$cached; source='cache'; sourceUrl=$Uri; fromCache=$true; error=$null }
        } catch { }  # fall through to live fetch on corrupt cache
    }
    if ($Offline) {
        return [ordered]@{ status='OfflineCacheMiss'; data=$null; source='cache'; sourceUrl=$Uri; fromCache=$false; error='offline: no cached response' }
    }

    # 2) Courtesy throttle per host.
    if ($MinIntervalSeconds -gt 0) {
        try { $uriHost = ([uri]$Uri).Host } catch { $uriHost = $Uri }
        if ($script:VulnHostLastCall.ContainsKey($uriHost)) {
            $elapsed = (Get-Date) - $script:VulnHostLastCall[$uriHost]
            $wait = $MinIntervalSeconds - $elapsed.TotalSeconds
            if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]($wait * 1000)) }
        }
    }

    # 3) Live GET with retry + exponential backoff on transient failures.
    $hdr = if ($Headers) { $Headers } else { @{ Accept = 'application/json' } }
    $lastErr = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $ProgressPreference = 'SilentlyContinue'
            $resp = Invoke-RestMethod -Uri $Uri -Headers $hdr -TimeoutSec $TimeoutSec -Method Get
            $script:VulnHostLastCall[([uri]$Uri).Host] = Get-Date
            if ($cacheFile) {
                try {
                    if (-not (Test-Path -LiteralPath $CachePath)) { New-Item -ItemType Directory -Path $CachePath -Force | Out-Null }
                    $resp | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cacheFile -Encoding UTF8
                } catch { }
            }
            return [ordered]@{ status='Ok'; data=$resp; source='live'; sourceUrl=$Uri; fromCache=$false; error=$null }
        } catch {
            $lastErr = $_.Exception.Message
            if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds ([math]::Pow(2, $attempt)) }
        }
    }
    return [ordered]@{ status='Error'; data=$null; source='live'; sourceUrl=$Uri; fromCache=$false; error=$lastErr }
}

function Get-MsrcKbCveMapping {
    <#
    .SYNOPSIS
        MsrcSecurityUpdateProvider: map a Microsoft KB to its CVEs using the MSRC Security
        Update Guide CVRF document for the patch's release month. Primary KB->CVE source.
    .DESCRIPTION
        Returns one CveMapping per CVE (matchMethod=KbToCveMicrosoft, confidence=High). If the
        KB is not found in the document, returns a single record with mappingStatus=Unmapped.
        On provider failure returns a single record with mappingStatus=Error (never throws).
    .PARAMETER PublishedDate
        The patch's published/release date, used to resolve the MSRC monthly document.
    #>
    param(
        [Parameter(Mandatory)] [string] $KbId,
        [Parameter(Mandatory)] [datetime] $PublishedDate,
        [string] $PatchName,
        [string] $CachePath,
        [switch] $Offline
    )

    $kbDigits = ($KbId -replace '(?i)^kb', '') -replace '\D', ''
    $docId = Get-MsrcDocumentId $PublishedDate
    $uri = "https://api.msrc.microsoft.com/cvrf/v3.0/cvrf/$docId"

    $base = [ordered]@{
        mappingId=$null; kbId="KB$kbDigits"; patchName=$PatchName; cveId=$null; product=$null
        affectedComponent=$null; source='MSRC'; sourceUrl=$uri; matchMethod='KbToCveMicrosoft'
        confidence='None'; mappingStatus='Unmapped'; notes="MSRC document $docId"
    }

    $r = Invoke-VulnApiRequest -Uri $uri -CacheKey "msrc_$docId" -CachePath $CachePath -Offline:$Offline -MinIntervalSeconds 1.0
    if ($r.status -eq 'Error' -or $r.status -eq 'OfflineCacheMiss') {
        $m = [ordered]@{} + $base; $m.mappingStatus = 'Error'; $m.notes = "$($r.status): $($r.error)"
        return ,$m
    }

    $doc = $r.data
    $results = @()
    $prop = {
        param($obj, $name)
        if ($null -eq $obj) { return $null }
        if ($obj -is [System.Collections.IDictionary]) { if ($obj.Contains($name)) { return $obj[$name] } else { return $null } }
        $pi = $obj.PSObject.Properties[$name]
        if ($pi) { return $pi.Value } else { return $null }
    }

    foreach ($v in (& $prop $doc 'Vulnerability')) {
        $hit = $false
        foreach ($rem in (& $prop $v 'Remediations')) {
            $desc = & $prop $rem 'Description'
            $descVal = if ($desc) { "$(& $prop $desc 'Value')" } else { '' }
            if (($descVal -replace '\D', '') -eq $kbDigits -and $kbDigits) { $hit = $true; break }
        }
        if ($hit) {
            $title = & $prop $v 'Title'
            $m = [ordered]@{} + $base
            $m.mappingId = "KB$kbDigits`:$(& $prop $v 'CVE')"
            $m.cveId = & $prop $v 'CVE'
            $m.product = if ($title) { "$(& $prop $title 'Value')" } else { $null }
            $m.confidence = 'High'
            $m.mappingStatus = 'Mapped'
            $results += $m
        }
    }
    if ($results.Count -eq 0) {
        $m = [ordered]@{} + $base; $m.notes = "KB$kbDigits not present in MSRC document $docId"
        return ,$m
    }
    return $results
}

function Get-NvdCveEnrichment {
    <#
    .SYNOPSIS
        NvdCveProvider: enrich a known CVE with CVSS/CWE/date/reference metadata from the NVD
        CVE API 2.0. Enrichment only — NVD is never used to infer KB->CVE mappings.
    .DESCRIPTION
        Returns a CveEnrichment object (source=NVD). enrichmentStatus is Ok/Cached/NotFound/
        Error/OfflineCacheMiss. Reads an optional API key from -ApiKey or $env:NVD_API_KEY
        (raises the NVD rate limit); the key is never written to cache or output.
    #>
    param(
        [Parameter(Mandatory)] [string] $CveId,
        [string] $ApiKey = $env:NVD_API_KEY,
        [string] $CachePath,
        [switch] $Offline
    )

    $uri = "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=$CveId"
    $headers = @{ Accept = 'application/json' }
    if ($ApiKey) { $headers['apiKey'] = $ApiKey }
    # Without a key NVD asks for <=5 requests / 30s; with a key, <=50 / 30s.
    $interval = if ($ApiKey) { 0.6 } else { 6.0 }

    $enrich = [ordered]@{
        cveId=$CveId; cvssVersion=$null; cvssBaseScore=$null; cvssBaseSeverity=$null
        cvssVector=$null; cweIds=@(); publishedDate=$null; lastModifiedDate=$null
        description=$null; references=@(); exploitabilityScore=$null; impactScore=$null
        source='NVD'; enrichmentStatus='Error'
    }

    $r = Invoke-VulnApiRequest -Uri $uri -CacheKey "nvd_$CveId" -Headers $headers -CachePath $CachePath -Offline:$Offline -MinIntervalSeconds $interval
    if ($r.status -eq 'Error' -or $r.status -eq 'OfflineCacheMiss') {
        $enrich.enrichmentStatus = $r.status; return $enrich
    }

    $vuln = $r.data.vulnerabilities | Select-Object -First 1
    if (-not $vuln) { $enrich.enrichmentStatus = 'NotFound'; return $enrich }
    $cve = $vuln.cve
    $prop = {
        param($obj, $name)
        if ($null -eq $obj) { return $null }
        if ($obj -is [System.Collections.IDictionary]) { if ($obj.Contains($name)) { return $obj[$name] } else { return $null } }
        $pi = $obj.PSObject.Properties[$name]
        if ($pi) { return $pi.Value } else { return $null }
    }

    $metrics = & $prop $cve 'metrics'
    $metric = $null
    if ($metrics) {
        foreach ($k in 'cvssMetricV31','cvssMetricV30','cvssMetricV2') {
            $set = & $prop $metrics $k
            if ($set) { $metric = $set | Select-Object -First 1; break }
        }
    }
    if ($metric) {
        $cd = & $prop $metric 'cvssData'
        $enrich.cvssVersion         = "$(& $prop $cd 'version')"
        $enrich.cvssBaseScore       = & $prop $cd 'baseScore'
        $enrich.cvssBaseSeverity    = "$(& $prop $cd 'baseSeverity')"
        $enrich.cvssVector          = "$(& $prop $cd 'vectorString')"
        $enrich.exploitabilityScore = & $prop $metric 'exploitabilityScore'
        $enrich.impactScore         = & $prop $metric 'impactScore'
    }
    $weaknesses = & $prop $cve 'weaknesses'
    if ($weaknesses) { $enrich.cweIds = @($weaknesses.description.value | Select-Object -Unique) }
    $enrich.publishedDate    = "$(& $prop $cve 'published')"
    $enrich.lastModifiedDate = "$(& $prop $cve 'lastModified')"
    $descs = & $prop $cve 'descriptions'
    if ($descs) { $enrich.description = "$(( $descs | Where-Object { $_.lang -eq 'en' } | Select-Object -First 1).value)" }
    $refs = & $prop $cve 'references'
    if ($refs) { $enrich.references = @($refs.url) }
    $enrich.enrichmentStatus = if ($r.fromCache) { 'Cached' } else { 'Ok' }
    return $enrich
}

Export-ModuleMember -Function `
    Get-KbIdFromText, `
    ConvertFrom-AumSummary, `
    ConvertFrom-AumSoftwarePatch, `
    Get-CveMappingConfidence, `
    Test-HeadlineEligible, `
    Assert-AssessmentOnly, `
    Get-MsrcDocumentId, `
    Invoke-VulnApiRequest, `
    Get-MsrcKbCveMapping, `
    Get-NvdCveEnrichment
