# Copilot Instructions

## What this repo is

A GitHub Copilot **skill** and **custom agent** for analysing Arc-enabled SQL Server estates and recommending Azure optimisation/migration pathways. There is no application code, build system, or test suite — the repo contains only Markdown-based agent and skill definitions.

## Architecture

```
.github/
  skills/arc-sql-estate-analysis/
    SKILL.md              ← Skill definition (triggers, workflow, guardrails)
    references/
      output-template.md  ← Required output structure for analysis results
  agents/
    sql-estate-architect.agent.md  ← Custom agent persona and instructions
docs/
  example-prompts.md      ← Sample user prompts for testing the skill
```

- The **skill** (`SKILL.md`) defines *when* and *how* to perform an estate analysis. It is invoked by the agent or directly by a user prompt.
- The **agent** (`sql-estate-architect.agent.md`) is a thin persona wrapper that delegates analysis work to the skill and enforces output ordering.
- The **output template** is the canonical section structure that all analysis output must follow.

## Key conventions

- Output must always follow the five-section order defined in both `SKILL.md` and the output template: Estate summary → Key optimisation opportunities → Azure target recommendations → Risks and blockers → Data gaps / follow-up questions.
- Findings must be evidence-based. Never claim savings, utilisation, or migration suitability without supporting source data. Missing data goes in the "Data gaps" section.
- The agent uses `claude-sonnet-4.5` as its model (set in agent frontmatter).
- Keep wording concise and customer-ready; this output is intended for direct customer consumption.

## Editing guidelines

- When modifying the skill workflow steps, keep the numbered list in `SKILL.md` in sync with the output template sections.
- Trigger phrases (the "When to use this skill" list in `SKILL.md`) should stay aligned with the `description` field in the YAML frontmatter.
- If you add new Azure target options, update both the skill workflow step 6 and the output template.
