---
name: pre-flight
description: Pre-pipeline validation checklist. Run before tar_make() to catch common issues. Read-only — does not run the pipeline.
user-invocable: true
---

# Pre-Flight Skill

Read-only checklist to run before `tar_make()` on API-calling targets. Catches configuration errors, dirty git state, and stale dependencies before spending API credits.

## When to Use

Invoke `/pre-flight` before running any API-calling pipeline target (S1, S2, S3 behavioral tests or evaluations). Not needed for read-only operations like `tar_read()` or `tar_outdated()`.

## Procedure

### Step 1: Ask the user

Ask which target(s) they plan to run. Common targets:

| Target | Description |
|--------|-------------|
| `c1_s1_results` | C1 S1 behavioral tests |
| `c1_s2_results` | C1 S2 LOOCV raw results |
| `c1_s2_eval` | C1 S2 evaluation metrics |
| `c1_s3_results` | C1 S3 error analysis |
| `c2_s1_results` | C2 S1 behavioral tests |
| (etc.) | Same pattern for C2-C4 |

### Step 2: Run checks (all read-only)

Run each check and record pass/fail:

#### Check 1: Git status clean

```bash
git status --porcelain -- 'R/*.R' 'prompts/*.yml' '_targets.R'
```

- **Pass**: No output (no uncommitted changes to pipeline-critical files)
- **Fail**: List the modified files. Suggest committing before running.

#### Check 2: Target exists in manifest

```bash
Rscript -e 'library(targets); cat(tar_manifest()$name, sep = "\n")' | grep <target_name>
```

- **Pass**: Target name found
- **Fail**: Target not defined in `_targets.R`

#### Check 3: Upstream dependencies not outdated

```bash
Rscript -e 'library(targets); cat(tar_outdated(), sep = "\n")'
```

- **Pass**: Target not in outdated list (or only the target itself is outdated, which is expected)
- **Fail**: Upstream dependencies are outdated. List them and suggest running those first.

#### Check 4: Codebook validates

Identify which codebook the target uses (from target name prefix `c1`-`c4`), then:

```bash
Rscript -e 'source("R/behavioral_tests.R"); load_validate_codebook("prompts/<codebook_file>.yml")'
```

- **Pass**: No errors
- **Fail**: Show validation error. Codebook YAML is malformed.

#### Check 5: Model ID is valid

Read `_targets.R` and search for the model parameter used by the target. Verify it matches a known valid ID:

- `claude-haiku-4-5-20251001`
- `claude-sonnet-4-5-20250514`

- **Pass**: Model ID is current
- **Fail**: Flag the stale or unknown model ID

#### Check 6: API key present

This project uses `dotenv` to load environment variables from `.env`. Check the key after loading `.env`:

```bash
Rscript -e 'dotenv::load_dot_env(); cat(nchar(Sys.getenv("ANTHROPIC_API_KEY")) > 0)'
```

- **Pass**: `TRUE`
- **Fail**: API key not set. Verify `.env` file exists at the project root and contains `ANTHROPIC_API_KEY=sk-ant-...`

#### Check 7: Cost estimate

Count expected API calls for the target:

- **S1 targets**: Count behavioral test cases (Test I: N chunks, Test II: N classes, Test III: N examples, Test IV: N orderings x N chunks)
- **S2 targets**: 44 LOOCV folds (44 API calls)
- **S3 targets**: Count ablation components + Test V/VI/VII inputs

Estimate cost at the model's pricing:

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| claude-haiku-4-5-20251001 | $1.00 | $5.00 |
| claude-sonnet-4-5-20250514 | $3.00 | $15.00 |

Present as: "Estimated ~N API calls at ~$X.XX (model: Y)"

### Step 3: Present checklist

Format as a clear pass/fail summary:

```
## Pre-Flight: <target_name>

| # | Check | Status |
|---|-------|--------|
| 1 | Git status clean | PASS |
| 2 | Target exists | PASS |
| 3 | Dependencies current | PASS |
| 4 | Codebook validates | PASS |
| 5 | Model ID valid | PASS |
| 6 | API key present | PASS |
| 7 | Cost estimate | ~44 calls, ~$0.15 (haiku) |

Ready to run: `tar_make(<target_name>)`
```

If any check fails, show the failure details and suggest fixes.

### Step 4: Stop

Do NOT run `tar_make()`. The user decides when to run the pipeline. End with the checklist output only.
