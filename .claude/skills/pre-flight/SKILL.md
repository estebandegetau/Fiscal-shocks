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
| `c1_s2_results` | C1 S2 zero-shot raw results |
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

#### Check 5: Model & API key

Read `_targets.R` and identify `llm_provider` and `llm_model`. Report both in the checklist.

Then verify the corresponding API key is present. The project uses `dotenv` to load environment variables from `.env`. Check the key that matches the configured provider:

| Provider | Env var |
|----------|---------|
| `anthropic` | `ANTHROPIC_API_KEY` |
| `openrouter` | `OPENROUTER_API_KEY` |
| `openai` | `OPENAI_API_KEY` |
| `groq` | `GROQ_API_KEY` |
| `ollama` | (none needed) |

```bash
Rscript -e 'dotenv::load_dot_env(); cat(nchar(Sys.getenv("<ENV_VAR>")) > 0)'
```

- **Pass**: `TRUE` (key present for the configured provider)
- **Fail**: API key not set. Verify `.env` file exists and contains the correct key.

If the provider is not `anthropic`, add an **INFO** note (not a failure): "Non-Anthropic model — results are for exploration only and cannot be reported as H&K validation in the paper."

#### Check 7: Cost estimate

Count expected API calls for the target:

- **S1 targets**: Count behavioral test cases (Test I: N chunks, Test II: N classes, Test III: N examples, Test IV: N orderings x N chunks)
- **S2 targets**: One API call per chunk in test set. Check `tar_read(c1_s2_test_set) |> nrow()` (or estimate from cached value if test set is outdated)
- **S3 targets**: Count ablation components + Test V/VI/VII inputs

Estimate cost at the model's pricing. For known models:

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| claude-haiku-4-5-20251001 | $1.00 | $5.00 |
| claude-sonnet-4-5-20250514 | $3.00 | $15.00 |

For non-Anthropic models, look up current pricing or note "check provider pricing".

Present as: "Estimated ~N API calls (model: provider/model-id)"

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
| 5 | Model & API key | PASS — openrouter/qwen-2.5-72b-instruct |
| 6 | Cost estimate | ~52 calls (model: openrouter/qwen-2.5-72b) |

Ready to run: `tar_make(<target_name>)`
```

If any check fails, show the failure details and suggest fixes.

### Step 4: Stop

Do NOT run `tar_make()`. The user decides when to run the pipeline. End with the checklist output only.
