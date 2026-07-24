[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $WorkspaceResourceGroup,
    [Parameter(Mandatory)] [string] $WorkspaceName,
    [Parameter(Mandatory)] [string] $DcrName,
    [string[]] $MachineResourceIds,
    [switch] $DeleteWorkspace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:AZURE_CORE_ONLY_SHOW_ERRORS = 'true'

az account set --subscription $SubscriptionId | Out-Null
az extension add --name monitor-control-service --only-show-errors | Out-Null

foreach ($machineId in ($MachineResourceIds | Where-Object { $_ })) {
    $machine = az resource show --ids $machineId -o json | ConvertFrom-Json
    $machineName = $machine.name
    $machineRg = $machine.resourceGroup
    $osName = [string] $machine.properties.osName

    az monitor data-collection rule association delete `
        --name "$machineName-vminsights-map" `
        --resource $machineId `
        -o none

    if ($osName -match 'windows') {
        $amaName = 'AzureMonitorWindowsAgent'
        $depName = 'DependencyAgentWindows'
    } else {
        $amaName = 'AzureMonitorLinuxAgent'
        $depName = 'DependencyAgentLinux'
    }

    az connectedmachine extension delete --machine-name $machineName --resource-group $machineRg --name $depName -o none
    az connectedmachine extension delete --machine-name $machineName --resource-group $machineRg --name $amaName -o none
}

az monitor data-collection rule delete --name $DcrName --resource-group $WorkspaceResourceGroup --yes -o none

if ($DeleteWorkspace) {
    az monitor log-analytics workspace delete --resource-group $WorkspaceResourceGroup --workspace-name $WorkspaceName --yes -o none
}

Write-Host 'Map-only VM Insights dependency prerequisite removed.' -ForegroundColor Green
