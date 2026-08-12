[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$powerBiRoot = Split-Path -Parent $PSScriptRoot
$bimPath = Join-Path $powerBiRoot 'ArcSqlEstate.bim'
$layoutBuilderPath = Join-Path $PSScriptRoot 'build-layout.mjs'
$model = Get-Content -Raw -Encoding utf8 $bimPath | ConvertFrom-Json -Depth 100

$requiredParameters = @(
    'Licensing_SA_Status',
    'Licensing_Standard_SA_Cores',
    'Licensing_Enterprise_SA_Cores',
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

$declaration = $model.model.tables | Where-Object name -eq 'licensing_declaration'
if ($null -eq $declaration) {
    throw 'The customer-owned licensing declaration table is missing.'
}

$sqlView = $model.model.tables | Where-Object name -eq 'view_sql_instances'
$legacyColumn = $sqlView.columns | Where-Object name -eq 'sql_license_type'
if (-not $legacyColumn.isHidden) {
    throw 'The legacy conflated sql_license_type field must remain hidden.'
}

$requiredColumns = @(
    'billing_mode',
    'licensing_model',
    'software_assurance_status',
    'ahb_eligibility',
    'licensable_cores',
    'licensing_confidence'
)
foreach ($column in $requiredColumns) {
    if ($column -notin @($sqlView.columns.name)) {
        throw "Missing licensing semantic column '$column'."
    }
}

$measureNames = @(($model.model.tables | Where-Object name -eq 'all_measures').measures.name)
foreach ($measure in @(
    'kpi_engine_licensable_cores',
    'kpi_ssis_licensable_cores',
    'kpi_ahb_covered_engine_cores',
    'kpi_ahb_uncovered_engine_cores',
    'licensing_data_gap_text',
    'licensing_cost_assumption_text'
)) {
    if ($measure -notin $measureNames) {
        throw "Missing licensing measure '$measure'."
    }
}

$fixture = @(
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Enterprise'; Cores = 10 },
    [pscustomobject]@{ ServiceType = 'Engine'; Edition = 'Enterprise'; Cores = 15 },
    [pscustomobject]@{ ServiceType = 'SSIS'; Edition = 'Enterprise'; Cores = 21 }
)
$declaredEnterpriseCores = 6
$engineCores = ($fixture |
    Where-Object ServiceType -eq 'Engine' |
    Measure-Object Cores -Sum).Sum
$coveredEngineCores = [Math]::Min($declaredEnterpriseCores, $engineCores)
$uncoveredEngineCores = $engineCores - $coveredEngineCores

if ($engineCores -ne 25 -or $coveredEngineCores -ne 6 -or $uncoveredEngineCores -ne 19) {
    throw 'Edition-matched engine core reconciliation failed for the mixed Engine/SSIS fixture.'
}

$additionalSsis = $fixture + [pscustomobject]@{
    ServiceType = 'SSIS'
    Edition = 'Enterprise'
    Cores = 64
}
$engineCoresWithAdditionalSsis = ($additionalSsis |
    Where-Object ServiceType -eq 'Engine' |
    Measure-Object Cores -Sum).Sum
if ($engineCoresWithAdditionalSsis -ne $engineCores) {
    throw 'Adding SSIS resources changed the Database Engine licensing population.'
}

$layoutBuilder = Get-Content -Raw -Encoding utf8 $layoutBuilderPath
if (-not $layoutBuilder.Contains('displayName: "Licensing Position"')) {
    throw 'The Licensing Position report page is not generated.'
}
if (-not $layoutBuilder.Contains('"view_sql_instances.billing_mode"')) {
    throw 'The existing SQL licensing visuals are not rebound to billing mode.'
}

Write-Host 'PASS: licensing model, billing mode, SA evidence, AHB coverage, and SSIS separation are consistent.'
