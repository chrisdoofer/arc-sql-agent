# Fabric refresh setup

This guide applies after publishing `arc_sql_estate_strategy.pbit` to a Fabric
workspace.

## What the template already fixes

The current template does not use `Web.BrowserContents`. The SQL Server build
reference is retrieved with `Web.Contents` by requesting Microsoft Learn's
static Markdown representation and parsing its version tables. This is
compatible with Power BI Service and does not require a browser engine,
personal gateway, VNet gateway, or on-premises gateway.

This change is included in:

- `arc_sql_estate_strategy.pbit`
- `ArcSqlEstate.bim`
- `ArcSqlEstate/Model/tables/dim_sql_patches.tmdl`

## Why tenant-specific setup is still required

A PBIT contains the report, semantic model, and Power Query definitions. It
cannot carry another tenant's Fabric connection objects, OAuth tokens,
credentials, ownership, or service-side privacy settings.

The model combines:

- Azure Resource Graph, authenticated with an Organizational account.
- Public Microsoft and Linux vendor web endpoints, authenticated anonymously.

Some vendor requests are narrowed using package and release values returned by
Azure Resource Graph. Power BI Service therefore requires both sides of this
combination to use the same `Organizational` privacy boundary. The web
credentials remain `Anonymous`; privacy level and credential type are separate
settings.

## Recommended post-publish process

### 1. Open and authenticate the template

1. Open `arc_sql_estate_strategy.pbit` in Power BI Desktop.
2. When prompted for Azure Resource Graph, choose **Organizational account** and
   sign in to the tenant being assessed.
3. For every public web source, choose **Anonymous** authentication.
4. Set the privacy level to **Organizational** for Azure Resource Graph and all
   web sources.
5. Refresh in Desktop and confirm the report loads.
6. Save the report as a PBIX if required, then publish it to the target Fabric
   workspace.

### 2. Establish the Fabric cloud connections

1. In Fabric, open the workspace.
2. Locate the published semantic model.
3. Select **More options (...)** > **Settings**.
4. Expand **Gateway and cloud connections**.
5. Confirm each data-source reference is mapped to a cloud connection.
6. For the `AzureResourceGraph` source, select or create a connection using:
   - Authentication: **OAuth2**
   - Account: an identity with access to the required subscriptions
   - Privacy level: **Organizational**
7. For each HTTPS web source, select or create a connection using:
   - Authentication: **Anonymous**
   - Privacy level: **Organizational**
8. Do not enable a personal, on-premises, or VNet gateway. A disabled or grey
   gateway control is expected when all sources use cloud connections.

Connection display names do not need to match the source URL. Fabric binds
sources using the internal connection type and exact path, so verify every
reference rather than relying on its friendly name.

### 3. Apply and verify privacy settings automatically

The operator must first create or authorize the connections because OAuth
credentials cannot be distributed in a public template. After that one-time
authentication, run:

```powershell
az login --tenant <tenant-id>

.\powerbi\tools\configure-fabric-refresh.ps1 `
  -WorkspaceName "<workspace-name>" `
  -SemanticModelName "<semantic-model-name>" `
  -TriggerRefresh
```

The script:

1. Resolves the workspace and semantic model without hardcoded IDs.
2. Confirms every semantic-model source is bound.
3. Sets all web connections to `Organizational` privacy without changing their
   anonymous credentials, and verifies Azure Resource Graph is already
   `Organizational`.
4. Confirms web connections use `Anonymous` and Azure Resource Graph uses
   `OAuth2`.
5. Confirms Power BI does not classify the model as gateway-required.
6. Optionally starts a full refresh.

Use IDs if duplicate names exist:

```powershell
.\powerbi\tools\configure-fabric-refresh.ps1 `
  -WorkspaceId "<workspace-guid>" `
  -SemanticModelId "<semantic-model-guid>" `
  -TriggerRefresh
```

### 4. Enable scheduled refresh

1. Return to the semantic model **Settings** page.
2. Expand **Refresh** or **Scheduled refresh**.
3. Turn the schedule on.
4. Choose the required frequency, time zone, and refresh times.
5. Save the schedule.
6. Run **Refresh now** once and inspect **Refresh history**.

The refresh is correctly configured when:

- The refresh completes without `DMTS_PersonalGatewayIsNeeded`.
- No privacy-firewall error is reported.
- No connection shows `Not configured correctly`.
- The semantic model reports that an on-premises gateway is not required.

## Manual privacy fallback

If the automation cannot be used:

1. Open Fabric **Settings** > **Manage connections and gateways**.
2. Open each connection used by the semantic model.
3. Select **Edit credentials** or **Settings**, depending on the portal view.
4. Keep public web credentials set to **Anonymous**.
5. Keep Azure Resource Graph credentials set to **OAuth2**.
6. Set **Privacy level** to **Organizational**.
7. Save the connection.
8. Repeat for all semantic-model connections.
9. Return to **Gateway and cloud connections** and confirm all references remain
   mapped.
10. Run **Refresh now** and inspect **Refresh history**.

## Troubleshooting

| Symptom | Resolution |
|---|---|
| `DMTS_PersonalGatewayIsNeeded` | The old model was published or another query uses a browser/local connector. Publish the current PBIT and confirm no gateway is enabled. |
| Privacy levels cannot be combined | Set both Azure Resource Graph and every web connection to `Organizational`; keep web authentication `Anonymous`. |
| Credentials are greyed out in semantic-model settings | This is normal when credentials are owned by Fabric connection objects. Edit them under **Manage connections and gateways**. |
| Only Personal Cloud is offered | This is valid for these cloud sources. Select or create the exact-path Personal Cloud connection; do not create a gateway. |
| A source is unbound | Create or authorize its cloud connection, then map it under **Gateway and cloud connections**. |
| SQL patch table is empty | Confirm the current template is published and the Microsoft Learn connection allows anonymous HTTPS access. |
