---
name: arc-sql-estate-analysis
description: Analyse an Arc-enabled SQL Server estate and recommend Azure optimisation and migration pathways. Use this when asked to assess SQL versions, editions, sizing, utilisation patterns, licensing optimisation, and Azure target options.
license: MIT
---

# Purpose

Use this skill to assess an Arc-enabled SQL Server estate and produce a structured optimisation recommendation for Azure migration.

# When to use this skill

Use this skill when the user asks to:

- assess an Arc-enabled SQL Server estate
- identify SQL Server end-of-support or end-of-life exposure
- find optimisation opportunities before migrating to Azure
- recommend candidate Azure landing options for SQL workloads
- separate evidence-based findings from assumptions or missing data

# Analysis workflow

1. Confirm the dataset scope and what fields are available.
2. Summarise the estate by host, instance, version, and edition where possible.
3. Flag end-of-support or end-of-life exposure.
4. Identify edition-related optimisation opportunities such as possible Enterprise-to-Standard downgrade candidates.
5. Review available sizing or utilisation indicators and note obvious rightsizing opportunities.
6. Recommend candidate Azure target options, for example:
   - Azure SQL Managed Instance
   - SQL Server on Azure Virtual Machines
   - Arc-enabled SQL Server PAYG as an interim transition option
7. Separate confirmed findings from assumptions, unknowns, or missing fields.
8. Produce the final answer using the structure in `references/output-template.md`.

# Guardrails

- Keep findings evidence-based.
- Do not claim utilisation, savings, or migration suitability unless the source data supports it.
- If required fields are missing, state that plainly under Data gaps / follow-up questions.
- Prefer concise, customer-ready wording.

# Output requirements

Start with an **Executive Summary** at the top (3–5 concise bullet points for CIO/IT Director audience, highlighting key risks, optimisation opportunities, and Azure direction).

Then produce the sections below in order:

1. Estate summary
2. Key optimisation opportunities
3. Azure target recommendations
4. Risks and blockers
5. Data gaps / follow-up questions
