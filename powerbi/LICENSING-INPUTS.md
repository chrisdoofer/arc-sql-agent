# Software Assurance core inputs

The template keeps licensing model, Arc/Azure billing mode, Software Assurance
(SA), and Azure Hybrid Benefit (AHB) demand as separate concepts. Arc values
such as `Paid`, `LicenseOnly`, or `ServerCAL` are retained as source signals
and never converted into owned SA cores.

## Configure the public PBIT

When opening the PBIT, set these Power Query parameters:

| Parameter | Required value |
| --- | --- |
| `Licensing_Standard_SA_Cores` | Non-negative whole number |
| `Licensing_Enterprise_SA_Cores` | Non-negative whole number |
| `Licensing_Standard_License_SA_Annual_Cost_Per_Core` | Optional annualized customer price per Standard core for a new licence with SA |
| `Licensing_Enterprise_License_SA_Annual_Cost_Per_Core` | Optional annualized customer price per Enterprise core for a new licence with SA |

The values are trusted customer inputs. The template does not request or retain
licensing evidence, agreement references, effective dates, or confidence
ratings. Enter `Not provided` for either price when a customer-specific
License+SA rate is unavailable; the report will show the assessment PAYG cost
without claiming that either purchase option is cheaper.

After changing a parameter in Power BI Desktop, select **Apply changes** and
refresh the model. After publishing, parameters can also be updated under the
semantic model's **Settings > Parameters**, followed by a refresh.

## Report semantics

- **Licensing model** is populated only when the source explicitly reports
  Core or Server/CAL. Ambiguous values remain `Unknown`.
- **Billing mode** preserves the Arc extension or Azure SQL VM configuration.
- **Owned SA cores** come only from the two trusted customer parameters.
- **Current core gap** compares edition-matched owned SA cores with current
  Standard and Enterprise Database Engine cores. SSIS and free editions such
  as Developer are excluded.
- **Target AHB core gap** compares the same owned SA position with the
  edition-matched target cores predicted by the Azure migration assessment.
- The dedicated `Licensing Position` page is a decision page, not another
  server inventory. It shows total, Standard, and Enterprise core positions,
  the target-core shortfall, and a cost comparison for that shortfall.
- **PAYG for gap** uses the assessment's own
  `monthlyCost.sqlLicenseCost` value in proportion to uncovered target cores.
  This is the authoritative SQL PAYG licence component produced by the same
  assessment that has SQL AHB enabled.
- **Buy License+SA for gap** uses the optional customer-entered annualized
  Standard and Enterprise per-core prices, divided by 12 for a monthly
  equivalent.
- Both options include the same assessed AHB infrastructure baseline, so the
  decision isolates the licensing treatment of cores not covered by owned SA.
- Reservation or savings-plan selection affects the shared infrastructure
  baseline. It does not discount the assessment SQL licence component or the
  customer-entered License+SA price.
- Rows without an assessment SQL licence component are disclosed as incomplete
  and are not assigned a fabricated PAYG cost.

## Durable Fabric option

For repeat assessments, the edition-level core values and optional annualized
prices can be stored in a governed customer-owned Lakehouse table:

`standard_sa_cores`, `enterprise_sa_cores`,
`standard_license_sa_annual_cost_per_core`, and
`enterprise_license_sa_annual_cost_per_core`.

Replace the single-row `licensing_inputs` parameter table with that Lakehouse
table when central management of the trusted core values is required.
