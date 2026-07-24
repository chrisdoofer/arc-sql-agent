[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $WorkspaceResourceGroup,
    [Parameter(Mandatory)] [string] $WorkspaceName,
    [Parameter(Mandatory)] [string] $Location,
    [string] $DcrName = 'arc-sql-dependency-map-only',
    [string[]] $MachineResourceIds,
    [int] $RetentionInDays = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'

if (-not $MachineResourceIds -or $MachineResourceIds.Count -eq 0) {
    throw 'At least one Arc machine resource ID must be supplied.'
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templatePath = Join-Path $scriptDir 'deploy-map-only.bicep'

az account set --subscription $SubscriptionId | Out-Null
az extension add --name monitor-control-service --only-show-errors | Out-Null

$deployment = az deployment group create `
    --resource-group $WorkspaceResourceGroup `
    --template-file $templatePath `
    --parameters workspaceName=$WorkspaceName location=$Location dcrName=$DcrName retentionInDays=$RetentionInDays `
    -o json | ConvertFrom-Json

$dcrId = $deployment.properties.outputs.dcrResourceId.value

foreach ($machineId in $MachineResourceIds) {
    $machine = az resource show --ids $machineId -o json | ConvertFrom-Json
    $machineName = $machine.name
    $machineRg = $machine.resourceGroup
    $machineLocation = $machine.location
    $osName = [string] $machine.properties.osName

    if ($osName -match 'windows') {
        $amaName = 'AzureMonitorWindowsAgent'
        $depName = 'DependencyAgentWindows'
    } else {
        $amaName = 'AzureMonitorLinuxAgent'
        $depName = 'DependencyAgentLinux'
    }

    az connectedmachine extension create `
        --machine-name $machineName `
        --resource-group $machineRg `
        --location $machineLocation `
        --publisher Microsoft.Azure.Monitor `
        --type $amaName `
        --name $amaName `
        --enable-auto-upgrade true `
        -o none

    az connectedmachine extension create `
        --machine-name $machineName `
        --resource-group $machineRg `
        --location $machineLocation `
        --publisher Microsoft.Azure.Monitoring.DependencyAgent `
        --type $depName `
        --name $depName `
        --enable-auto-upgrade true `
        -o none

    az monitor data-collection rule association create `
        --name "$machineName-vminsights-map" `
        --rule-id $dcrId `
        --resource $machineId `
        -o none
}

Write-Host 'Map-only VM Insights dependency prerequisite deployed. Leave it in place for about 24 hours before running analysis.' -ForegroundColor Green
