# CLAUDE.md

This file is Claude's project-specific operating instructions. Read `COMPANION.md` for the permanent principles and full architecture. The sections below override or extend `COMPANION.md` for this project.

---

## Project Overview

<!-- POPULATE: Fill in the following fields after running /setup-project -->

**Title**: <!-- POPULATE: Project title -->
**Authors**: <!-- POPULATE: Author names -->
**Affiliation**: <!-- POPULATE: Institution -->

### Research Problem

<!-- POPULATE: 2-3 sentences. What gap does this project address? Why has it been unsolved until now? -->

### Our Solution

<!-- POPULATE: Describe the LLM-assisted approach. What methodological frameworks does it use? What does the pipeline produce? -->

### Key Innovation

<!-- POPULATE: What is the core methodological contribution? What can this project do that was not possible before? -->

### Research Contribution

<!-- POPULATE: Bullet list of specific contributions. Distinguish methodological from empirical contributions. -->

### Measurement Instruments

<!-- POPULATE: List each instrument (e.g., C1, C2) with:
- Short name and description
- Output type (classification, extraction, estimation)
- Sequencing dependencies (if C2 depends on C1 output, note that) -->

### Validation Pipeline

<!-- POPULATE: Describe the validation stages (e.g., S0-S3 if using H&K framework):
- Stage name and description
- What constitutes passing -->

### Success Criteria

<!-- POPULATE: Per-instrument success criteria. Format as:
- Instrument name: Metric ≥ target (diagnostic benchmark vs. hard gate) -->

### Data and Scope

<!-- POPULATE: Primary data sources, labeled example count, geographic/temporal scope, any known constraints -->

### Strategic Framing

<!-- POPULATE: What this project IS and IS NOT. Prevents scope creep and misrepresentation. -->

### Current Status

<!-- Tier 1: Claude updates this section via /doc-sync -->
<!-- POPULATE: Initial status entries per instrument and phase -->

---

## Development Commands

### Pipeline

<!-- POPULATE: Commands for your pipeline tool (e.g., targets, DVC, Snakemake) -->

```r
# Example for {targets}
tar_make()           # Run pipeline
tar_read(target)     # Read output
tar_outdated()       # Check what needs updating
tar_visnetwork()     # Visualize dependencies
```

### Documentation

<!-- POPULATE: Commands for building docs -->

```bash
# Example for Quarto
quarto render notebooks/my_notebook.qmd
```

---

## Technology Stack

### Languages and Packages

<!-- POPULATE: List key packages per language -->

### Valid Model IDs

<!-- POPULATE: List your validated model IDs here. Convention 3 requires checking against this list before writing any model parameter.

Example:
- Production: `claude-haiku-4-5-20251001`
- Exploration: `claude-sonnet-4-6` (or cheaper alternatives)
-->

### Data Sources

<!-- POPULATE: Where does primary data come from? URLs, archives, APIs? -->

---

## Phase Structure

<!-- POPULATE (optional): If your project has multiple phases, describe them:
- Phase 0: ...
- Phase 1: ...
- Phase N: ...

Delete this section if your project does not use phases. -->

---

## Research Companion Principles

The five principles governing Claude's role in this project. See `COMPANION.md` for full rationale.

1. **Human confers meaning.** Claude pattern-matches against instrument definitions but does not understand what the classification means for causal identification or external validity.
2. **Delegate instrumental, own the core.** Pipeline plumbing and documentation sync are fully delegable. Instrument design, success criteria, and error interpretation are human-owned.
3. **Credibility tracks involvement.** The human must have lived through the iteration history to defend decisions at peer review.
4. **Commits belong to humans.** Claude analyzes and proposes; the human decides and records the rationale.
5. **Error recoverability heuristic.** AI owns tasks where errors are recoverable. Humans own tasks where errors compound silently.

---

## Workflow Conventions

These 10 rules govern how Claude operates in this project. Verbatim from `COMPANION.md` — do not modify without updating both files.

1. **Plan-first mode.** When asked to diagnose, investigate, or propose, present findings and wait. Do NOT implement changes or run code unless explicitly told to.

2. **Root cause first.** When something fails, identify the root cause before proposing a fix. Do not patch symptoms.

3. **Model ID validation.** Before writing any model parameter, verify against the "Valid Model IDs" list above. Flag any legacy IDs.
   <!-- POPULATE: List your validated model IDs in the Technology Stack section above -->

4. **Prefer existing files.** Search with Glob/Grep before creating new files.

5. **No autonomous API calls.** Never run the pipeline on API-calling targets without explicit human approval. Read-only operations are always safe.

6. **Commit before pipeline runs.** Ensure no uncommitted changes to instrument files or pipeline functions before running.

7. **One change at a time.** Change one instrument component per iteration.

8. **Pipeline data validation.** After a pipeline run completes, verify result shape before proceeding.

9. **Quarto render safety.** Always render specific files, never the full project.

10. **Strategy reconciliation.** After stage gate crossings or when 3+ unresolved deltas accumulate in `docs/deltas.md`, run `/strategy-sync`.

---

## Claude Code Agents

<!-- POPULATE: List your project-specific agents following the taxonomy in COMPANION.md:

Read-only agents (Read, Grep, Glob only):
- <agent-name>: <role>, <model>

Write-capable agents:
- <agent-name>: <role>, <model>

See COMPANION.md Part 2 for agent taxonomy principles. -->
