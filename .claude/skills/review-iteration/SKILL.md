---
name: review-iteration
description: Read-only structured analysis of pipeline results for human review. Diagnoses failures, maps error patterns, and suggests next steps without editing any files.
user-invocable: true
---

# Review Iteration Skill

Structured, read-only analysis of pipeline results. This fills the gap between results existing and the user understanding what happened.

**Key distinction from `/log-iteration`:**

- `/review-iteration` = **read and analyze** results (before deciding what to do)
- `/log-iteration` = **write a record** (after deciding what happened)

Typical workflow: `tar_make()` -> `/review-iteration` -> discuss with user -> `/log-iteration`

## When to Use

Invoke `/review-iteration` after a pipeline stage completes and before deciding what to change. Use when you want to understand:

- Which tests or metrics pass/fail and why
- What error patterns dominate
- Which codebook component is most likely responsible
- What to investigate or change next

## Procedure

### Step 1: Ask the user

Ask for two things:

1. **Codebook**: Which codebook? (`c1`, `c2`, `c3`, or `c4`)
2. **Stage**: Which stage was run? (`s1`, `s2`, or `s3`)

### Step 2: Auto-gather context (read-only)

Collect all relevant context without modifying anything:

| Source | How |
|--------|-----|
| Codebook YAML | Read `prompts/c<N>_<name>.yml` |
| Pipeline results | `Rscript -e 'library(targets); cat(jsonlite::toJSON(tar_read(<target>), auto_unbox = TRUE, digits = 4, pretty = TRUE))'` |
| Iteration log | Read `prompts/iterations/c<N>.yml` (if exists, for comparison with previous iterations) |
| Success criteria | Read `docs/strategy.md` and extract the relevant codebook's target metrics |
| Previous diagnosis | Check if `/review-iteration` was run before for this codebook+stage |

**Target name mapping:**

| Codebook + Stage | Target |
|------------------|--------|
| `c<N>` + `s1` | `c<N>_s1_results` |
| `c<N>` + `s2` | `c<N>_s2_eval` (metrics) + `c<N>_s2_results` (raw predictions) |
| `c<N>` + `s3` | `c<N>_s3_results` |

If `tar_read()` fails, tell the user and suggest running `tar_make(<target>)` first.

### Step 3: Stage-specific analysis

#### S1 Analysis (Behavioral Tests)

For each of the 4 tests (I-IV):

1. **Pass/fail status** with value vs. threshold
2. **For failures**: Show the specific inputs that failed
   - Test I: Which chunks returned invalid JSON? Show the raw response.
   - Test II: Which label definitions were misclassified? Show predicted vs. expected.
   - Test III: Which examples were misclassified? Show the example text and predicted vs. expected.
   - Test IV: Which chunk+ordering combinations changed? Show the prediction pairs.
3. **Root cause mapping**: Which codebook component (definition, clarification, example, output_instructions) is likely responsible for each failure?

#### S2 Analysis (Zero-Shot Evaluation)

1. **Primary metrics** vs. targets (from `docs/strategy.md`)
2. **Secondary metrics** for context
3. **Worst-performing acts**: Which acts have the lowest recall/accuracy? List the bottom 5-10.
4. **Error category distribution** using H&K categories:
   - A: Retrieval augmentation errors
   - B: Prompt construction errors
   - C: Formatting/output errors
   - D: Non-compliance (model ignores instructions)
   - E: Semantics/reasoning errors (model misunderstands domain)
   - F: Ambiguous ground truth
5. **Confusion patterns**: For classification tasks, which label pairs are most confused?
6. **Example deep-dives**: For the 3 worst errors, show:
   - Act name, chunk text (truncated), predicted label, true label
   - Model reasoning (if available in raw results)
   - Why this is likely wrong (analysis)

#### S3 Analysis (Error Analysis)

1. **Test V (Exclusion Criteria)**: Which negative clarifications, when removed, cause the largest accuracy drops? Rank by impact.
2. **Test VI (Generic Labels)**: How much does accuracy change with generic labels? High change = model relies on label names, not definitions.
3. **Test VII (Swapped Labels)**: Does the model follow definitions or label names? Quantify.
4. **Ablation ranking**: Which components have the largest accuracy drops when removed? Top 5.
5. **Iteration priority**: Based on ablation + error patterns, what's the highest-leverage change?

### Step 4: Present structured diagnosis

Use this format:

```
## Iteration Diagnosis: [Codebook] [Stage]

### What Passed / What Failed

| Test/Metric | Value | Target | Status |
|-------------|-------|--------|--------|
| [name] | [value] | [target] | PASS/FAIL |

### Error Patterns (if applicable)

- [N] errors in category [X]: [description]
- Example: Act "[name]", chunk [id]: predicted [X], true [Y]
  Model reasoning: "[quoted from raw results]"
  Likely cause: [analysis]

### Comparison with Previous Iteration (if applicable)

| Metric | Previous | Current | Change |
|--------|----------|---------|--------|
| [name] | [value] | [value] | +/-[delta] |

### Root Cause Hypothesis

[One sentence: what codebook component is most likely responsible for the dominant failure pattern]

### What I'd Investigate Next

1. [Ranked suggestion with rationale]
2. [Ranked suggestion with rationale]
3. [Ranked suggestion with rationale]

### Questions for You

- [Ambiguities requiring user domain judgment]
- [Design choices where multiple valid options exist]
```

### Step 5: Stop

Do NOT propose code changes, edit files, or modify the codebook. This skill is strictly read-only analysis.

End with: "To iterate on the codebook, you can edit it directly or start a `codebook-developer` session. When ready to record this iteration, run `/log-iteration`."
