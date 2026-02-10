# High-Level Strategy: R&R + H&K Framework for Fiscal Shock Identification

## Executive Summary

**Objective:** Transform a collection of fiscal policy documents (e.g., `us_body`) into a balanced quarterly dataset of exogenous fiscal shocks (e.g., `us_shocks.csv`) using LLMs to transfer the knowledge gathered by Romer & Romer in the US to other countries.

**Approach:** Integrate two rigorous frameworks:

- **Romer & Romer (2010)**: 6-step methodology for identifying exogenous fiscal shocks (RR1-RR6)
- **Halterman & Keith (2025)**: 5-stage framework for rigorous LLM content analysis

**Key Innovation:** Create 4 domain-specific codebooks (one per R&R LLM step), each processed through the full H&K validation pipeline before moving to the next. The pipeline is designed to be **country-agnostic** to enable transfer learning across countries without retraining.

**Research Contribution:** Novel synthesis framing — first application of H&K validation framework to economic history/fiscal policy domain.

**Reference Documents:**

- R&R Methodology: `docs/methods/Methodology for Quantifying Exogenous Fiscal Shocks.md`
- H&K Framework: `docs/methods/The Halterman & Keith Framework for LLM Content Analysis.md`

---

## Project Phases

The project progresses through four phases. Each phase builds on the previous one.

| Phase | Name | Scope | Key Deliverable |
|-------|------|-------|-----------------|
| **Phase 0** | Codebook Development | Develop and validate codebooks C1-C4 on a subset of `us_body` chunks using H&K S0-S3 on 44 US labeled acts | Validated codebooks meeting success criteria |
| **Phase 1** | US Full Production | Run validated codebooks on the full `us_body` corpus; compare end-to-end results against `us_shocks.csv` | Reproduced US shock series |
| **Phase 2** | Malaysia Pilot | Deploy codebooks to Malaysia documents (1980-2022) with expert validation | Expert-validated Malaysia fiscal shock dataset |
| **Phase 3** | Regional Scaling | Extend to Indonesia, Thailand, Philippines, Vietnam | Multi-country fiscal shock panel |

**Phase 0 vs. Phase 1 distinction:** Phase 0 validates codebook accuracy using LOOCV on a cost-efficient subset of chunks (relevant + irrelevant text around the 44 labeled acts). Phase 1 tests whether the validated codebooks can recover `us_shocks.csv` when run on the full document corpus, which is far more expensive but validates production readiness.

---

## The Complete R&R Pipeline

The Romer & Romer methodology consists of 6 steps (RR1-RR6). Steps RR2-RR5 are implemented as LLM codebooks; RR1 and RR6 are data engineering tasks.

| R&R Step | Task | Implementation | Output |
|----------|------|----------------|--------|
| **RR1: Source Compilation** | Gather fiscal policy documents | Data engineering | Document corpus |
| **RR2: Measure ID** | Identify fiscal measures meeting "significant mention" rule | Codebook C1 (LLM) | Binary + extraction |
| **RR3: Quantification** | Extract fiscal impact in billions USD | Codebook C4 (LLM) | Magnitude per quarter |
| **RR4: Timing** | Extract implementation quarter(s) using midpoint rule | Codebook C3 (LLM) | List of quarters |
| **RR5: Motivation** | Classify motivation and filter exogenous shocks | Codebook C2 (LLM) | 4-class + exogenous flag |
| **RR6: Aggregation** | Normalize by GDP, aggregate to quarterly series | Data engineering | Shock time series |

---

## RR1: Source Compilation (Data Engineering)

### Required Sources (per R&R methodology)

| Source | Purpose | Status |
|--------|---------|--------|
| Economic Report of the President | Executive fiscal narrative | ✅ URLs and text extracted (`erp_urls`, `us_body`) |
| Treasury Annual Reports | Revenue estimates, implementation details | ✅ URLs and text extracted |
| Budget of the United States | Budget proposals, revenue projections | ✅ URLs and text extracted |
| House Ways & Means Committee Reports | Legislative intent, bill details | ❌ Not yet collected |
| Senate Finance Committee Reports | Legislative intent, bill details | ❌ Not yet collected |
| Congressional Record | Floor debates, stated motivations | ❌ Not yet collected |
| CBO Reports (post-1974) | Non-partisan revenue estimates | ✅ Manually downloaded (CAPTCHA bypass), 1976-2022 |
| Conference Reports | Final bill versions | ❌ Not yet collected |
| Social Security Bulletin | Payroll tax changes | ⏸️ Deferred (CAPTCHA-protected) |

### Current Corpus

The `us_body` target contains **360 documents** (350 successfully extracted, 97.2% success rate) totaling **104,763 pages** across 4 document types:

| Document Type | Years | Documents | Pages |
|---------------|-------|-----------|-------|
| Economic Report of the President | 1947-2022 | 75 | 25,403 |
| Annual Report of the Treasury | 1946-2022 | 46 | 26,690 |
| Budget of the United States | 1946-2022 | 182 | 45,232 |
| CBO Budget and Economic Outlook | 1976-2022 | 47 | 7,438 |

The 10 failed extractions are Fraser-hosted Budget section PDFs with non-standard URLs and one broken Treasury link. None affect years critical to the 44 labeled acts. CBO PDFs were manually downloaded due to cbo.gov CAPTCHA requirements and extracted locally via `pymupdf_extract.py` into the `data/extracted/` cache.

Known act recall (expanded year window) is **84.8%** (39/46 acts). The 7 missing acts are attributable to non-standard naming in labels (e.g., Public Law numbers instead of popular names) and compound act names, not corpus gaps. See `notebooks/verify_body.qmd` for full verification results.

### RR1 Deliverables

**Notebooks:**

- `notebooks/verify_body.qmd` — Document coverage inventory, extraction quality, gap analysis (complete with interpretive commentary)
- `notebooks/data_overview.qmd` — Training data pipeline documentation

**Remaining:**

- SSB deferred: ssa.gov requires CAPTCHA; revisit in Phase 1 if codebook evaluation reveals payroll tax coverage gaps
- Per-bill congressional sources deferred: require Congress.gov API integration



---

## Architecture: 4 Codebooks × 5 Stages

### The Four Codebooks (R&R Steps RR2-RR5)

| Codebook | R&R Step | Task | Output Type |
|----------|----------|------|-------------|
| **C1: Measure ID** | RR2 | Does passage describe a fiscal measure meeting "significant mention" rule? | Binary + extraction |
| **C2: Motivation** | RR5 | Classify motivation: Spending-driven, Countercyclical, Deficit-driven, Long-run | 4-class + exogenous flag |
| **C3: Timing** | RR4 | Extract implementation quarter(s) using midpoint rule | List of quarters |
| **C4: Magnitude** | RR3 | Extract fiscal impact in billions USD | Magnitude per quarter + PV |

### H&K Stages (Applied to Each Codebook)

| Stage | Purpose | Key Activities |
|-------|---------|----------------|
| **S0: Codebook Prep** | Machine-readable definitions | Label, definition, clarifications, +/- examples, output instructions |
| **S1: Behavioral Tests** | Model sanity checks | Legal output (100%), memorization (100%), order sensitivity (<5%) |
| **S2: Zero-Shot Eval** | Performance measurement | LOOCV on 44 US acts, compute primary metrics |
| **S3: Error Analysis** | Failure mode identification | Ablation studies, swapped label tests, lexical heuristic detection |
| **S4: Fine-Tuning** | Last resort improvement | LoRA if S3 shows unacceptable performance (see note below) |

**Critical Note on S4 (Fine-Tuning):**

Fine-tuning is a **last resort** that should only be triggered based on S3 error analysis results. Because the pipeline must remain **country-agnostic** for cross-country transfer learning, fine-tuning on US data risks overfitting to US-specific patterns and reducing transferability to countries where we have no labeled data. Prefer improving codebook definitions (S0) or adding clarifying examples before resorting to S4.

---

## Sequencing Strategy

**Order:** C1 → C2 → C3 → C4 (following R&R step order)

**Rationale:**

In production, the output of Codebook N feeds into Codebook N+1:

```
Documents → C1 (Measure ID) → C2 (Motivation) → C3 (Timing) → C4 (Magnitude) → Aggregation
```

Developing codebooks in production order allows us to:

1. Test the actual input/output interfaces between stages
2. Identify how upstream errors propagate downstream
3. Build the pipeline incrementally with realistic inputs

**Dependencies:**

```
C1 (Measure ID)
       ↓
C2 (Motivation)
       ↓
    ┌──┴──┐
    ↓     ↓
  C3     C4
(Time) (Mag)
```

---

## Success Criteria

### Per Codebook

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

### Per H&K Stage (All Codebooks)

| Stage | Criterion | Pass Threshold |
|-------|-----------|----------------|
| S0 | Expert review | Domain expert approval |
| S1 | Legal outputs | 100% valid labels |
| S1 | Memorization | 100% recovery |
| S1 | Order sensitivity | <5% label changes |
| S2 | Primary metric | See codebook targets |
| S3 | Error analysis | Documented patterns |
| S4 | Fine-tuning decision | Only if S3 shows unacceptable patterns AND codebook improvements exhausted |

### Iteration Strategy (When Targets Are Not Met)

When a codebook fails to meet its success criteria after S2 evaluation:

1. **Review S3 error analysis.** Identify the dominant error category using H&K taxonomy (A: format, B: scope, C: omission, D: non-compliance, E: semantics/reasoning, F: ambiguous ground truth).
2. **If Category D (non-compliance):** Improve output instructions (format, valid labels reminder).
3. **If Category E (semantics/reasoning):** Improve clarifications and add worked examples targeting the identified confusion pattern.
4. **Run ablation** to find the weakest codebook component. Strengthen it with additional clarifications or examples.
5. **Add domain-specific negative examples** targeting identified failure patterns (near-miss passages that caused errors).
6. **If three S0 revision rounds** don't reach targets: document the gap, consider whether the target should be adjusted with methodological justification.
7. **S4 trigger:** Only if all S0 improvements are exhausted AND the remaining gap compromises the research contribution. Document the decision rationale.

---

## Codebook Structure Template

Each codebook is a single YAML file in `prompts/` following H&K machine-readable format. The authoritative format specification is `.claude/skills/codebook-yaml/SKILL.md`. Summary of top-level structure:

```yaml
codebook:
  name: "C1: Measure Identification"
  version: "0.1.0"
  description: >
    One-paragraph task description explaining what the LLM must do.

  instructions: >
    Overall task instructions provided to the LLM before the class definitions.
    Describes input format, expected output format, and global rules.

  classes:
    - label: "CATEGORY_NAME"
      label_definition: >
        Single-sentence definition from R&R methodology.
      clarification:
        - "Inclusion criterion 1 (independently testable for ablation)"
        - "Inclusion criterion 2"
      negative_clarification:
        - "Exclusion rule 1 (addresses most common confusion case)"
        - "Exclusion rule 2"
      positive_examples:
        - text: "Example passage..."
          reasoning: "Why this qualifies, citing specific criteria"
      negative_examples:
        - text: "Near-miss passage..."
          reasoning: "Why this does NOT qualify, citing exclusion rule"

  output_instructions: >
    Reminds the LLM of exact valid labels, specifies output format
    (plain text or JSON), and includes structured output requirements.
```

**Key design rules:**

- **Ablation-ready**: Each clarification item makes an independent, testable contribution (H&K Table 4)
- **Country-agnostic**: Definitions and clarifications use general fiscal concepts; US-specific terms only in examples
- **Near-miss negatives**: Negative examples are plausible near-misses, not obvious strawmen

---

## Implementation Approach

### Step-by-Step Development

Each R&R step is implemented and validated independently before proceeding to the next. Each step produces or updates a **Quarto notebook** demonstrating successful implementation.

| Step | Description | Deliverable |
|------|-------------|-------------|
| 1 | ✅ Source compilation complete (360 docs, 104K pages, 4 sources) | `notebooks/verify_body.qmd` updated |
| 2 | Implement C1 (Measure ID) through H&K S0-S3 | `notebooks/c1_measure_id.qmd` |
| 3 | Implement C2 (Motivation) through H&K S0-S3 | `notebooks/c2_motivation.qmd` |
| 4 | Implement C3 (Timing) through H&K S0-S3 | `notebooks/c3_timing.qmd` |
| 5 | Implement C4 (Magnitude) through H&K S0-S3 | `notebooks/c4_magnitude.qmd` |
| 6 | Implement RR6 aggregation, validate against `us_shocks.csv` | `notebooks/rr6_aggregation.qmd` |
| 7 | End-to-end pipeline integration and testing | `notebooks/pipeline_integration.qmd` |

### C1: Measure Identification Blueprint

**S0 Codebook Design.** Operationalize the "significant mention" rule from `docs/literature_review.md` Section 1.2. Two classes: `FISCAL_MEASURE`, `NOT_FISCAL_MEASURE`. Inclusion criteria: legislated liability changes, executive depreciation orders, any action receiving more than incidental reference in primary sources. Exclusion criteria: extensions of existing provisions without rate changes, withholding-only adjustments, automatic renewals, proposals that did not become law.

**S1 Behavioral Tests.** Test I: valid JSON structure with required fields (label, reasoning). Test II: feed codebook definitions back as input, verify correct label recovery. Test III: feed positive/negative examples, verify correct label. Test IV: reverse class order (only 2 classes, so reverse `FISCAL_MEASURE` / `NOT_FISCAL_MEASURE`). Pass criteria: 100% legal outputs, 100% memorization, <5% order sensitivity.

**S2 LOOCV Plan.** Ground truth: `aligned_data` (44 acts from `us_labels.csv` + `us_shocks.csv`). For each act, hold out its passages, generate few-shot examples from remaining 43, classify held-out passages. Primary metrics: Recall ≥90%, Precision ≥80%. Bootstrap 1000 resamples for 95% CIs.

**S3 Error Analysis Plan.** Primary risk: false positives from passages discussing policy context without a specific legislative act. Test V: systematically remove each negative clarification, measure FP increase. Ablation on negative clarifications for "policy discussion without act" cases. Error categories following H&K taxonomy (A: format, B: scope, C: omission, D: non-compliance, E: semantics/reasoning, F: ambiguous ground truth).

**Migration from Legacy Code.** Reuse `R/functions_llm.R` (`call_claude_api()`), `R/functions_self_consistency.R` (self-consistency sampling), `R/prepare_training_data.R` (`align_labels_shocks()`). Adapt domain logic from `R/model_a_detect_acts.R`.

**Iteration Strategy.** If recall <90%: examine FN passages for oblique act references not covered by clarifications; add inclusion criteria. If precision <80%: strengthen negative clarifications for policy-discussion-without-act passages; add near-miss negative examples.

### C2: Motivation Classification Blueprint

**S0 Codebook Design.** Four classes: `SPENDING_DRIVEN`, `COUNTERCYCLICAL`, `DEFICIT_DRIVEN`, `LONG_RUN`, plus a derived exogenous flag (exogenous if `DEFICIT_DRIVEN` or `LONG_RUN`). Critical boundary cases from `docs/literature_review.md` Section 1.3: countercyclical vs. long-run distinction uses the "return to normal" test (is the stated goal restoring a prior state, or building something new?); spending-driven vs. deficit-driven uses the 1-year temporal rule (is spending the proximate cause within 1 year?); mixed motivation apportionment follows the EGTRRA 2001 worked example (split by component share).

**S1 Behavioral Tests.** Test IV is most critical (4 semantically loaded class names). Run original, reversed, and shuffled orderings of class definitions. Validate both the 4-class motivation label and the derived exogenous flag. Tests I-III follow the standard pattern. Pass criteria: 100% legal outputs, 100% memorization, <5% order sensitivity across all orderings.

**S2 LOOCV Plan.** Ground truth: `aligned_data` motivation labels (44 acts). LOOCV with stratified few-shot examples from `R/generate_few_shot_examples.R`. Primary metrics: Weighted F1 ≥70%, Exogenous Precision ≥85%. Report full 4x4 confusion matrix and 2x2 exogenous confusion matrix. Bootstrap 1000 resamples for 95% CIs.

**S3 Error Analysis Plan.** Tests VI/VII are critical for C2: replace labels with generic `LABEL_1`..`LABEL_4` (Test VI), then swap definitions across labels (Test VII) to detect reliance on semantically loaded label names rather than definitions. Primary risk: "deficit" appearing in passage text triggers `DEFICIT_DRIVEN` even when R&R methodology says `SPENDING_DRIVEN` (1-year temporal rule). Ablation on negative clarifications for boundary cases between each class pair.

**Migration from Legacy Code.** Adapt `R/model_b_loocv.R` (162+ lines of LOOCV framework). Reuse `R/generate_few_shot_examples.R` stratification logic for balanced class representation in few-shot prompts.

**Iteration Strategy.** If F1 <70%: examine confusion matrix for most confused class pair (likely countercyclical/long-run); strengthen distinguishing clarifications. If exogenous precision <85%: examine endogenous acts misclassified as exogenous; add negative examples for the specific confusion pattern.

### C3: Timing Extraction Blueprint

**S0 Codebook Design.** Structured extraction (not classification). Operationalize the midpoint rule from `docs/literature_review.md` Section 1.5: if legislation specifies a range, use the quarter containing the midpoint. Phased changes are recorded as separate entries with distinct quarters. Retroactive components appear in both the standard series (implementation quarter) and the adjusted series (quarter the legislation was signed). Output format: list of `{quarter, amount_at_annual_rate}` tuples. Include Excess Profits Tax 1950 as a worked example of phased timing.

**S1 Behavioral Tests.** Test I checks valid structured output format (list of quarter-amount tuples, quarters as YYYY-QN). Tests II-IV follow standard pattern. Pass criteria: 100% legal outputs, 100% memorization, <5% order sensitivity.

**S2 LOOCV Plan.** Compare extracted quarters to `us_shocks.csv` ground truth quarter assignments. Primary metrics: Exact quarter match ≥85%, ±1 quarter match ≥95%. Bootstrap 1000 resamples for 95% CIs.

**S3 Error Analysis Plan.** Ablation on midpoint rule clarification vs. phased change examples to determine which component drives accuracy. Error categories: wrong quarter (off by 1+), missed phase (fewer entries than ground truth), spurious phase (more entries than ground truth), incorrect retroactive handling, date parsing error.

**Migration from Legacy Code.** Split timing extraction from `R/model_c_extract_info.R`. Reuse quarter comparison logic from `R/evaluate_model_c.R`.

**Iteration Strategy.** If exact quarter <85%: examine whether errors cluster on phased/retroactive acts (systematic) or are distributed (noise). If clustered: improve midpoint rule clarification with additional worked examples.

### C4: Magnitude Extraction Blueprint

**S0 Codebook Design.** Structured extraction. Operationalize the fallback hierarchy from `docs/literature_review.md` Section 1.4: Economic Report of the President > calendar year estimates > fiscal year estimates > conference report estimates. Annual rate convention: all magnitudes expressed at annual rates. Distinguish policy-driven revenue changes from growth-driven changes (only policy-driven count). Output format: `{magnitude_billions, currency, annual_rate: true/false, source_tier: 1-4}`. Present-value alternative for multi-year provisions.

**S1 Behavioral Tests.** Test I checks valid numeric output with required fields (magnitude, currency, annual_rate flag, source_tier). Tests II-IV follow standard pattern. Pass criteria: 100% legal outputs, 100% memorization, <5% order sensitivity.

**S2 LOOCV Plan.** Compare extracted magnitude to `change_in_liabilities_billion` column in `us_shocks.csv`. Primary metrics: MAPE <30%, Sign accuracy ≥95%. Report scatter plot of predicted vs. actual. Bootstrap 1000 resamples for 95% CIs.

**S3 Error Analysis Plan.** Ablation on fallback hierarchy guidance to test whether the model follows source priority correctly. Primary risk: multiple revenue estimates in the same passage (e.g., ERP estimate vs. conference report estimate) confuse the model. Error categories: wrong source tier selected, magnitude off by order of magnitude, sign error, policy/growth confusion.

**Migration from Legacy Code.** Split magnitude extraction from `R/model_c_extract_info.R` and `R/evaluate_model_c.R`.

**Iteration Strategy.** If MAPE >30%: examine whether errors are systematic (e.g., consistently picking wrong source tier, or confusing fiscal year vs. calendar year estimates) vs. random. If sign accuracy <95%: examine whether sign errors correlate with ambiguous language about "revenue effects" vs. "tax changes."

---

## Files to Create

### Codebooks (`/prompts/`)

- `c1_measure_id.yml`
- `c2_motivation.yml`
- `c3_timing.yml`
- `c4_magnitude.yml`

### H&K Stage Functions (`/R/`)

- `codebook_stage_0.R` — Load YAML codebook, validate required fields (label, label_definition, clarification, negative_clarification, positive_examples, negative_examples, output_instructions), construct LLM prompt from structured components. Returns a validated codebook object.
- `codebook_stage_1.R` — Run Tests I-IV on a codebook. Takes codebook object + test documents. Returns tibble of test results with pass/fail per test.
- `codebook_stage_2.R` — Generalized LOOCV for any codebook type (C1-C4). Extends the pattern from `model_b_loocv.R`. Accepts codebook, aligned data, and codebook type. Returns predictions + metrics with bootstrap CIs.
- `codebook_stage_3.R` — Run Tests V-VII, ablation studies, and error categorization using H&K 6-category taxonomy (A-F). Returns error analysis report with ablation results.
- `behavioral_tests.R` — Shared test functions: `test_legal_outputs()` (Test I), `test_definition_recovery()` (Test II), `test_example_recovery()` (Test III), `test_order_invariance()` (Test IV), `test_exclusion_criteria()` (Test V), `test_generic_labels()` (Test VI), `test_swapped_labels()` (Test VII).

### Notebooks (`/notebooks/`)

**Existing (updated):**

- `verify_body.qmd` — ✅ RR1 source coverage, 6 verification tests with interpretive commentary
- `data_overview.qmd` — Align with new codebook terminology

**New (create):**

- `c1_measure_id.qmd`
- `c2_motivation.qmd`
- `c3_timing.qmd`
- `c4_magnitude.qmd`
- `rr6_aggregation.qmd`
- `pipeline_integration.qmd`

### Targets Pipeline Plan

Concrete target definitions for the C1-C4 codebook evaluation pipeline, replacing legacy Model A/B/C targets:

```r
# Codebook loading and validation
tar_target(c1_codebook, load_validate_codebook("prompts/c1_measure_id.yml"))
tar_target(c2_codebook, load_validate_codebook("prompts/c2_motivation.yml"))
tar_target(c3_codebook, load_validate_codebook("prompts/c3_timing.yml"))
tar_target(c4_codebook, load_validate_codebook("prompts/c4_magnitude.yml"))

# C1: Measure ID pipeline
tar_target(c1_s1_results, run_behavioral_tests_s1(c1_codebook, aligned_data))
tar_target(c1_s2_results, run_loocv(c1_codebook, aligned_data, type = "C1"))
tar_target(c1_s3_results, run_error_analysis(c1_codebook, c1_s2_results, aligned_data))

# C2: Motivation pipeline
tar_target(c2_s1_results, run_behavioral_tests_s1(c2_codebook, aligned_data))
tar_target(c2_s2_results, run_loocv(c2_codebook, aligned_data, type = "C2"))
tar_target(c2_s3_results, run_error_analysis(c2_codebook, c2_s2_results, aligned_data))

# C3: Timing pipeline
tar_target(c3_s1_results, run_behavioral_tests_s1(c3_codebook, aligned_data))
tar_target(c3_s2_results, run_loocv(c3_codebook, aligned_data, type = "C3"))
tar_target(c3_s3_results, run_error_analysis(c3_codebook, c3_s2_results, aligned_data))

# C4: Magnitude pipeline
tar_target(c4_s1_results, run_behavioral_tests_s1(c4_codebook, aligned_data))
tar_target(c4_s2_results, run_loocv(c4_codebook, aligned_data, type = "C4"))
tar_target(c4_s3_results, run_error_analysis(c4_codebook, c4_s2_results, aligned_data))

# Aggregation
tar_target(shocks_llm, aggregate_outputs(c1_s2_results, c2_s2_results,
                                          c3_s2_results, c4_s2_results))
```

---

## Cross-Country Transfer Strategy

### Design Principle

The entire pipeline is designed for **country-agnostic transfer**. This means:

- Codebook definitions use general fiscal policy concepts, not US-specific terminology
- Examples are illustrative of patterns, not memorization targets
- Fine-tuning is avoided to prevent overfitting to US data

### Expected Transfer Gaps

| Component | Transfer Quality | Risk |
|-----------|-----------------|------|
| Motivation categories | High | Low |
| Timing rules | High | Low |
| Magnitude extraction | Medium | Medium |
| Legislative language | Low | High |

### Malaysia Adaptation Protocol

1. Run US-trained codebooks on Malaysia documents
2. Expert validates random 50% sample
3. If agreement < 70% for any codebook:
   - Add Malaysia-specific examples to codebook (S0 revision)
   - Re-run S2-S3 (not full pipeline)
   - Document transfer learning gap

---

## Verification Plan

### Per Codebook

1. **S0 Complete:** Codebook YAML reviewed by domain expert
2. **S1 Pass:** All behavioral tests pass thresholds
3. **S2 Baseline:** LOOCV metrics computed and documented
4. **S3 Complete:** Error analysis report with patterns identified
5. **S4 Decision:** Fine-tuning triggered only if codebook improvements exhausted

### Phase 1: US Full Production

1. Run full pipeline on entire `us_body` corpus
2. Verify end-to-end recall ≥85% on 44 known acts
3. Compare extracted shocks to `us_shocks.csv`
4. Document any systematic gaps

### Phase 2: Malaysia Pilot

1. Run pipeline on Malaysia documents (1980-2022)
2. Expert agreement ≥80% on measure identification
3. Expert agreement ≥70% on motivation classification
4. Document transfer learning performance

---

## Key Decisions Summary

- **Country-agnostic design**: Pipeline must transfer to countries without labeled data
- **Production-order sequencing**: C1 → C2 → C3 → C4 to test actual data flow
- **Fine-tuning as last resort**: Preserve transferability by improving codebooks first
- **One notebook per R&R step**: Clear documentation of each implementation step
- **Explicit methodology references**: Implementing agents consult `docs/methods/` for details
- **Incremental validation**: Each R&R step validated before proceeding to next

---

## RR6: Aggregation (Data Engineering)

### Steps (per R&R methodology)

1. **Normalize by GDP**: Express each nominal shock as percentage of nominal GDP in implementation quarter
2. **Aggregate multiple actions**: Sum GDP percentages for same-motivation shocks in same quarter
3. **Handle phased changes**: Record each implementation step in respective quarters
4. **Produce final series**: Quarterly time series with discrete exogenous shock entries

### Required Data

- Quarterly nominal GDP series (1945-present)
- Codebook outputs: measure ID, magnitude, timing, motivation

### RR6 Deliverable

**Quarto notebook:** `notebooks/rr6_aggregation.qmd`

- Aggregation methodology verification against `us_shocks.csv`
- Validation of GDP normalization
- Final dataset generation