# Phase 0: US Benchmark Training — CLAUDE.md

This file provides context for Claude Code when working on Phase 0 implementation.

## Phase 0 Overview

**Goal**: Train LLM models on US government documents (1945-2022) to identify fiscal shocks matching Romer & Romer's gold-standard labels.

**Timeline**: 10 days (2 weeks for validation)

**Status**: IN PROGRESS (Model A complete, Model B training, Model C not started)

**Approach**: Few-shot learning with Claude 3.5 Sonnet API + cloud PDF extraction (AWS Lambda or local)

## Key Documents

- **[plan_phase0.md](plan_phase0.md)** - Full implementation plan (10-day timeline, model architecture, evaluation metrics)
- **[model_a_results_summary.md](model_a_results_summary.md)** - Model A performance evaluation
- **[model_a_precision_improvements.md](model_a_precision_improvements.md)** - Precision enhancement strategies
- **[targets_integration_complete.md](targets_integration_complete.md)** - Targets pipeline integration status
- **[DEPLOYMENT_OPTIONS.md](DEPLOYMENT_OPTIONS.md)** - AWS Lambda vs local deployment comparison

## Three Models Implemented

### Model A: Act Detection
**Task**: Binary classification - does this passage describe a specific fiscal act?

**Files**:
- `R/model_a_detect_acts.R` - Implementation
- `prompts/model_a_system.txt` - System prompt
- `prompts/model_a_examples.json` - Few-shot examples

**Success Criteria**: F1 > 0.85 on test set

**Current Status**: ✅ COMPLETE (see `model_a_results_summary.md`)

### Model B: Motivation Classification
**Task**: 4-way classification into Romer & Romer categories:
1. Spending-driven (endogenous)
2. Countercyclical (endogenous)
3. Deficit-driven (exogenous)
4. Long-run (exogenous)

**Files**:
- `R/model_b_classify_motivation.R` - Implementation
- `prompts/model_b_system.txt` - System prompt with Romer & Romer framework
- `prompts/model_b_examples.json` - Few-shot examples (5 per class)

**Success Criteria**:
- Overall accuracy > 0.75
- Per-class F1 > 0.70
- Exogenous flag accuracy > 0.85

**Current Status**: 🔄 IN PROGRESS (currently training)

### Model C: Information Extraction
**Task**: Extract timing (quarters) and magnitude (billions USD) from narrative + tables

**Files**:
- `R/model_c_extract_info.R` - Implementation
- `prompts/model_c_system.txt` - Extraction rules + table interpretation

**Success Criteria**:
- Timing: ±1 quarter tolerance > 85%
- Magnitude MAPE < 30%
- Sign accuracy > 95%

**Current Status**: ⏳ NOT STARTED (planned after Model B complete)

## Training Data

### Ground Truth Labels

**Location**: `data/raw/`
- `us_shocks.csv` (126 fiscal shock events) - Act name, date, magnitude, timing, motivation, exogenous flag, reasoning
- `us_labels.csv` (340 document passages) - Text excerpts aligned to specific acts

**CRITICAL**: Only **44 acts** have complete labels suitable for training Models A/B/C. This is NOT 126 acts as originally assumed.

**Implications**:
- Few-shot learning is the only viable approach (not fine-tuning)
- Phase 1 must use transfer learning (cannot expect large Malaysia dataset)
- Success = methodology validation, not scale

### Document Sources

**Location**: Various (extracted to `_targets/` cache)
- Economic Report of the President (ERP) - 77 years, ~150 documents
- Treasury Annual Reports - ~100 documents
- Budget Documents - ~100 documents

**Total**: ~350 PDFs covering 1946-present

## Targets Pipeline Integration

### Key Targets

```r
# Training data preparation
tar_target(aligned_data, align_labels_shocks(us_labels, us_shocks))
tar_target(training_data_a, prepare_model_a_data(aligned_data, relevant_paragraphs))
tar_target(training_data_b, prepare_model_b_data(aligned_data))
tar_target(training_data_c, prepare_model_c_data(aligned_data))

# Model predictions
tar_target(model_a_predictions, run_model_a(training_data_a))
tar_target(model_b_predictions, run_model_b(training_data_b))
tar_target(model_c_predictions, run_model_c(training_data_c))

# Evaluation
tar_target(model_a_eval, evaluate_model_a(model_a_predictions))
tar_target(model_b_eval, evaluate_model_b(model_b_predictions))
tar_target(model_c_eval, evaluate_model_c(model_c_predictions))

# Final LLM-generated shock dataset
tar_target(shocks_llm, combine_predictions(model_b_predictions, model_c_predictions))
```

### Running Phase 0 Pipeline

```r
# Execute all Phase 0 targets
tar_make()

# Read specific outputs
tar_read(model_a_eval)     # Model A performance metrics
tar_read(model_b_eval)     # Model B confusion matrix
tar_read(model_c_eval)     # Model C magnitude/timing errors
tar_read(shocks_llm)       # Final LLM shock dataset

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
- Total API calls: ~378 (126 acts × 3 models)
- Minimum runtime: ~8 minutes
- Implemented in `R/functions_llm.R` with `Sys.sleep(1.2)` between calls

**Retry Logic**: Exponential backoff (3 attempts) in `call_claude_api()`

**Logging**: All API calls logged to `logs/api_calls.csv` (timestamp, tokens, cost)

## Cost Estimates

| Component | Estimated | Notes |
|-----------|-----------|-------|
| PDF Extraction (Lambda) | $6.04 | 350 PDFs × 4.8 min × 3GB |
| Model A API | $5.87 | ~101 passages |
| Model B API | $7.14 | 126 acts × 5K tokens |
| Model C API | $3.12 | 126 acts × 6K tokens (with tables) |
| Contingency | $8.00 | Retries/errors |
| **Total** | **~$30** | Phase 0 budget |

## Evaluation Metrics

### Model A (Act Detection)
- **Precision**: TP / (TP + FP) - target > 0.80
- **Recall**: TP / (TP + FN) - target > 0.90 (don't miss real acts)
- **F1 Score**: target > 0.85

### Model B (Motivation Classification)
- **Overall accuracy**: target > 0.75
- **Per-class F1**: target > 0.70 for each category
- **Confusion matrix**: Check Spending-driven ↔ Countercyclical errors
- **Exogenous flag accuracy**: target > 0.85 (critical for multiplier estimation)

### Model C (Information Extraction)
- **Timing**: ±1 quarter tolerance > 85%
- **Magnitude MAPE**: < 30%
- **Sign accuracy**: > 95% (tax increase = positive, tax cut = negative)
- **Correlation**: r > 0.90 with true values

## Common Tasks

### Re-run Model A on New Data
```r
# 1. Update training data
tar_make(training_data_a)

# 2. Re-run predictions
tar_make(model_a_predictions)

# 3. Re-evaluate
tar_make(model_a_eval)

# 4. View results
tar_read(model_a_eval)
```

### Adjust Few-Shot Examples
```r
# 1. Edit prompts/model_a_examples.json
# 2. Invalidate cache
tar_invalidate(model_a_predictions)
# 3. Re-run
tar_make(model_a_predictions)
```

### Add New Model (e.g., Model D)
```r
# 1. Create R/model_d_*.R
# 2. Add targets to _targets.R:
tar_target(model_d_predictions, run_model_d(training_data_d))
tar_target(model_d_eval, evaluate_model_d(model_d_predictions))
# 3. Run pipeline
tar_make()
```

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

## Troubleshooting

### API Rate Limit Errors
**Error**: `429 Too Many Requests`
**Fix**: Increase `Sys.sleep()` in `R/functions_llm.R` from 1.2s to 2.0s

### JSON Parsing Failures
**Error**: `parse_json_response() failed`
**Cause**: LLM returned malformed JSON or wrapped in markdown
**Fix**: Check `R/functions_llm.R` - extracts JSON from ```json...``` blocks

### Low Model Performance
**Model A F1 < 0.85**: Add more few-shot examples (current: 20, try 30)
**Model B accuracy < 0.75**: Check confusion matrix - which categories confused? Add targeted examples
**Model C MAPE > 30%**: Focus on table extraction - use Vision API for critical PDFs

### Targets Cache Issues
**Error**: Target appears outdated but won't rebuild
**Fix**:
```r
tar_invalidate(<target_name>)  # Force rebuild
tar_make(<target_name>)
```

## Next Steps After Phase 0

**If all models meet success criteria**:
→ Proceed to **Phase 1 (Malaysia Deployment)**
→ See `docs/phase_1/malaysia_strategy.md` for strategic plan
→ Key constraint: Transfer learning with limited training data (44 acts)

**If models underperform**:
→ Error analysis in `notebooks/phase0_evaluation.qmd`
→ Add more few-shot examples
→ Consider hybrid human-in-loop approach
→ See "Pivot options" in [plan_phase0.md](plan_phase0.md#next-steps-after-phase-0)

## References

- **Romer & Romer (2010)**: "The Macroeconomic Effects of Tax Changes: Estimates Based on a New Measure of Fiscal Shocks" (American Economic Review)
- **Mertens & Ravi (2013)**: "The Dynamic Effects of Personal and Corporate Income Tax Changes in the United States" (American Economic Review)
- **Targets documentation**: https://books.ropensci.org/targets/
- **Claude API docs**: https://docs.anthropic.com/claude/reference/

## Contact

For Phase 0 specific questions, see the full implementation plan in [plan_phase0.md](plan_phase0.md).
