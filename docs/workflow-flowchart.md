# Workflow Flowchart

This document describes the step-by-step execution flow of the Arc SQL Estate Analyser.

---

## High-Level Flow

```
┌─────────────┐
│ User Prompt │
│ (tenant ID) │
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 1. RESOLVE TENANT SUBSCRIPTIONS      │
│    • List all subscriptions in tenant │
│    • Present to user for confirmation │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│ 2. USER CONFIRMS SCOPE               │
│    • All subscriptions               │
│    • Selected subscriptions           │
│    • Single subscription              │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│ 3. SCOPE VALIDATION QUERY            │
│    • Query Resource Graph for         │
│      Arc SQL resources                │
│    • Verify subscriptionId in results │
│      matches confirmed scope          │
└──────────────┬───────────────────────┘
               │
          ┌────┴────┐
          │ Match?  │
          └────┬────┘
         Yes   │    No
       ┌───────┴───────┐
       │               │
       ▼               ▼
┌─────────────┐  ┌────────────────────────────┐
│ Continue    │  │ FALLBACK: Retry via CLI     │
└──────┬──────┘  │ • az graph query with       │
       │         │   explicit --subscriptions   │
       │         └─────────────┬──────────────┘
       │                       │
       │                  ┌────┴────┐
       │                  │ Match?  │
       │                  └────┬────┘
       │                 Yes   │    No
       │               ┌───────┴───────┐
       │               │               │
       │               ▼               ▼
       │         ┌───────────┐   ┌─────────────────────┐
       │         │ Continue  │   │ STOP: Scope error   │
       │         └─────┬─────┘   │ • Report mismatch   │
       │               │         │ • Offer file upload  │
       │               │         └─────────────────────┘
       ▼               ▼
┌──────────────────────────────────────┐
│ 4. DATA ACQUISITION                  │
│    • SQL instances (version, edition,│
│      licensing, vCores, status)      │
│    • Databases (size, recovery,      │
│      backup, encryption, state)      │
│    • Host machines (OS, cores, RAM,  │
│      hypervisor)                     │
│    • Migration assessments (MI/VM    │
│      readiness, SKU recommendations) │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│ 5. IDENTIFY ENTERPRISE INSTANCES     │
│    • Filter instances with           │
│      edition = Enterprise            │
│    • Filter service type = Engine    │
│    • Enumerate user databases        │
│      (database_id > 4, online)       │
└──────────────┬───────────────────────┘
               │
          ┌────┴─────────────┐
          │ Enterprise found? │
          └────┬─────────────┘
         Yes   │    No
       ┌───────┴───────┐
       │               │
       ▼               ▼
┌─────────────────┐  ┌──────────────────────┐
│ 6. DOWNGRADE    │  │ Skip to Analysis     │
│    AUDIT        │  └──────────┬───────────┘
└────────┬────────┘             │
         │                      │
         ▼                      │
┌──────────────────────────────────────┐
│ FOR EACH DATABASE / INSTANCE          │
│ (sequential per host):                │
│                                      │
│  ┌────────────────────────────────┐  │
│  │ Arc Run Command:               │  │
│  │ Invoke-Sqlcmd executes:        │  │
│  │ 1) DMV query per user DB       │  │
│  │ 2) Runtime checks per instance │  │
│  │    - Always On AG              │  │
│  │    - Resource Governor         │  │
│  │    - Partitioned tables        │  │
│  │    - ONLINE=ON job steps       │  │
│  └───────────────┬────────────────┘  │
│                  │                    │
│         ┌────────┴────────┐          │
│         │    Result?      │          │
│         └────────┬────────┘          │
│     ┌────────────┼────────────┐      │
│     ▼            ▼            ▼      │
│  ┌────────┐ ┌─────────┐ ┌───────┐   │
│  │Features│ │No rows  │ │Failed │   │
│  │returned│ │(clean)  │ │       │   │
│  └───┬────┘ └────┬────┘ └───┬───┘   │
│      │           │           │       │
│      ▼           ▼           ▼       │
│  Record:     Record:     Record:     │
│  featureName featureName featureName │
│  = <name>   = null      = null       │
│  status     status      status       │
│  = Succeeded= Succeeded = Failed     │
│  error      error       error        │
│  = null     = null      = <message>  │
│                                      │
└──────────────────┬───────────────────┘
                   │
                   ▼
┌──────────────────────────────────────┐
│ 7. CLASSIFY DOWNGRADE READINESS      │
│                                      │
│  GREEN  = DMV clean + runtime valid  │
│  AMBER  = DMV clean + runtime TBD   │
│  RED    = Features found / failed    │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│ 8. ANALYSIS & REPORT GENERATION      │
│                                      │
│  1. Executive Summary                │
│  2. Estate Summary                   │
│  3. Key Optimisation Opportunities   │
│  4. Enterprise Downgrade Audit       │
│  5. Azure Target Recommendations     │
│  6. Risks and Blockers               │
│  7. Data Gaps / Follow-up Questions  │
└──────────────────────────────────────┘
```

---

## Decision Points Summary

| Step | Decision | Outcome if No |
|------|----------|---------------|
| Scope validation | Do returned resources match requested tenant? | Fallback to CLI |
| CLI fallback | Do CLI results match requested tenant? | **STOP** — report error, offer file upload |
| Enterprise detection | Any Enterprise Engine instances? | Skip downgrade audit |
| Run Command execution | Did execution succeed? | Record as Failed, confidence = Low |
| Combined persisted + runtime results | Are persisted and runtime checks both clean? | AMBER/RED depending on blockers or incomplete runtime checks |

---

## Execution Constraints

- **Sequential per machine:** Only one Run Command is executed at a time per Arc machine to avoid HCRP500 conflicts.
- **Older hosts:** The `-TrustServerCertificate` parameter is omitted on hosts with older `SqlServer` PowerShell module versions (e.g., SQL Server 2016 hosts).
- **Single-line scripts:** Run Command scripts are kept as simple single-command patterns to avoid multi-line parsing issues across different handler versions.
- **Cleanup:** Run Command resources are deleted after results are retrieved to avoid namespace conflicts on subsequent runs.
