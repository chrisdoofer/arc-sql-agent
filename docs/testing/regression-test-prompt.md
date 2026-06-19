# Regression Test Prompt

Use this prompt to execute a full estate analysis with pre-defined answers. Copy the entire block below into the Copilot CLI to run a hands-free regression test.

## Usage

1. Run `git pull` to get the latest skill changes
2. Paste the prompt below into the Copilot CLI
3. After execution completes, run the validation script: `pwsh docs/testing/validate-report.ps1`

## Test Prompt

```
/arc-sql-estate-analysis

Analyse this Arc-enabled SQL estate. Check if there's an Azure Migrate project in the tenant and include utilisation baselines and application dependency mapping in the analysis.

For this test run, use the following pre-defined answers for all interactive prompts (do not prompt me — use these directly):

- Tenant ID: c202f0a2-c1d7-4498-bb80-d61e138803f3
- Subscription scope: All subscriptions in tenant
- Software Assurance: Yes
- Standard SA-covered cores: 0
- Enterprise SA-covered cores: 2
- Azure Migrate project selection: Select the first project found (ArcBoxMigrate expected)
- Dependency data: I do not have a CSV to provide (but confirm the prompt WAS triggered)
- BPA alignment scan: Yes — run alignment scan
- All Arc Run Command script approvals: Approve for all listed machines
- Tier 3 BPA scan (if offered): Yes — run full scan via Arc Run Command

After analysis is complete, export to HTML at the default path (estate-report.html).

IMPORTANT: Even though answers are pre-defined, you MUST still execute every phase of the analysis workflow including:
- Scope validation query
- Consolidated estate ARG query
- Azure Migrate utilisation data extraction
- Azure Migrate dependency prompt (ask_user MUST still fire — just use the pre-defined answer)
- Enterprise downgrade DMV audit via Arc Run Command
- Enterprise downgrade runtime validation via Arc Run Command
- BPA alignment scan (Tier 1 + Tier 2 + Tier 3 if needed)
- Full analysis output with all 10 sections
- HTML export with validation
```

## Expected Outcomes

After a successful run, the following should all be true:

### Phase 1-2: Scope
- [ ] Tenant resolved to c202f0a2-c1d7-4498-bb80-d61e138803f3
- [ ] 5 subscriptions discovered
- [ ] Scope validated: 3 SQL instances, 7 machines in wrkload-uk-001

### Phase 3: Licensing
- [ ] SA declared as Enabled with 0 Standard / 2 Enterprise cores

### Phase 4: Data Acquisition
- [ ] Consolidated ARG query returned: 3 instances, 15 databases, 7 machines, 1 Migrate project
- [ ] Assessment data extracted for ArcBox-SQL (MI=NotReady, VM=Ready)
- [ ] Assessment data extracted for ARCBOX-SQL2016 (MI=Ready, VM=Ready)
- [ ] ArcBox-SQL_SSIS_2022 noted as assessment not enabled
- [ ] Azure Migrate project ArcBoxMigrate selected
- [ ] Utilisation data retrieved (ArcBox-SQL: ~90% CPU, ~68% memory)
- [ ] Dependency prompt fired (ask_user triggered asking about CSV export)
- [ ] Dependency noted as not enabled / no CSV provided

### Phase 5: Enterprise Downgrade Audit
- [ ] DMV audit executed on ArcBox-SQL (slot estate-audit-ArcBox-SQL-01)
- [ ] DMV audit executed on ARCBOX-SQL2016 (slot estate-audit-ARCBOX-SQL2016-01)
- [ ] Both returned: no persisted features detected
- [ ] Runtime validation executed on both machines (slot-02)
- [ ] All 4 runtime checks passed on both: AG, Resource Governor, Partitions, Online Index
- [ ] ArcBox-SQL/MSSQLSERVER classified GREEN
- [ ] ARCBOX-SQL2016/MSSQLSERVER classified GREEN
- [ ] SSIS_2022 classified RED (unreachable)

### Phase 4 step 9: BPA Alignment
- [ ] Tier 1: Resource Graph checks extracted (INST-01, SEC-01, etc.)
- [ ] Tier 2: Log Analytics workspace la-arcbox-001 discovered
- [ ] Tier 2: SqlAssessment_CL table found and queried successfully
- [ ] Tier 2: BPA findings returned for both ArcBox-SQL and ARCBOX-SQL2016
- [ ] BPA data freshness disclosed (date of latest TimeGenerated)
- [ ] Tier 3 offered (if BPA coverage incomplete) OR skipped (if BPA sufficient)

### Phase 6-7: Analysis & Export
- [ ] HTML report generated at estate-report.html
- [ ] All 10 required sections present in HTML
- [ ] GREEN/RED badges rendered correctly
- [ ] Status badges (Pass/Fail/Warning) rendered for BPA alignment
- [ ] Assessment data (MI/VM readiness, costs) included in Azure target recommendations
- [ ] Utilisation data attributed to Azure Migrate with confidence rating

## Known Test Environment State

These are characteristics of the test environment that should remain stable:

| Property | Expected Value |
|----------|---------------|
| Tenant ID | c202f0a2-c1d7-4498-bb80-d61e138803f3 |
| SQL machines | ArcBox-SQL, ARCBOX-SQL2016 |
| SQL instances | ArcBox-SQL/MSSQLSERVER, ArcBox-SQL/SSIS_2022, ARCBOX-SQL2016/MSSQLSERVER |
| All editions | Enterprise |
| Migrate project | ArcBoxMigrate (rg-cb-migrate-001) |
| LA workspace | la-arcbox-001 (rg-cb-arcbox-001) |
| BPA table | SqlAssessment_CL (in la-arcbox-001) |
| Run command slots | estate-audit-{machine}-01 and -02 on both machines |
| SSIS_2022 status | Unreachable (SQL Browser not running) |

## Updating This Test

When new features are added to the skill:
1. Add a new assertion to the "Expected Outcomes" section above
2. Add a corresponding check to `validate-report.ps1`
3. If the feature requires a new interactive prompt, add the pre-defined answer to the test prompt
