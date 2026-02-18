---
name: doc-sync
description: Keep project documentation in sync with implementation state. Apply after completing significant implementation work (new R functions, codebook changes, pipeline target updates, notebook creation/deletion). Also invocable via /doc-sync for a full documentation sync pass.
user-invocable: true
---

# Documentation Sync Skill

This skill defines how to keep project documentation accurate as the codebase evolves. It implements a three-tier system: auto-update machine context, log deltas for human-authored specifications, and ignore stable reference docs.

## When to Apply

Run a doc-sync pass after any of these events:

- Creating or modifying R functions in `R/`
- Creating or modifying codebook YAML files in `prompts/`
- Adding, removing, or modifying targets in `_targets.R`
- Creating, deleting, or substantially updating notebooks in `notebooks/`
- Completing an H&K stage gate (S0, S1, S2, S3) for any codebook
- Changing project phase status (e.g., Phase 0 complete, Phase 2 started)

Do NOT run doc-sync for:

- Minor edits (typo fixes, formatting changes, comment updates)
- Reading or exploring files without making changes
- Changes only to `docs/` files themselves (avoid circular updates)

## Tier 1: Auto-Update (Machine Context)

These files exist to give Claude Code accurate project state. Update them directly when implementation changes make them stale.

### Files

| File | Key sections to keep current |
|------|------------------------------|
| `CLAUDE.md` (root) | "Current Status" (C1-C4 stage progress), "Key Directories" (if new dirs added), "Architecture > Pipeline" (if new targets added) |
| `docs/phase_0/CLAUDE.md` | "Status", "Files to Create" (mark created files), "Targets Pipeline Integration" |
| `docs/phase_1/CLAUDE.md` | "Status", "Open Questions" (as resolved) |
| `notebooks/CLAUDE.md` | "Active Notebooks" (add/remove entries), "Archived Notebooks" (move deleted ones here) |
| `docs/phase_1/README.md` | "Next Steps", status fields |
| `docs/phase_1/expert_review_protocol.md` | Procedural adjustments as Malaysia work begins |

### Update rules

1. **Read the file first.** Never update a file you haven't read in this session.
2. **Change only stale facts.** Do not rewrite prose, add commentary, or "improve" wording.
3. **Preserve structure.** Keep the existing heading hierarchy, formatting, and organization.
4. **Be minimal.** Update the specific lines that are stale. A status changing from "Not started" to "S0 complete, S1 in progress" is a one-line edit, not a paragraph rewrite.
5. **For `notebooks/CLAUDE.md`**: When a notebook is created, add an entry following the existing format (Purpose, Key tests and decisions, Decision). When a notebook is deleted, move its entry to "Archived Notebooks" with a note on why.

### Example: Updating root CLAUDE.md status

```markdown
<!-- Before -->
- **C1 (Measure ID)**: Not started

<!-- After -->
- **C1 (Measure ID)**: S1 behavioral tests complete; S2 LOOCV in progress
```

### Example: Updating notebooks/CLAUDE.md

```markdown
<!-- When a notebook is deleted, move to Archived section -->
### Archived Notebooks
- `review_model_a.qmd` -- Legacy Model A review (superseded by C1-C4 framework)
```

## Tier 2: Delta Log (Human-Authored Specifications)

These files represent deliberate research design decisions. Never edit them directly. Instead, log discoveries that may require the human to update them.

### Files (never auto-edit)

| File | What it specifies |
|------|-------------------|
| `docs/strategy.md` | Methodology, codebook definitions, success criteria, implementation blueprint |
| `docs/proposal.qmd` | Research scope, questions, empirical plan, timelines |
| `docs/two_pager.qmd` | Stakeholder framing, project outputs, timelines |
| `docs/phase_1/malaysia_strategy.md` | Malaysia strategic decisions, four options, recommended path |

### Delta log location

`docs/deltas.md`

### When to log a delta

Log an entry when implementation reveals any of these:

- A specification is wrong or incomplete (e.g., "strategy.md says X but we found Y")
- Success criteria need adjusting based on actual results
- New constraints discovered that affect the strategy
- A phase status change that the human should reflect in strategy docs
- A checklist item in a specification doc has been completed
- An assumption was validated or invalidated

### Delta log format

Each entry is a short, structured block. Most recent entries go at the top.

```markdown
## YYYY-MM-DD: [Short title]

**Type:** [status-change | correction | new-constraint | validated | invalidated]
**Affects:** `docs/strategy.md` > Section Name > Subsection
**Detail:** One to three sentences describing what was discovered or what changed.
**Suggested edit:** The specific text change, if obvious. Otherwise "Review needed."
```

### Example delta entries

```markdown
## 2026-02-18: C1 codebook S0 complete

**Type:** status-change
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 Implementation
**Detail:** C1 codebook YAML (`prompts/c1_measure_id.yml`) passed S0 validation.
Behavioral test functions implemented in `R/behavioral_tests.R`. S1 tests ready to run.
**Suggested edit:** Update Step 2 status from "⬜ Pending" to "✅ Complete".
```

```markdown
## 2026-02-15: Training data count confirmed at 44 acts

**Type:** validated
**Affects:** `docs/strategy.md` > Data Constraints
**Detail:** `data_overview.qmd` confirms 44 aligned acts after Jaro-Winkler matching
at threshold 0.85. The 44-act constraint documented in strategy.md is correct.
**Suggested edit:** None needed (already accurate).
```

### Rules for delta logging

1. **Be factual.** State what happened, not what you think should happen to the strategy.
2. **Be specific.** Point to the exact section and subsection affected.
3. **Don't accumulate noise.** If a discovery confirms the strategy is correct, log it as "validated" but don't suggest edits.
4. **One entry per discovery.** Don't batch unrelated changes into one entry.

## Tier 3: Ignore (Stable / Low Priority)

These files are either stable reference documents, generated artifacts, or infrastructure docs that rarely need updates. Do not update them during a doc-sync pass.

### Files

| File | Why ignore |
|------|-----------|
| `docs/literature_review.md` | Stable summary of published papers |
| `docs/methods/*.md` | Faithful summaries of R&R and H&K papers |
| `docs/articles/*.pdf` | Published papers (immutable) |
| `docs/_metadata.yml` | Quarto config (human format decisions) |
| `slides/CLAUDE.md` | Stable presentation style guide |
| `docs/phase_0/COST_ESTIMATES_REVISED.md` | Legacy cost estimates, served its purpose |
| `docs/phase_0/DEPLOYMENT_OPTIONS.md` | Situational infrastructure doc |
| `docs/phase_0/lambda_*.md` | Infrastructure guides, stable |
| `docs/phase_0/QUICKSTART_LAMBDA.md` | Quick-start guide, stable |
| `docs/phase_0/plan_phase0.html` + `*_files/` | Generated artifacts |
| `docs/strategy_files/` | Build artifacts |

**Exception:** If you discover a factual error in a Tier 3 reference doc (e.g., literature_review.md misquotes a paper), log a delta rather than editing directly.

## Running a Full Sync Pass (/doc-sync)

When invoked explicitly via `/doc-sync`, perform these steps in order:

### Step 1: Gather current state

- Read `git status` (untracked files, modifications, deletions)
- Read `_targets.R` for current target definitions
- Glob `R/*.R`, `prompts/*.yml`, `notebooks/*.qmd` for current files
- Note any completed pipeline runs (`tar_meta()` if available)

### Step 2: Check Tier 1 files for staleness

For each Tier 1 file:

1. Read the file
2. Compare stated facts against current state from Step 1
3. List specific lines that are stale

### Step 3: Update Tier 1 files

Apply minimal edits to fix stale facts. Follow the update rules above.

### Step 4: Check for Tier 2 deltas

Review whether any recent implementation work contradicts, extends, or validates the specification docs:

- Did any success criteria get tested? Log results.
- Did any "Files to Create" get created? Log status change.
- Were any assumptions validated or invalidated? Log finding.
- Did a phase or stage gate status change? Log transition.

### Step 5: Append to delta log

Add entries to `docs/deltas.md` following the format above. Do not modify existing entries.

### Step 6: Report

Summarize to the user:

- Which Tier 1 files were updated (and what changed)
- Which deltas were logged (and what they recommend)
- Any Tier 3 errors spotted (if applicable)

## Creating docs/deltas.md

If `docs/deltas.md` does not exist, create it with this header:

```markdown
# Strategy Delta Log

Bottom-up discoveries from implementation that may require updates to
human-authored specification documents (`docs/strategy.md`, `docs/proposal.qmd`,
`docs/two_pager.qmd`, `docs/phase_1/malaysia_strategy.md`).

Review this log periodically and incorporate relevant changes into the
source documents. Delete entries after they have been addressed.

---

```

New entries go immediately after the `---` separator.
