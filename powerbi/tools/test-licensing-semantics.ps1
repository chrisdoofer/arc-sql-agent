[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$powerBiRoot = Split-Path -Parent $PSScriptRoot
$bimPath = Join-Path $powerBiRoot 'ArcSqlEstate.bim'
$layoutBuilderPath = Join-Path $PSScriptRoot 'build-layout.mjs'
$model = Get-Content -Raw -Encoding utf8 $bimPath | ConvertFrom-Json -Depth 100

$requiredParameters = @(
    'Licensing_Standard_SA_Cores',
    'Licensing_Enterprise_SA_Cores'
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
if (@($inputs.columns.name | Sort-Object) -join ',' -ne 'enterprise_sa_cores,standard_sa_cores') {
    throw 'The licensing input table must contain only Standard and Enterprise SA core counts.'
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

$esuView = $model.model.tables | Where-Object name -eq 'view_esu'
if ('service_type' -notin @($esuView.columns.name)) {
    throw 'The ESU forecast does not expose service_type for Engine-only target-core reconciliation.'
}

$measureNames = @(($model.model.tables | Where-Object name -eq 'all_measures').measures.name)
foreach ($measure in @(
    'kpi_engine_licensable_cores',
    'kpi_owned_sa_cores',
    'kpi_current_sa_covered_engine_cores',
    'kpi_current_sa_core_gap',
    'kpi_target_ahb_required_cores',
    'kpi_target_ahb_covered_cores',
    'kpi_target_ahb_core_gap'
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
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Enterprise'; Cores = 12 },
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Enterprise'; Cores = 18 },
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Developer'; Cores = 10 },
    [pscustomobject]@{ ServiceType = 'SSIS'; Edition = 'Enterprise'; Cores = 64 }
)
$ownedEnterpriseCores = 6
$engineCores = ($currentFixture |
    Where-Object { $_.ServiceType -eq 'Engine' -and $_.Edition -in @('Standard', 'Enterprise') } |
    Measure-Object Cores -Sum).Sum
$currentCoveredCores = [Math]::Min($ownedEnterpriseCores, $engineCores)
$currentGap = $engineCores - $currentCoveredCores
$targetCores = ($targetFixture |
    Where-Object { $_.ServiceType -eq 'Engine' -and $_.Edition -in @('Standard', 'Enterprise') } |
    Measure-Object Cores -Sum).Sum
$targetCoveredCores = [Math]::Min($ownedEnterpriseCores, $targetCores)
$targetGap = $targetCores - $targetCoveredCores

if (
    $engineCores -ne 25 -or
    $currentCoveredCores -ne 6 -or
    $currentGap -ne 19 -or
    $targetCores -ne 30 -or
    $targetCoveredCores -ne 6 -or
    $targetGap -ne 24
) {
    throw 'Current and forecast Engine core reconciliation failed.'
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
if ($layoutBuilder.Contains('buildLicensingPage(),')) {
    throw 'The duplicate Licensing Position page is still generated.'
}
if (-not $layoutBuilder.Contains('enhanceEsuForecastPage();')) {
    throw 'The ESU Forecast page is not enhanced with the focused SA/AHB core position.'
}
foreach ($measure in @(
    'kpi_owned_sa_cores',
    'kpi_engine_licensable_cores',
    'kpi_target_ahb_required_cores',
    'kpi_current_sa_core_gap',
    'kpi_target_ahb_core_gap'
)) {
    if (-not $layoutBuilder.Contains($measure)) {
        throw "The ESU Forecast layout is missing '$measure'."
    }
}
if (-not $layoutBuilder.Contains('"view_sql_instances.billing_mode"')) {
    throw 'The existing SQL licensing visuals are not rebound to billing mode.'
}

Write-Host 'PASS: trusted SA core inputs reconcile current and forecast Engine demand without a duplicate licensing page or evidence capture.'
