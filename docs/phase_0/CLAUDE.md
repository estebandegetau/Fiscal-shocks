# Phase 0: US Benchmark Training — CLAUDE.md

This file provides context for Claude Code when working on Phase 0 implementation.

## Phase 0 Overview

**Goal**: Develop and validate 4 domain-specific codebooks (C1-C4) on 44 US fiscal acts using the Halterman & Keith (2025) 5-stage framework.

**Approach**: Country-agnostic codebook design with few-shot learning using Claude 3.5 Sonnet API

**Status**: IN PROGRESS — Transitioning from legacy Model A/B/C approach to C1-C4 codebook framework

## Authoritative Methodology

**Primary Reference**: `docs/strategy.md`

This document contains the complete R&R + H&K framework specification including:

- The 4 codebook definitions (C1-C4) mapping to R&R phases 2-5
- H&K 5-stage validation pipeline (S0-S3 + S4 if needed)
- Success criteria per codebook and per stage
- Implementation sequencing strategy

**Supporting References**:

- `docs/methods/Methodology for Quantifying Exogenous Fiscal Shocks.md` — R&R methodology
- `docs/methods/The Halterman & Keith Framework for LLM Content Analysis.md` — H&K framework

## The Four Codebooks

| Codebook | R&R Phase | Task | Output Type |
|----------|-----------|------|-------------|
| **C1: Measure ID** | Phase 2 | Does passage describe a fiscal measure meeting "significant mention" rule? | Binary + extraction |
| **C2: Motivation** | Phase 5 | Classify motivation: Spending-driven, Countercyclical, Deficit-driven, Long-run | 4-class + exogenous flag |
| **C3: Timing** | Phase 4 | Extract implementation quarter(s) using midpoint rule | List of quarters |
| **C4: Magnitude** | Phase 3 | Extract fiscal impact in billions USD | Magnitude per quarter |

**Sequencing**: C1 → C2 → C3 → C4 (following R&R phase order, allowing upstream outputs to feed downstream)

## H&K Stages (Applied to Each Codebook)

| Stage | Purpose | Pass Criteria |
|-------|---------|---------------|
| **S0: Codebook Prep** | Machine-readable YAML definitions | Domain expert approval |
| **S1: Behavioral Tests** | Model sanity checks | Legal outputs (100%), memorization (100%), order sensitivity (<5%) |
| **S2: Zero-Shot Eval** | Performance measurement | LOOCV on 44 US acts, meet primary metrics |
| **S3: Error Analysis** | Failure mode identification | Documented patterns, ablation studies |
| **S4: Fine-Tuning** | Last resort improvement | Only if S3 shows unacceptable patterns AND codebook improvements exhausted |

**Critical Note**: Fine-tuning is avoided to preserve country-agnostic transferability.

## Success Criteria Per Codebook

| Codebook | Primary Metric | Target | Critical |
|----------|---------------|--------|----------|
| C1: Measure ID | Recall | ≥90% | Don't miss real acts |
| C1: Measure ID | Precision | ≥80% | Acceptable FP rate |
| C2: Motivation | Weighted F1 | ≥70% | LOOCV baseline |
| C2: Motivation | Exogenous Precision | ≥85% | Critical for shock series |
| C3: Timing | Exact Quarter | ≥85% | R&R accuracy |
| C3: Timing | ±1 Quarter | ≥95% | Acceptable tolerance |
| C4: Magnitude | MAPE | <30% | R&R accuracy |
| C4: Magnitude | Sign Accuracy | ≥95% | Critical (tax increase vs cut) |

## Training Data

### Ground Truth Labels

**Location**: `data/raw/`

- `us_shocks.csv` — Fiscal shock events with timing, magnitude, motivation, exogenous flag
- `us_labels.csv` — Document passages aligned to specific acts

**CRITICAL**: Only **44 acts** have complete labels suitable for codebook development. This is NOT 126 acts as originally assumed.

**Implications**:

- Few-shot learning is the only viable approach (not fine-tuning)
- Country-agnostic design is essential for cross-country transfer
- Success = methodology validation, not scale

### Document Sources

**Location**: Various (extracted to `_targets/` cache)

- Economic Report of the President (ERP) — 77 years, ~150 documents
- Treasury Annual Reports — ~100 documents
- Budget Documents — ~100 documents

**Total**: ~350 PDFs covering 1946-present

## Files to Create

### Codebooks (`/prompts/`)

- `codebook_1_measure_id.yaml`
- `codebook_2_motivation.yaml`
- `codebook_3_timing.yaml`
- `codebook_4_magnitude.yaml`

### H&K Stage Functions (`/R/`)

- `codebook_stage_0.R` — Codebook loading/validation
- `codebook_stage_1.R` — Behavioral tests
- `codebook_stage_2.R` — Zero-shot evaluation
- `codebook_stage_3.R` — Error analysis
- `behavioral_tests.R` — H&K test suite implementation

### Notebooks (`/notebooks/`)

- `codebook_1_measure_id.qmd`
- `codebook_2_motivation.qmd`
- `codebook_3_timing.qmd`
- `codebook_4_magnitude.qmd`
- `phase_6_aggregation.qmd`
- `pipeline_integration.qmd`

## Targets Pipeline Integration

### Key Targets (To Be Implemented)

```r
# Training data preparation
tar_target(aligned_data, align_labels_shocks(us_labels, us_shocks))

# Codebook 1: Measure ID
tar_target(c1_s1_results, run_behavioral_tests("codebook_1_measure_id.yaml"))
tar_target(c1_s2_results, run_loocv_evaluation(aligned_data, "C1"))
tar_target(c1_s3_analysis, run_error_analysis(c1_s2_results))

# Codebook 2: Motivation
tar_target(c2_s1_results, run_behavioral_tests("codebook_2_motivation.yaml"))
tar_target(c2_s2_results, run_loocv_evaluation(aligned_data, "C2"))
tar_target(c2_s3_analysis, run_error_analysis(c2_s2_results))

# Similar pattern for C3, C4...

# Final LLM-generated shock dataset
tar_target(shocks_llm, aggregate_codebook_outputs(c1_s2_results, c2_s2_results, c3_s2_results, c4_s2_results))
```

### Running Phase 0 Pipeline

```r
# Execute codebook evaluation
tar_make()

# Read specific outputs
tar_read(c1_s2_results)     # C1 LOOCV metrics
tar_read(c2_s3_analysis)    # C2 error analysis
tar_read(shocks_llm)        # Final LLM shock dataset

# Visualize dependencies
tar_visnetwork()
```

## LLM API Configuration

### Environment Variables

Create `.env` file (gitignored):
```
ANTHROPIC_API_KEY=sk-ant-api03-xxx...
AWS_ACCESS_KEY_ID=AKIA...          # If using Lambda
AWS_SECRET_ACCESS_KEY=xxx...       # If using Lambda
AWS_DEFAULT_REGION=us-east-1       # If using Lambda
```

Load in R: `dotenv::load_dot_env()` at start of `_targets.R`

### API Usage

**Model**: Claude 3.5 Sonnet (`claude-3-5-sonnet-20241022`)

- 200K context window (handles long documents)
- JSON mode for structured outputs
- Strong reasoning for borderline cases

**Rate Limits**: Tier 1 = 50 requests/minute

- Implemented with `Sys.sleep(1.2)` between calls
- Retry logic with exponential backoff

## PDF Extraction Options

### Option 1: AWS Lambda (Cloud)

**Pros**: Fast (5-10 min for 350 PDFs), parallel, no local resources
**Cons**: AWS setup required, ~$6 cost
**See**: [DEPLOYMENT_OPTIONS.md](DEPLOYMENT_OPTIONS.md), [lambda_deployment_guide.md](lambda_deployment_guide.md)

### Option 2: Local Docling (Python)

**Pros**: Free, no AWS dependencies, good for small batches
**Cons**: Slow (12+ hours for 350 PDFs), sequential processing
**Command**: `python python/docling_extract.py --input <pdf> --output <json>`

### Option 3: pdftools (R, fallback)

**Pros**: Fast, built-in to R, no Python
**Cons**: Poor table extraction, misses structured data
**Function**: `pull_text_pdftools()` in `R/pull_functions.R`

**Recommendation**: Use Lambda for full dataset, local Docling for testing/debugging.

## Per-Codebook Implementation Steps

For each codebook (C1-C4):

1. **S0**: Draft codebook YAML based on R&R methodology
2. **S1**: Run behavioral tests, iterate on codebook until pass
3. **S2**: Run LOOCV evaluation, document baseline metrics
4. **S3**: Conduct error analysis, identify failure patterns
5. **Decision**: If metrics acceptable → proceed; if not → improve S0 or (last resort) S4
6. **Document**: Produce Quarto notebook with results

## Next Steps After Phase 0

**If all codebooks meet success criteria**:
→ Proceed to **Phase 1 (Malaysia Deployment)**
→ See `docs/phase_1/malaysia_strategy.md` for strategic plan
→ Key constraint: Transfer learning with limited training data (44 acts)

**If codebooks underperform**:
→ Error analysis in codebook notebooks
→ Improve codebook definitions (S0 revision)
→ Add clarifying examples before considering fine-tuning
→ Document failure patterns for research contribution

## Historical Documentation

Previous Model A/B/C implementation documents have been archived to `docs/archive/phase_0/`. The current methodology uses the C1-C4 codebook framework documented in `docs/strategy.md`.

## References

- **Romer & Romer (2010)**: Original narrative approach methodology
- **Halterman & Keith (2025)**: LLM content analysis validation framework
- **Targets documentation**: https://books.ropensci.org/targets/
- **Claude API docs**: https://docs.anthropic.com/claude/reference/
