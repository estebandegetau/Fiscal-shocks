---
name: iterate
description: Full codebook iteration cycle — pre-flight, pipeline review, and iteration logging — with explicit human decision points between each phase. Composes /pre-flight, /review-iteration, and /log-iteration.
user-invocable: true
---

# Iterate Skill

Run the full codebook iteration cycle with human decision points at every phase boundary. This skill composes three existing skills into a single workflow while preserving all human decision authority.

## When to Use

Invoke `/iterate` when you've made codebook changes and want to run the full cycle: validate, execute, review, and log. This replaces manually invoking `/pre-flight`, `/review-iteration`, and `/log-iteration` in sequence.

## Critical Rule

**This skill never runs `tar_make()` or interprets results.** It prepares, presents, and records. The human decides and acts at every boundary.

## Procedure

### Phase A: Pre-Flight

Run the `/pre-flight` skill procedure (see `.claude/skills/pre-flight/SKILL.md`):

1. Ask which codebook and stage the user plans to run
2. Run all pre-flight checks (git status, target exists, dependencies, codebook validation, model/API key, cost estimate)
3. Present the checklist

#### PAUSE POINT 1

Stop and present:

```
Pre-flight complete. [N/N checks passed | N failures listed above]

When you're ready, run `tar_make(<target_name>)` in your R console.
Tell me when the pipeline has finished, and I'll review the results.
```

**Do NOT proceed until the user confirms the pipeline has completed.**

### Phase B: Review

After the user confirms pipeline completion, run the `/review-iteration` skill procedure (see `.claude/skills/review-iteration/SKILL.md`):

1. Read pipeline results from the target
2. Run stage-specific analysis (S1/S2/S3)
3. Present the structured diagnosis with metrics, error patterns, comparisons, and root cause hypothesis

#### PAUSE POINT 2

Stop and present:

```
Review complete. Before I log this iteration, I need your interpretation:

1. **What do these results mean?** (Why do they look this way?)
2. **What's the decision?** (What to do next — proceed, revise, investigate?)
```

**Do NOT proceed until the user provides their interpretation and decision.** These are human-owned judgments (Research Companion Principle 1: human confers meaning).

### Phase C: Log

After the user provides interpretation and decision, run the `/log-iteration` skill procedure (see `.claude/skills/log-iteration/SKILL.md`):

1. Auto-gather metadata (codebook version, git commit, date, iteration number)
2. Extract stage-specific metrics from pipeline results
3. Combine with user's interpretation and decision
4. Append entry to `prompts/iterations/<codebook>.yml`
5. Confirm the entry was written

#### PAUSE POINT 3

Stop and present:

```
Iteration [N] logged to prompts/iterations/<codebook>.yml

Next steps based on your decision:
- [Reflect user's stated decision back to them]
- [If codebook changes needed]: Edit the codebook, commit, then run `/iterate` again
- [If stage gate crossed]: Consider running `/doc-sync` to update project status
```

**Do NOT start the next iteration automatically.** The user decides when and whether to continue.

## What This Skill Does NOT Do

- **Does not run `tar_make()`** — the user runs the pipeline
- **Does not interpret results** — the user provides interpretation (Principle 1)
- **Does not decide next steps** — the user makes the decision (Principle 4)
- **Does not edit the codebook** — the user or codebook-developer agent does that
- **Does not skip phases** — all three phases run in order, every time

## Error Handling

- **Pre-flight fails**: Present failures and stop. Do not proceed to Phase B.
- **Pipeline not run**: If the user says "review results" without confirming pipeline completion, ask them to run `tar_make()` first.
- **Target missing**: If `tar_read()` fails in Phase B, tell the user which target is missing and suggest running the pipeline.
- **User skips interpretation**: Gently redirect — "I need your interpretation before logging. What do these results mean to you?"

## Composability

This skill delegates to:

- `.claude/skills/pre-flight/SKILL.md` (Phase A)
- `.claude/skills/review-iteration/SKILL.md` (Phase B)
- `.claude/skills/log-iteration/SKILL.md` (Phase C)

It does not duplicate their logic. If the sub-skill procedures change, this skill inherits those changes automatically.
