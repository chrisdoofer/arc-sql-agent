# Solution Architecture

## Overview

The Arc SQL Estate Analyser is a GitHub Copilot skill and custom agent that performs live assessment of Arc-enabled SQL Server estates and produces structured optimisation and migration recommendations for Azure.

It connects directly to an Azure tenant, queries live infrastructure data via Azure Resource Graph and Azure CLI, executes remote diagnostic commands via Arc Run Command, and produces a customer-ready analysis report.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        GitHub Copilot CLI                                │
│                                                                         │
│  ┌───────────────────────┐     ┌──────────────────────────────────┐    │
│  │  sql-estate-architect  │────▶│  arc-sql-estate-analysis skill   │    │
│  │  (Custom Agent)        │     │  (Analysis workflow engine)       │    │
│  └───────────────────────┘     └──────────────┬───────────────────┘    │
│                                                │                        │
└────────────────────────────────────────────────┼────────────────────────┘
                                                 │
                         ┌───────────────────────┼───────────────────────┐
                         │                       │                       │
                         ▼                       ▼                       ▼
              ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
              │  Azure Resource  │   │   Azure CLI      │   │  Arc Run Command │
              │  Graph (MCP)     │   │   (Fallback)     │   │  (Remote exec)   │
              └────────┬─────────┘   └────────┬─────────┘   └────────┬─────────┘
                       │                      │                       │
                       ▼                      ▼                       ▼
              ┌────────────────────────────────────────────────────────────────┐
              │                     Azure Tenant                               │
              │                                                                │
              │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
              │  │ Subscriptions│  │ Arc-enabled  │  │  Arc-enabled SQL     │ │
              │  │              │  │ Machines     │  │  Server Instances    │ │
              │  └──────────────┘  └──────────────┘  └──────────────────────┘ │
              │                                                                │
              └────────────────────────────────────────────────────────────────┘
```

---

## Component Roles

| Component | Role |
|-----------|------|
| **sql-estate-architect** (agent) | Thin persona wrapper. Delegates all analysis work to the skill. Enforces output ordering and evidence-based guardrails. |
| **arc-sql-estate-analysis** (skill) | Core analysis engine. Defines the 5-phase workflow: scope determination → validation → data acquisition → Enterprise downgrade audit → analysis and reporting. |
| **output-template.md** (reference) | Canonical output structure. All reports must follow this section order. |
| **Azure Resource Graph** | Primary data source for inventory (SQL instances, databases, machines). Queried via MCP tools and Azure CLI. |
| **Azure CLI** | Fallback data source when MCP scope validation fails. Also used for Arc Run Command execution. |
| **Arc Run Command** | Remote execution mechanism for running T-SQL diagnostic queries (e.g., `sys.dm_db_persisted_sku_features`) on Arc-enabled SQL hosts. |

---

## Data Flow

```
User prompt (tenant ID)
        │
        ▼
┌─────────────────────┐
│ Phase 1: Scope      │──▶ Resolve subscriptions in tenant
│ Determination       │──▶ User confirms subscription scope
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ Phase 2: Scope      │──▶ Validation query (Resource Graph)
│ Validation          │──▶ Verify returned resources match tenant/subscription
│                     │──▶ Fallback to CLI if scope mismatch detected
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ Phase 3: Data       │──▶ SQL instances (type, version, edition, licensing)
│ Acquisition         │──▶ Databases (size, recovery, backup, state)
│                     │──▶ Host machines (OS, cores, RAM, hypervisor)
│                     │──▶ Migration assessments (MI/VM readiness)
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ Phase 4: Enterprise │──▶ Identify Enterprise instances with user databases
│ Downgrade Audit     │──▶ Execute DMV via Arc Run Command per database
│                     │──▶ Capture structured results (pass/fail/features)
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ Phase 5: Analysis   │──▶ Synthesise findings into structured report
│ & Reporting         │──▶ Apply confidence levels and classifications
│                     │──▶ Produce customer-ready output
└─────────────────────┘
```

---

## File Structure

```
.github/
  agents/
    sql-estate-architect.agent.md    ← Agent persona and instructions
  skills/
    arc-sql-estate-analysis/
      SKILL.md                       ← Skill definition (triggers, workflow, guardrails)
      references/
        output-template.md           ← Required output structure
docs/
  architecture.md                    ← This document
  prerequisites.md                   ← Setup requirements and RBAC
  data-transparency.md               ← Data collection transparency
  workflow-flowchart.md              ← Step-by-step execution flow
  example-prompts.md                 ← Sample prompts for testing
  test-prompts.md                    ← Test scenarios
README.md                            ← Project overview
```

---

## Design Principles

1. **Evidence-based only** — Never claim savings, feature usage, or migration suitability without source data.
2. **Scope-safe** — Always validate tenant/subscription scope before analysis. Stop on mismatch.
3. **Transparent** — Clearly state what data was collected, from where, and which method was used.
4. **Cautious on downgrade** — Never recommend Enterprise → Standard without DMV audit evidence and runtime validation.
5. **Customer-ready** — Output is written for direct consumption by CIOs, IT Directors, and DBAs.
