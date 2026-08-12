# Licensing declaration setup

The template keeps licensing model, Arc/Azure billing mode, Software Assurance
(SA), and Azure Hybrid Benefit (AHB) eligibility as separate concepts. Arc
values such as `Paid`, `LicenseOnly`, or `ServerCAL` are retained as source
signals and never treated as proof of SA entitlement.

## Configure the public PBIT

When opening the PBIT, set these Power Query parameters:

| Parameter | Required value |
| --- | --- |
| `Licensing_SA_Status` | `Confirmed`, `Not confirmed`, or `Unknown` |
| `Licensing_Standard_SA_Cores` | Non-negative whole number |
| `Licensing_Enterprise_SA_Cores` | Non-negative whole number |
| `Licensing_Evidence_Source` | Evidence reference, such as an agreement review or licensing statement |
| `Licensing_Effective_Date` | ISO date in `YYYY-MM-DD` format |
| `Licensing_Assessment_Run` | Customer or assessment-run identifier |

If entitlement is not confirmed, keep the status as `Unknown` or
`Not confirmed`. The report leaves AHB-covered and uncovered core measures
blank rather than converting billing metadata into entitlement.

After changing a parameter in Power BI Desktop, select **Apply changes** and
refresh the model. After publishing, parameters can also be updated under the
semantic model's **Settings > Parameters**, followed by a refresh.

## Report semantics

- **Licensing model** is populated only when the source explicitly reports
  Core or Server/CAL. Ambiguous values remain `Unknown`.
- **Billing mode** preserves the Arc extension or Azure SQL VM configuration.
- **SA status** comes only from the customer declaration parameters.
- **AHB-covered cores** are the lower of declared SA cores and observed
  Database Engine cores for the matching edition.
- **SSIS cores** are reported separately and never increase Database Engine
  AHB coverage.
- Azure Migrate and ESU source costs remain as reported. The model discloses
  the eligible core coverage but does not automatically apply a discount.

## Durable Fabric option

For repeat assessments, store the same declaration fields in a governed
Lakehouse table keyed by customer and assessment run:

`assessment_run`, `effective_date`, `software_assurance_status`,
`standard_sa_cores`, `enterprise_sa_cores`, `evidence_source`, and
`declaration_confidence`.

Replace the single-row `licensing_declaration` parameter table with that
Lakehouse table and select the applicable assessment run in the semantic
model. This preserves licensing history and evidence lineage without embedding
customer-owned data in the public PBIT.
