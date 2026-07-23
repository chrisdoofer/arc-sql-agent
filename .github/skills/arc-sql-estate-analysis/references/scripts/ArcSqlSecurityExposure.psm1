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
        assessmentStatus    = if ($props -and $props.PSObject.Properties.Name -contains 'assessmentState') { [string]$props.assessmentState } else { 'Unknown' }
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

Export-ModuleMember -Function `
    Get-KbIdFromText, `
    ConvertFrom-AumSummary, `
    ConvertFrom-AumSoftwarePatch, `
    Get-CveMappingConfidence, `
    Test-HeadlineEligible, `
    Assert-AssessmentOnly
