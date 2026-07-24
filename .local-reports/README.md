# Local reports (generated output — not committed)

This folder is the **standard output location** for the Arc-enabled SQL Server estate analysis skill.
Every agent run writes its deliverables here, under a per-run subfolder named
`<yyyyMMdd-HHmmss>[-<estate-label>]/`, for example:

```
.local-reports/
  20260724-081722-arcbox/
    estate-report.md              # rendered two-part report (always written)
    estate-report.html            # branded HTML (only if export requested)
    estate-report.pdf             # PDF (only if export requested)
    machine-patch-exposure.csv    # dashboard-ready security exposure outputs
    missing-patch-detail.csv
    patch-cve-mappings.csv
    cve-enrichment.csv
    exec-summary.json
    dmv-downgrade-summary.csv      # Enterprise downgrade audit (when run)
    migrate-sql-summary.csv        # optional Azure Migrate enrichment (when available)
```

## Why this folder is gitignored

Estate outputs contain **tenant-identifying data** — machine names, subscription IDs,
CVE exposure, licensing detail. This must never be committed. `.gitignore` therefore
ignores everything in this folder **except this README**:

```gitignore
/.local-reports/*
!/.local-reports/README.md
```

The README keeps the folder present on clone so the skill always has somewhere to write;
its generated contents stay local to the machine that produced them.

## Retention

Runs accumulate here. Delete old run subfolders manually when no longer needed —
they are never cleaned up automatically and are never pushed to the repository.
