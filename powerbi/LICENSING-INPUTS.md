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

The values are trusted customer inputs. The template does not request or retain
licensing evidence, agreement references, effective dates, or confidence
ratings.

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
- **Target AHB core gap** compares the same owned SA position with the Database
  Standard and Enterprise Database Engine cores predicted by the existing ESU
  Forecast migration assessment.
- The focused core position appears on the existing `ESU Forecast` page; there
  is no separate licensing inventory page.
- Azure Migrate and ESU source costs remain as reported. The model does not
  automatically apply an AHB discount to those source estimates.

## Durable Fabric option

For repeat assessments, the two edition-level core values can optionally be
stored in a governed customer-owned Lakehouse table:

`standard_sa_cores` and `enterprise_sa_cores`.

Replace the single-row `licensing_inputs` parameter table with that Lakehouse
table when central management of the trusted core values is required.
