# Azure Monitor VM Insights dependency-monitoring prerequisites

These files are **consumer-run prerequisite templates** for collecting **application dependency
data** from Arc-enabled SQL hosts **before** an assessment. The analysis agent may reference them and
explain the 24-hour prerequisite, but it must **never** execute them itself.

## Guardrails

- Enable dependency monitoring **at least ~24 hours before** the engagement.
- Use a **dedicated Log Analytics workspace** for a one-off capture where possible so the first
  **5 GB/month free ingestion grant** usually makes the run effectively **$0** for small estates.
- Use **Map-only** collection: keep the DCR on `Microsoft-ServiceMap` only and leave
  `Microsoft-InsightsMetrics` / perf counters out.
- After the capture window, run the paired teardown script to remove DCR associations plus AMA /
  Dependency Agent extensions and optionally delete the dedicated workspace.

## Option 1 — Azure Policy path (best at scale)

Assign the built-in **Enable Azure Monitor for Hybrid/Arc VMs** VM Insights initiative (display name
may vary slightly by tenant) at the **resource-group** scope that contains the Arc machines.

1. Create or choose a **dedicated** Log Analytics workspace for the 24-hour capture.
2. Assign the built-in VM Insights initiative to the Arc-machine resource group.
3. Enable the parameter that turns on **processes and dependencies**.
4. If the built-in initiative in your tenant still emits `InsightsMetrics`, use the targeted Bicep
   path below for a strict Map-only capture; the policy path is the scale-first option.
5. Wait about **24 hours** for `VMConnection` / `VMProcess` / `VMComputer` / `VMBoundPort` data to
   accumulate, then run the assessment.
6. After the snapshot, remove the policy assignment or remediate it off, then run
   `teardown-map-only.ps1` to clean up extensions/associations if required.

## Option 2 — Targeted Bicep + `az` path (strict Map-only reference)

Use this path when you want an exact **Map-only** capture with no perf counters.

### Files

- `deploy-map-only.bicep` — creates a **dedicated Log Analytics workspace** plus a **Map-only DCR**
  that sends only the `Microsoft-ServiceMap` stream.
- `deploy-map-only.ps1` — deploys the Bicep template, installs AMA + Dependency Agent (with
  `enableAMA=true`, required so the Dependency Agent feeds the AMA-based `Microsoft-ServiceMap`
  pipeline instead of running in legacy mode) on the supplied Arc machines, and creates DCR
  associations.
- `teardown-map-only.ps1` — removes DCR associations plus AMA / Dependency Agent extensions and can
  optionally delete the DCR and workspace.

### Example deployment

```powershell
pwsh -File ./deploy-map-only.ps1 `
  -SubscriptionId <subscription-id> `
  -WorkspaceResourceGroup <resource-group> `
  -Location uksouth `
  -WorkspaceName arc-sql-dependency-la `
  -DcrName arc-sql-dependency-map-only `
  -MachineResourceIds @(
    '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.HybridCompute/machines/SQL01',
    '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.HybridCompute/machines/SQL02'
  )
```

The script deploys only the monitoring prerequisite. It does **not** run any assessment queries.
Once deployment completes, leave it in place for about **24 hours**, then run the dependency
analysis.

## Teardown after the snapshot

```powershell
pwsh -File ./teardown-map-only.ps1 `
  -SubscriptionId <subscription-id> `
  -WorkspaceResourceGroup <resource-group> `
  -WorkspaceName arc-sql-dependency-la `
  -DcrName arc-sql-dependency-map-only `
  -MachineResourceIds @(
    '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.HybridCompute/machines/SQL01',
    '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.HybridCompute/machines/SQL02'
  ) `
  -DeleteWorkspace
```

Use `-DeleteWorkspace` only when the workspace was created solely for this short capture.
