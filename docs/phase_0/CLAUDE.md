# Phase 0: Codebook Development — CLAUDE.md

This file provides context for Claude Code when working on Phase 0 implementation.

## Phase 0 Overview

**Goal**: Develop and validate 4 domain-specific codebooks (C1-C4) on a cost-efficient subset of `us_body` chunks using the Halterman & Keith (2025) 5-stage framework, evaluated against 44 labeled US fiscal acts.

**Approach**: Country-agnostic codebook design with few-shot learning using LLM API (Anthropic Claude or OpenRouter)

**Status**: IN PROGRESS — C1 S1 complete (v0.3.0), S2 ran on v0.3.0 (81.1% recall), codebook revised to v0.4.0 (relevance filter reframe), S1+S2 pending on v0.4.0; C2-C4 not yet started

## Authoritative Methodology

**Primary Reference**: `docs/strategy.md`

This document contains the complete R&R + H&K framework specification including:

- The 4 codebook definitions (C1-C4) mapping to R&R steps RR2-RR5
- H&K 5-stage validation pipeline (S0-S3 + S4 if needed)
- Success criteria per codebook and per stage
- Implementation sequencing strategy

**Supporting References**:

- `docs/methods/Methodology for Quantifying Exogenous Fiscal Shocks.md` — R&R methodology
- `docs/methods/The Halterman & Keith Framework for LLM Content Analysis.md` — H&K framework

## The Four Codebooks

| Codebook | R&R Step | Task | Output Type |
|----------|----------|------|-------------|
| **C1: Measure ID** | RR2 | Does passage describe a fiscal measure meeting "significant mention" rule? | Binary + extraction |
| **C2: Motivation** | RR5 | Classify motivation: Spending-driven, Countercyclical, Deficit-driven, Long-run | 4-class + exogenous flag |
| **C3: Timing** | RR4 | Extract implementation quarter(s) using midpoint rule | List of quarters |
| **C4: Magnitude** | RR3 | Extract fiscal impact in billions USD | Magnitude per quarter |

**Sequencing**: C1 → C2 → C3 → C4 (following R&R step order, allowing upstream outputs to feed downstream)

## H&K Stages (Applied to Each Codebook)

| Stage | Purpose | Pass Criteria |
|-------|---------|---------------|
| **S0: Codebook Prep** | Machine-readable YAML definitions | Domain expert approval |
| **S1: Behavioral Tests** | Model sanity checks | Legal outputs (100%), memorization (100%), order sensitivity (<5%) |
| **S2: Zero-Shot Eval** | Performance measurement | Single-pass zero-shot on 44 US acts, meet primary metrics |
| **S3: Error Analysis** | Failure mode identification | Documented patterns, ablation studies |
| **S4: Fine-Tuning** | Last resort improvement | Only if S3 shows unacceptable patterns AND codebook improvements exhausted |

**Critical Note**: Fine-tuning is avoided to preserve country-agnostic transferability.

## Success Criteria Per Codebook

| Codebook | Primary Metric | Target | Critical |
|----------|---------------|--------|----------|
| C1: Measure ID | Recall | ≥90% | Don't miss real acts |
| C1: Measure ID | Precision | ≥70% | Acceptable FP rate |
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

- ✅ `c1_measure_id.yml` — Created
- `c2_motivation.yml`
- `c3_timing.yml`
- `c4_magnitude.yml`

### H&K Stage Functions (`/R/`)

- ✅ `codebook_stage_0.R` — Created (codebook loading/validation)
- ✅ `codebook_stage_1.R` — Created (behavioral tests runner)
- ✅ `codebook_stage_2.R` — Created (zero-shot evaluation; LOOCV reserved for S3 few-shot ablation)
- ✅ `codebook_stage_3.R` — Created (error analysis)
- ✅ `behavioral_tests.R` — Created (H&K test suite implementation)
- ✅ `generate_c1_examples.R` — Created (C1 few-shot example generation)

### Notebooks (`/notebooks/`)

- ✅ `c1_measure_id.qmd` — Created (C1 evaluation notebook, S0-S3)
- `c2_motivation.qmd`
- `c3_timing.qmd`
- `c4_magnitude.qmd`
- `rr6_aggregation.qmd`
- `pipeline_integration.qmd`

## Targets Pipeline Integration

### Key Targets (To Be Implemented)

```r
# Training data preparation
tar_target(aligned_data, align_labels_shocks(us_labels, us_shocks))

# Codebook loading and validation
tar_target(c1_codebook, load_validate_codebook("prompts/c1_measure_id.yml"))
tar_target(c2_codebook, load_validate_codebook("prompts/c2_motivation.yml"))
tar_target(c3_codebook, load_validate_codebook("prompts/c3_timing.yml"))
tar_target(c4_codebook, load_validate_codebook("prompts/c4_magnitude.yml"))

# Per-codebook S1-S3 pipeline (C1 shown; repeat for C2, C3, C4)
tar_target(c1_s1_results, run_behavioral_tests_s1(c1_codebook, aligned_data))
tar_target(c1_s2_test_set, assemble_zero_shot_test_set(aligned_data, c1_chunk_data))
tar_target(c1_s2_results, run_zero_shot(c1_codebook, c1_s2_test_set, type = "C1"))
tar_target(c1_s3_results, run_error_analysis(c1_codebook, c1_s2_results, aligned_data))

# Final LLM-generated shock dataset
tar_target(shocks_llm, aggregate_outputs(c1_s2_results, c2_s2_results,
                                          c3_s2_results, c4_s2_results))
```

### Running Phase 0 Pipeline

```r
# Execute codebook evaluation
tar_make()

# Read specific outputs
tar_read(c1_s2_results)     # C1 zero-shot classification results
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
```

Load in R: `dotenv::load_dot_env()` at start of `_targets.R`

### API Usage

**Default Model**: Claude Haiku 4.5 (`claude-haiku-4-5-20251001`) for paper-quality results

**Exploration Model**: Qwen 2.5 72B (`qwen/qwen-2.5-72b-instruct`) via OpenRouter for cost-effective iteration

- 200K context window (handles long documents)
- JSON mode for structured outputs
- Strong reasoning for borderline cases
- Provider configurable in `_targets.R` (`llm_provider`, `llm_model`)

**Rate Limits**: Tier 1 = 50 requests/minute (Anthropic)

- Implemented with `Sys.sleep(1.2)` between calls
- Retry logic with exponential backoff

## PDF Extraction

**Active method**: `pull_text_local()` in `R/pull_text_local.R` using PyMuPDF + OCR.

- Parallel extraction with configurable workers
- Automatic OCR detection for scanned PDFs
- JSON caching in `data/extracted/`

**Fallback**: `pull_text()` in `R/pull_functions.R` using pdftools (text-based PDFs only, no OCR).

## Per-Codebook Implementation Steps

For each codebook (C1-C4):

1. **S0**: Draft codebook YAML based on R&R methodology
2. **S1**: Run behavioral tests, iterate on codebook until pass
3. **S2**: Run zero-shot evaluation on chunk test set, document baseline metrics
4. **S3**: Conduct error analysis, identify failure patterns
5. **Decision**: If metrics acceptable → proceed; if not → improve S0 or (last resort) S4
6. **Document**: Produce Quarto notebook with results

## Next Steps After Phase 0

**If all codebooks meet success criteria**:
→ Proceed to **Phase 1 (US Full Production)**: run on full `us_body`, compare against `us_shocks.csv`
→ Then **Phase 2 (Malaysia Pilot)**: see `docs/phase_1/malaysia_strategy.md` for strategic plan
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
