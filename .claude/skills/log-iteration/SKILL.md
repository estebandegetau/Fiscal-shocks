---
name: log-iteration
description: Log a codebook development iteration with auto-gathered metrics, user interpretation, and decision. Creates an auditable YAML trail in prompts/iterations/.
user-invocable: true
---

# Log Iteration Skill

Record a codebook development iteration: what changed, what the pipeline produced, what it means, and what to do next. Each entry captures enough context to reconstruct any past state (`git show <hash>:prompts/<codebook>.yml`).

## When to Use

Invoke `/log-iteration` after running a pipeline stage (S1, S2, or S3) for any codebook (C1-C4) and reviewing the results. Typical workflow:

1. Edit the codebook YAML
2. Run `tar_make(<target>)`
3. Invoke `/log-iteration` to record the iteration

## Procedure

### Step 1: Ask the user

Ask the user for three things (use AskUserQuestion or conversational prompts):

1. **Codebook**: Which codebook? (`c1`, `c2`, `c3`, or `c4`)
2. **Stage**: Which stage was run? (`s1`, `s2`, or `s3`)
3. **Changes**: What changes were made to the codebook since the last iteration? (Free text. For the first iteration, say "Initial codebook (v<version>). No changes from S0 draft.")

### Step 2: Auto-gather metadata

Collect these automatically (do NOT ask the user):

| Field | How to get it |
|-------|---------------|
| `codebook_version` | Read the codebook YAML file and extract `codebook.version` |
| `git_commit` | Run `git rev-parse --short HEAD` |
| `date` | Today's date (YYYY-MM-DD) |
| `iteration` | Read existing log file, count entries, add 1. If file doesn't exist, iteration = 1 |

### Step 3: Read pipeline results

Use Bash to read the target results:

```bash
Rscript -e 'library(targets); cat(jsonlite::toJSON(tar_read(<target_name>), auto_unbox = TRUE, digits = 4, pretty = TRUE))'
```

**Codebook file mapping:**

| Codebook | YAML file |
|----------|-----------|
| `c1` | `prompts/c1_measure_id.yml` |
| `c2` | `prompts/c2_motivation.yml` |
| `c3` | `prompts/c3_timing.yml` |
| `c4` | `prompts/c4_magnitude.yml` |

**Target name mapping:**

| Codebook + Stage | Target name |
|------------------|-------------|
| `c1` + `s1` | `c1_s1_results` |
| `c1` + `s2` | `c1_s2_eval` |
| `c1` + `s3` | `c1_s3_results` |
| `c2` + `s1` | `c2_s1_results` |
| `c2` + `s2` | `c2_s2_eval` |
| `c2` + `s3` | `c2_s3_results` |
| `c3` + `s1` | `c3_s1_results` |
| `c3` + `s2` | `c3_s2_eval` |
| `c3` + `s3` | `c3_s3_results` |
| `c4` + `s1` | `c4_s1_results` |
| `c4` + `s2` | `c4_s2_eval` |
| `c4` + `s3` | `c4_s3_results` |

If the target does not exist (error from `tar_read`), tell the user and ask if they want to proceed with manual metric entry or abort.

### Step 4: Extract stage-specific metrics

#### S1 metrics (from `<codebook>_s1_results`)

The result is a list with `overall_pass`, `model`, and `summary` (a tibble with columns: `test`, `pass`, `metric`, `threshold`, `comparison`).

Extract `model` from the result. Format metrics as:

```yaml
results:
  overall_pass: true
  metrics:
    - test: "I_legal_outputs"
      value: 1.0000
      threshold: 1.0000
      pass: true
    - test: "II_definition_recovery"
      value: 1.0000
      threshold: 1.0000
      pass: true
    - test: "III_example_recovery"
      value: 1.0000
      threshold: 1.0000
      pass: true
    - test: "IV_order_invariance"
      value: 0.0000
      threshold: 0.0500
      pass: true
```

Note: For Test IV (order invariance), the comparison is `<` (lower is better). For all others, the comparison is `>=` (higher is better).

#### S2 metrics (from `<codebook>_s2_eval`)

The result is a list with named metric fields and `*_ci` confidence interval vectors. Extract metrics according to codebook type:

**C1 primary metrics:**

| Metric | Field | Target |
|--------|-------|--------|
| `combined_recall` | `combined_recall` | >= 0.90 |
| `tier1_recall` | `tier1_recall` | >= 0.95 |
| `precision` | `precision` | >= 0.70 |

**C2 primary metrics:**

| Metric | Field | Target |
|--------|-------|--------|
| `weighted_f1` | `f1` | >= 0.70 |
| `exogenous_precision` | `precision` | >= 0.85 |

**C3 primary metrics:**

| Metric | Field | Target |
|--------|-------|--------|
| `exact_quarter` | `exact_quarter` | >= 0.85 |
| `plus_minus_1_quarter` | `plus_minus_1_quarter` | >= 0.95 |

**C4 primary metrics:**

| Metric | Field | Target |
|--------|-------|--------|
| `mape` | `mape` | <= 0.30 |
| `sign_accuracy` | `sign_accuracy` | >= 0.95 |

Also include secondary metrics when available (f1, accuracy, specificity for C1). Format with bootstrap CIs:

```yaml
results:
  overall_pass: false
  metrics:
    - metric: "combined_recall"
      value: 0.8500
      ci_lower: 0.7800
      ci_upper: 0.9100
      target: 0.9000
      pass: false
    - metric: "tier1_recall"
      value: 0.9200
      ci_lower: 0.8600
      ci_upper: 0.9700
      target: 0.9500
      pass: false
```

Set `overall_pass` to `true` only if ALL primary metrics meet their targets.

Extract model from the S2 raw results target (`<codebook>_s2_results`) if available, or ask the user.

#### S3 metrics (from `<codebook>_s3_results`)

The result is a list with `test_v`, `test_vi`, `test_vii`, `ablation`, `error_categories`, and `model`.

Format as:

```yaml
results:
  metrics:
    - test: "V_exclusion_criteria"
      baseline_accuracy: 0.8500
      max_accuracy_drop: 0.1200
      critical_component: "FISCAL_MEASURE.clarification_3"
    - test: "VI_generic_labels"
      original_accuracy: 0.8500
      generic_accuracy: 0.7200
      change_rate: 0.1800
    - test: "VII_swapped_labels"
      follows_definitions_rate: 0.8000
      follows_names_rate: 0.1500
      interpretation: "Model relies primarily on definitions"
  error_distribution:
    - category: "E_semantics_reasoning"
      count: 12
      pct: 60.0
    - category: "D_non_compliance"
      count: 5
      pct: 25.0
  top_ablation_drops:
    - component: "FISCAL_MEASURE.clarification_3"
      drop: 0.1200
    - component: "NOT_FISCAL_MEASURE.negative_clarification_1"
      drop: 0.0800
```

### Step 5: Present results and ask for interpretation

Show the user a formatted summary of the results. Then ask for:

1. **Interpretation**: What do these results mean? Why do they look this way? (Free text, will be stored as a YAML block scalar)
2. **Decision**: What to do next? (e.g., "Proceed to S2", "Revise clarification 3 to handle X", "Add negative example for Y")

### Step 6: Append to iteration log

**Directory**: `prompts/iterations/`
**File**: `prompts/iterations/<codebook>.yml` (e.g., `prompts/iterations/c1.yml`)

If the directory doesn't exist, create it. If the file doesn't exist, create it with:

```yaml
# Iteration log for <CODEBOOK_NAME>
# Each entry records a pipeline run: what changed, what happened, what to do next.
# Retrieve any past codebook version: git show <git_commit>:prompts/<codebook_file>

iterations: []
```

Then append the new entry to the `iterations` list.

### YAML formatting rules

1. **Block scalars** (`>`) for multi-line text fields: `changes`, `interpretation`, `decision`
2. **4 decimal places** for all float values (e.g., `0.8500`, not `0.85`)
3. **Short git hash** (7 characters)
4. **ISO date** format (YYYY-MM-DD)
5. **No trailing whitespace** in block scalars
6. Use `true`/`false` for booleans (lowercase)

### Complete entry schema

```yaml
- iteration: 1
  codebook_version: "0.1.0"
  date: "2026-02-20"
  git_commit: "0ecc0db"
  model: "claude-haiku-4-5-20251001"
  stage: "s1"
  changes: >
    Initial codebook (v0.1.0). No changes from S0 draft.
  results:
    overall_pass: true
    metrics:
      - test: "I_legal_outputs"
        value: 1.0000
        threshold: 1.0000
        pass: true
  interpretation: >
    All S1 behavioral tests pass. Ready to proceed to S2.
  decision: >
    Proceed to S2 LOOCV evaluation without codebook changes.
```

## Error Handling

- **Target doesn't exist**: Tell the user which target is missing and suggest running `tar_make(<target>)`. Offer to proceed with manual metrics or abort.
- **Codebook file doesn't exist**: Only C1 exists currently. For C2-C4, tell the user the codebook hasn't been created yet and abort.
- **JSON parsing failure**: If `tar_read()` output can't be parsed, show the raw output and ask the user to provide key metrics manually.
- **Dirty git state**: Warn the user if `git status --porcelain` shows uncommitted changes, since the logged commit hash won't fully reproduce the codebook. Suggest committing first, but don't block.

## Retrieving Past Iterations

The log stores the git commit hash per entry. To retrieve a past codebook version:

```bash
git show <hash>:prompts/c1_measure_id.yml
```

Full reproduction of past results requires checking out the commit and re-running `tar_make()`. Summary metrics in the log provide quick comparison without reproduction.
