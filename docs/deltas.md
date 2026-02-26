# Strategy Delta Log

Bottom-up discoveries from implementation that may require updates to
human-authored specification documents (`docs/strategy.md`, `docs/proposal.qmd`,
`docs/two_pager.qmd`, `docs/phase_1/malaysia_strategy.md`).

Review this log periodically and incorporate relevant changes into the
source documents. Delete entries after they have been addressed.

---

## 2026-02-26: S2 LOOCV changed from few-shot (n=5) to zero-shot (n=0)

**Type:** correction
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 Implementation > S2 Zero-Shot Eval
**Detail:** `_targets.R` target `c1_s2_results` changed from `n_few_shot = 5` to `n_few_shot = 0`. Strategy.md describes S2 as "Zero-Shot Eval" testing codebook sufficiency, but the implementation was passing 5 passage-level few-shot examples per LOOCV fold. The codebook YAML's built-in positive/negative examples (part of S0 specification) remain in the system prompt via `construct_codebook_prompt()` — these are always sent regardless of `n_few_shot` and are not "few-shot" in the H&K sense. Target `c1_s2_results` will need re-running.
**Suggested edit:** If strategy.md mentions few-shot examples in S2 context, clarify that S2 is zero-shot (codebook-only) and few-shot evaluation is reserved for S3 ablation or future stages.

## 2026-02-26: Test V redesigned to match H&K 4-combo specification

**Type:** correction
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > S3 Error Analysis > Behavioral Tests
**Detail:** `test_exclusion_criteria()` in `R/behavioral_tests.R` was an ablation study (removing negative_clarifications one at a time), which duplicated `run_ablation_study()` in `R/codebook_stage_3.R`. Replaced with the H&K 4-combo design: (normal/modified document) x (normal/modified codebook). Injects a monetary policy distractor paragraph and a corresponding exclusion rule, then verifies the model only applies the exclusion when both trigger and rule are present. Return structure changed from `$results` tibble (per-component accuracy drops) to `$combos` tibble (per-combo accuracy) + `$overall_consistency`. Logging in `run_error_analysis()` and notebook `c1_measure_id.qmd` updated accordingly. Target `c1_s3_results` will need re-running.
**Suggested edit:** If strategy.md describes Test V, update to reference the 4-combo (document x codebook) design rather than component ablation.

## 2026-02-26: make_chunks() now filters short chunks via min_chars parameter

**Type:** new-constraint
**Affects:** `docs/strategy.md` > C1 Implementation Blueprint > Chunk Tier System
**Detail:** `make_chunks()` gained a `min_chars = 100L` parameter (commit `144e13a`). Chunks with 100 or fewer characters are dropped as extraction artifacts (page-break markers, whitespace). The `chunks` target in `_targets.R` passes `min_chars = 100L` explicitly. Pre-flight notebook Test 2 reframed as a regression check verifying the filter is active. `validate_chunks()` also gained a corresponding `min_chars` check. This drops ~23 artifact chunks from the corpus.
**Suggested edit:** If strategy.md documents chunk parameters, add a note that `min_chars = 100` filters extraction artifacts.

## 2026-02-25: Chunk window reduced from 50 to 10 pages

**Type:** correction
**Affects:** `docs/strategy.md` > C1 Implementation Blueprint > Chunk Tier System
**Detail:** Chunk sliding window parameters changed from 50-page window / 10-page overlap to 10-page window / 3-page overlap (commit `c87283a`). This reduces LOOCV cost by ~75% while keeping all chunks within the 40K token advisory limit. The `data_overview.qmd` notebook documents the new parameters. If `docs/strategy.md` specifies chunk window size, it should be updated.
**Suggested edit:** Update any chunk window references from "50-page window, 10-page overlap" to "10-page window, 3-page overlap".

## 2026-02-25: Internal Revenue Code of 1954 excluded from evaluation data

**Type:** new-constraint
**Affects:** `docs/strategy.md` > Data Constraints; `docs/strategy.md` > C1 Implementation Blueprint
**Detail:** The Internal Revenue Code of 1954 is excluded from `aligned_data` via `exclude_acts` parameter (commit `ff9c8c9`). This act is a comprehensive codification rather than a discrete fiscal shock, making it unsuitable for C1 evaluation. Effective evaluation set is now 43 acts, not 44.
**Suggested edit:** Update "44 labeled acts" references to "43 labeled acts (44 minus Internal Revenue Code of 1954 exclusion)" where evaluation-specific, or add a footnote noting the exclusion.

## 2026-02-25: Legacy test_training_data.qmd removed from active notebooks

**Type:** status-change
**Affects:** `docs/strategy.md` > Files to Create (if listed)
**Detail:** `notebooks/test_training_data.qmd` deleted from active directory and moved to `notebooks/unused/` (commit `c2f90db`). This notebook tested the legacy Model A/B/C training data pipeline, which is superseded by the C1-C4 codebook framework. Data quality is now validated through pipeline targets and `verify_chunk_tiers.qmd`.
**Suggested edit:** None needed (notebook was not referenced in strategy.md).

## 2026-02-21: C1 S1 behavioral tests — all 4 tests pass (iteration 3)

**Type:** status-change
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 Implementation
**Detail:** C1 S1 behavioral tests pass after 3 iterations (commit `d6ce722`). Iteration 3 fixed the root cause of Test III failure: NOT_FISCAL_MEASURE negative_example 2 had reasoning that contradicted its structural label (concluded "makes this NOT_FISCAL_MEASURE" for a text whose placement required FISCAL_MEASURE). Replaced with an enacted corporate rate cut in forward-looking language. Also tightened NE-1 reasoning (removed "borderline case" hedging), which resolved Test IV order sensitivity. Added `c1_codebook_file` target (format="file") for automatic YAML change detection. Test III implementation also updated to use recall-framed prompt per H&K memorization test spec.
**Suggested edit:** Update C1 S1 status to "complete" in Phase 0 blueprint.

## ~~2026-02-19: C1 evaluation corpus filtered to max_doc_year = 2007~~ RESOLVED

**Resolved:** Added "Corpus scope" paragraph to `docs/strategy.md` > C1 Blueprint, after the Chunk Tier System table.

## 2026-02-18: C1 pipeline code and targets fully implemented

**Type:** status-change
**Affects:** `docs/strategy.md` > Step-by-Step Development (line 256) > Step 2
**Detail:** All C1 implementation files now exist: `prompts/c1_measure_id.yml` (S0 codebook), `R/behavioral_tests.R`, `R/codebook_stage_0.R` through `R/codebook_stage_3.R`, `R/generate_c1_examples.R`, and `notebooks/c1_measure_id.qmd`. Pipeline targets `c1_codebook`, `c1_s1_results`, `c1_s2_results`, `c1_s2_eval`, `c1_s3_results` are defined in `_targets.R`. Whether the targets have been executed (and results meet S1-S3 criteria) is not yet confirmed.
**Suggested edit:** Consider adding a status marker to Step 2 (e.g., "🔄 Code implemented, awaiting execution").

## 2026-02-18: C1 Files to Create section — all listed files exist

**Type:** status-change
**Affects:** `docs/strategy.md` > Files to Create (lines 335-364)
**Detail:** All codebook stage R files, `behavioral_tests.R`, `c1_measure_id.yml`, and `c1_measure_id.qmd` have been created. C2-C4 codebooks, C2-C4 notebooks, `rr6_aggregation.qmd`, and `pipeline_integration.qmd` remain to be created.
**Suggested edit:** Add ✅ markers to created files, matching the format used in `docs/phase_0/CLAUDE.md`.

## ~~2026-02-18: C1 success criteria differ between CLAUDE.md and strategy.md~~ RESOLVED

**Resolved:** Root `CLAUDE.md` updated to match strategy.md: Combined Recall ≥90%, Tier 1 Recall ≥95%, Precision ≥70%.

## 2026-02-18: Legacy Model A/B notebooks deleted from repo

**Type:** status-change
**Affects:** `docs/strategy.md` > C1 Blueprint > Migration from Legacy Code (line 285)
**Detail:** `notebooks/review_model_a.qmd` and `notebooks/review_model_b.qmd` have been deleted from the repository entirely (not moved to `notebooks/unused/`). The legacy code referenced in the Migration sections (`R/model_b_loocv.R`, `R/functions_llm.R`, etc.) still exists for reference.
**Suggested edit:** None needed in strategy.md (migration references are to R functions, not notebooks). Informational only.

