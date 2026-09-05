[CmdletBinding()]
param(
    [string]$WorkspaceName,
    [string]$WorkspaceId,
    [string]$SemanticModelName,
    [string]$SemanticModelId,
    [switch]$TriggerRefresh
)

$ErrorActionPreference = 'Stop'

function Get-AzToken {
    param([Parameter(Mandatory = $true)][string]$Resource)

    $token = & az account get-access-token --resource $Resource --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $token.accessToken) {
        throw "Unable to acquire an access token for $Resource. Run 'az login' and try again."
    }
    return $token.accessToken
}

function Get-FabricCollection {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][hashtable]$Headers
    )

    $items = @()
    $nextUri = $Uri
    while ($nextUri) {
        $response = Invoke-RestMethod -Method Get -Uri $nextUri -Headers $Headers
        $items += @($response.value)
        $nextUri = $response.continuationUri
    }
    return $items
}

if (-not $WorkspaceId -and -not $WorkspaceName) {
    throw 'Specify -WorkspaceName or -WorkspaceId.'
}
if (-not $SemanticModelId -and -not $SemanticModelName) {
    throw 'Specify -SemanticModelName or -SemanticModelId.'
}

$fabricToken = Get-AzToken -Resource 'https://api.fabric.microsoft.com'
$fabricHeaders = @{ Authorization = "Bearer $fabricToken" }

if (-not $WorkspaceId) {
    $workspaces = Get-FabricCollection `
        -Uri 'https://api.fabric.microsoft.com/v1/workspaces' `
        -Headers $fabricHeaders
    $matches = @($workspaces | Where-Object { $_.displayName -eq $WorkspaceName })
    if ($matches.Count -ne 1) {
        throw "Expected one workspace named '$WorkspaceName' but found $($matches.Count). Use -WorkspaceId."
    }
    $WorkspaceId = $matches[0].id
}

if (-not $SemanticModelId) {
    $items = Get-FabricCollection `
        -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items?type=SemanticModel" `
        -Headers $fabricHeaders
    $matches = @($items | Where-Object { $_.displayName -eq $SemanticModelName })
    if ($matches.Count -ne 1) {
        throw "Expected one semantic model named '$SemanticModelName' but found $($matches.Count). Use -SemanticModelId."
    }
    $SemanticModelId = $matches[0].id
}

$bindingsUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$SemanticModelId/connections"
$bindings = @((Invoke-RestMethod -Method Get -Uri $bindingsUri -Headers $fabricHeaders).value)
if ($bindings.Count -eq 0) {
    throw 'The semantic model has no data-source connections. Configure its cloud connections in Fabric first.'
}

$unbound = @($bindings | Where-Object { -not $_.id })
if ($unbound.Count -gt 0) {
    $paths = $unbound | ForEach-Object { "$($_.connectionDetails.type): $($_.connectionDetails.path)" }
    throw "The following data sources are not bound to Fabric connections:`n$($paths -join "`n")"
}

$results = @()
foreach ($binding in $bindings) {
    $connectionUri = "https://api.fabric.microsoft.com/v1/connections/$($binding.id)"
    $connection = Invoke-RestMethod -Method Get -Uri $connectionUri -Headers $fabricHeaders
    $sourceType = $binding.connectionDetails.type

    if ($sourceType -eq 'Web') {
        $body = @{
            connectivityType = $connection.connectivityType
            privacyLevel = 'Organizational'
        } | ConvertTo-Json -Compress

        Invoke-RestMethod `
            -Method Patch `
            -Uri $connectionUri `
            -Headers $fabricHeaders `
            -ContentType 'application/json' `
            -Body $body | Out-Null

        $connection = Invoke-RestMethod -Method Get -Uri $connectionUri -Headers $fabricHeaders
    }

    $expectedCredential = if ($sourceType -eq 'Web') { 'Anonymous' } else { 'OAuth2' }
    $results += [pscustomobject]@{
        Type = $sourceType
        Path = $binding.connectionDetails.path
        Bound = $true
        Privacy = $connection.privacyLevel
        Credential = $connection.credentialDetails.credentialType
        ExpectedCredential = $expectedCredential
    }
}

$invalid = @(
    $results | Where-Object {
        $_.Privacy -ne 'Organizational' -or
        $_.Credential -ne $_.ExpectedCredential
    }
)

$results | Sort-Object Type, Path | Format-Table Type, Privacy, Credential, Path -AutoSize

if ($invalid.Count -gt 0) {
    throw 'One or more connections still have an unexpected privacy level or credential type. Correct them in Manage connections and gateways, then rerun this script.'
}

$powerBiToken = Get-AzToken -Resource 'https://analysis.windows.net/powerbi/api'
$powerBiHeaders = @{ Authorization = "Bearer $powerBiToken" }
$datasetUri = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/datasets/$SemanticModelId"
$dataset = Invoke-RestMethod -Method Get -Uri $datasetUri -Headers $powerBiHeaders
if ($dataset.isOnPremGatewayRequired) {
    throw 'Power BI still classifies this model as requiring a gateway. Confirm that the published model contains the current template query.'
}

Write-Host "Configured $($bindings.Count) connections. Gateway required: false."

if ($TriggerRefresh) {
    $refreshUri = "$datasetUri/refreshes"
    Invoke-RestMethod `
        -Method Post `
        -Uri $refreshUri `
        -Headers $powerBiHeaders `
        -ContentType 'application/json' `
        -Body '{"notifyOption":"NoNotification"}' | Out-Null
    Write-Host 'Refresh requested. Monitor the semantic model refresh history in Fabric.'
}
