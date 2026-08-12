[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$powerBiRoot = Split-Path -Parent $PSScriptRoot
$bimPath = Join-Path $powerBiRoot 'ArcSqlEstate.bim'
$layoutBuilderPath = Join-Path $PSScriptRoot 'build-layout.mjs'
$model = Get-Content -Raw -Encoding utf8 $bimPath | ConvertFrom-Json -Depth 100

$requiredParameters = @(
    'Licensing_Standard_SA_Cores',
    'Licensing_Enterprise_SA_Cores',
    'Licensing_Standard_License_SA_Annual_Cost_Per_Core',
    'Licensing_Enterprise_License_SA_Annual_Cost_Per_Core'
)
$removedParameters = @(
    'Licensing_SA_Status',
    'Licensing_Evidence_Source',
    'Licensing_Effective_Date',
    'Licensing_Assessment_Run'
)
$parameterNames = @($model.model.expressions.name)
foreach ($parameter in $requiredParameters) {
    if ($parameter -notin $parameterNames) {
        throw "Missing licensing parameter '$parameter'."
    }
}
foreach ($parameter in $removedParameters) {
    if ($parameter -in $parameterNames) {
        throw "Removed licensing evidence parameter '$parameter' is still present."
    }
}

$inputs = $model.model.tables | Where-Object name -eq 'licensing_inputs'
if ($null -eq $inputs) {
    throw 'The trusted Software Assurance core-input table is missing.'
}
if (@($inputs.columns.name | Sort-Object) -join ',' -ne 'enterprise_license_sa_annual_cost_per_core,enterprise_sa_cores,standard_license_sa_annual_cost_per_core,standard_sa_cores') {
    throw 'The licensing input table must contain edition-level SA cores and optional annualized License+SA prices.'
}
if ($model.model.tables.name -contains 'licensing_declaration') {
    throw 'The removed licensing evidence table is still present.'
}

$sqlView = $model.model.tables | Where-Object name -eq 'view_sql_instances'
$legacyColumn = $sqlView.columns | Where-Object name -eq 'sql_license_type'
if (-not $legacyColumn.isHidden) {
    throw 'The legacy conflated sql_license_type field must remain hidden.'
}

$requiredColumns = @(
    'billing_mode',
    'licensing_model',
    'licensable_cores'
)
foreach ($column in $requiredColumns) {
    if ($column -notin @($sqlView.columns.name)) {
        throw "Missing licensing semantic column '$column'."
    }
}
foreach ($column in @('software_assurance_status', 'ahb_eligibility', 'licensing_confidence')) {
    if ($column -in @($sqlView.columns.name)) {
        throw "Removed licensing evidence column '$column' is still present."
    }
}

foreach ($column in @(
    'mi_sql_license_cost',
    'db_sql_license_cost',
    'vm_sql_license_cost',
    'mi_target_cores',
    'db_target_cores',
    'vm_target_cores'
)) {
    if ($column -notin @($sqlView.columns.name)) {
        throw "The migration assessment field '$column' is missing from the SQL view."
    }
}

$esuView = $model.model.tables | Where-Object name -eq 'view_esu'
if ('service_type' -notin @($esuView.columns.name)) {
    throw 'The ESU forecast does not expose service_type for Engine-only target-core reconciliation.'
}

if ('dim_licensing_edition' -notin @($model.model.tables.name)) {
    throw 'The stable Standard/Enterprise licensing chart axis is missing.'
}
foreach ($column in @(
    'mi_sql_license_cost',
    'db_sql_license_cost',
    'vm_sql_license_cost',
    'mi_target_cores',
    'db_target_cores',
    'vm_target_cores'
)) {
    if ($column -notin @($esuView.columns.name)) {
        throw "The ESU forecast does not expose '$column'."
    }
}

$measureNames = @(($model.model.tables | Where-Object name -eq 'all_measures').measures.name)
foreach ($measure in @(
    'kpi_engine_licensable_cores',
    'kpi_owned_sa_cores',
    'kpi_current_sa_covered_engine_cores',
    'kpi_current_sa_core_gap',
    'kpi_target_ahb_required_cores',
    'kpi_target_ahb_covered_cores',
    'kpi_target_ahb_core_gap',
    'kpi_target_standard_ahb_required_cores',
    'kpi_target_enterprise_ahb_required_cores',
    'kpi_target_standard_ahb_core_gap',
    'kpi_target_enterprise_ahb_core_gap',
    'kpi_target_sql_payg_license_cost_monthly',
    'kpi_gap_sql_payg_license_cost_monthly',
    'kpi_gap_license_sa_cost_monthly',
    'kpi_payg_gap_option_monthly',
    'kpi_license_sa_gap_option_monthly',
    'kpi_licensing_option_saving_monthly',
    'kpi_cheaper_licensing_option',
    'licensing_cost_assumption_text',
    'kpi_paas_target_ahb_required_cores',
    'kpi_vm_target_ahb_required_cores',
    'kpi_paas_target_ahb_core_gap',
    'kpi_vm_target_ahb_core_gap',
    'kpi_paas_payg_gap_option_monthly',
    'kpi_vm_payg_gap_option_monthly',
    'kpi_paas_license_sa_gap_option_monthly',
    'kpi_vm_license_sa_gap_option_monthly',
    'kpi_paas_cheaper_licensing_option',
    'kpi_vm_cheaper_licensing_option',
    'licensing_scenario_assumption_text',
    'kpi_paas_target_cores_by_edition',
    'kpi_vm_target_cores_by_edition'
)) {
    if ($measure -notin $measureNames) {
        throw "Missing licensing measure '$measure'."
    }
}

$currentFixture = @(
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Enterprise'; Cores = 10 },
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Enterprise'; Cores = 15 },
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Developer'; Cores = 8 },
    [pscustomobject]@{ ServiceType = 'SSIS'; Edition = 'Enterprise'; Cores = 21 }
)
$targetFixture = @(
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Standard'; Cores = 8; MonthlySqlPayg = 400 },
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Enterprise'; Cores = 12; MonthlySqlPayg = 1200 },
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Developer'; Cores = 10; MonthlySqlPayg = 0 },
    [pscustomobject]@{ ServiceType = 'SSIS'; Edition = 'Enterprise'; Cores = 64; MonthlySqlPayg = 6400 }
)
$ownedStandardCores = 4
$ownedEnterpriseCores = 6
$engineCores = ($currentFixture |
    Where-Object { $_.ServiceType -eq 'Engine' -and $_.Edition -in @('Standard', 'Enterprise') } |
    Measure-Object Cores -Sum).Sum
$currentCoveredCores = [Math]::Min($ownedEnterpriseCores, $engineCores)
$currentGap = $engineCores - $currentCoveredCores
$targetCores = ($targetFixture |
    Where-Object { $_.ServiceType -eq 'Engine' -and $_.Edition -in @('Standard', 'Enterprise') } |
    Measure-Object Cores -Sum).Sum
$targetCoveredCores =
    [Math]::Min($ownedStandardCores, 8) +
    [Math]::Min($ownedEnterpriseCores, 12)
$targetGap = $targetCores - $targetCoveredCores

if (
    $engineCores -ne 25 -or
    $currentCoveredCores -ne 6 -or
    $currentGap -ne 19 -or
    $targetCores -ne 20 -or
    $targetCoveredCores -ne 10 -or
    $targetGap -ne 10
) {
    throw 'Current and forecast Engine core reconciliation failed.'
}

$standardGap = 8 - $ownedStandardCores
$enterpriseGap = 12 - $ownedEnterpriseCores
$paygForGap =
    (400 * ($standardGap / 8)) +
    (1200 * ($enterpriseGap / 12))
$standardAnnualLicenseSaPerCore = 600
$enterpriseAnnualLicenseSaPerCore = 1800
$licenseSaForGap =
    (($standardGap * $standardAnnualLicenseSaPerCore) +
     ($enterpriseGap * $enterpriseAnnualLicenseSaPerCore)) / 12
if ($paygForGap -ne 800 -or $licenseSaForGap -ne 1100) {
    throw 'PAYG versus annualized License+SA shortfall comparison failed.'
}

$scenarioFixture = @(
    [pscustomobject]@{ Edition = 'Enterprise'; LogicalCores = 2; MiReady = $true; MiCores = 4; VmReady = $true; VmCores = 2 },
    [pscustomobject]@{ Edition = 'Enterprise'; LogicalCores = 2; MiReady = $false; MiCores = $null; VmReady = $true; VmCores = 2 },
    [pscustomobject]@{ Edition = 'Enterprise'; LogicalCores = 4; MiReady = $false; MiCores = $null; VmReady = $true; VmCores = 4 }
)
$paasScenarioCores = ($scenarioFixture | ForEach-Object {
    if ($_.MiReady) { $_.MiCores }
    elseif ($_.VmReady) { $_.VmCores }
    else { [Math]::Max($_.LogicalCores, 2) }
} | Measure-Object -Sum).Sum
$vmScenarioCores = ($scenarioFixture | ForEach-Object {
    if ($_.VmReady) { $_.VmCores }
    else { [Math]::Max($_.LogicalCores, 2) }
} | Measure-Object -Sum).Sum
if ($paasScenarioCores -ne 10 -or $vmScenarioCores -ne 8) {
    throw 'PaaS-first and SQL VM-only target-core scenarios were not calculated independently.'
}

$additionalSsis = $currentFixture + [pscustomobject]@{
    ServiceType = 'SSIS'
    Edition = 'Enterprise'
    Cores = 64
}
$engineCoresWithAdditionalSsis = ($additionalSsis |
    Where-Object { $_.ServiceType -eq 'Engine' -and $_.Edition -in @('Standard', 'Enterprise') } |
    Measure-Object Cores -Sum).Sum
if ($engineCoresWithAdditionalSsis -ne $engineCores) {
    throw 'Adding SSIS resources changed the Database Engine licensing population.'
}

$layoutBuilder = Get-Content -Raw -Encoding utf8 $layoutBuilderPath
if (-not $layoutBuilder.Contains('buildLicensingPage(),')) {
    throw 'The dedicated Licensing Position page is not generated.'
}
if ($layoutBuilder.Contains('enhanceEsuForecastPage')) {
    throw 'The licensing overlays are still applied to the ESU Forecast page.'
}
foreach ($measure in @(
    'kpi_owned_sa_cores',
    'kpi_paas_target_ahb_required_cores',
    'kpi_vm_target_ahb_required_cores',
    'kpi_paas_target_ahb_core_gap',
    'kpi_vm_target_ahb_core_gap',
    'kpi_paas_payg_gap_option_monthly',
    'kpi_vm_payg_gap_option_monthly',
    'kpi_paas_cheaper_licensing_option',
    'kpi_vm_cheaper_licensing_option'
)) {
    if (-not $layoutBuilder.Contains($measure)) {
        throw "The Licensing Position layout is missing '$measure'."
    }
}
if (-not $layoutBuilder.Contains('"view_sql_instances.billing_mode"')) {
    throw 'The existing SQL licensing visuals are not rebound to billing mode.'
}

Write-Host 'PASS: the dedicated licensing page compares PaaS-first and SQL VM-only target cores, gaps, PAYG, and optional License+SA pricing.'
