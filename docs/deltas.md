# Strategy Delta Log

Bottom-up discoveries from implementation that may require updates to
human-authored specification documents (`docs/strategy.md`, `docs/proposal.qmd`,
`docs/two_pager.qmd`, `docs/phase_1/malaysia_strategy.md`).

Review this log periodically and incorporate relevant changes into the
source documents. Delete entries after they have been addressed.

---

## 2026-03-10: C1 S3 manual error analysis complete — taxpayer-liability heuristic discovered

**Type:** status-change
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 Implementation > S3 Error Analysis
**Detail:** H&K manual error analysis (iteration 16) inspected all 40 S3 baseline chunks. Distribution: 31 A (correct), 5 B (gold-standard IKA noise in Tier 2), 3 E (semantics/reasoning), 1 F (codebook ambiguity). Bias-corrected recall is 100% after excluding B chunks. The 3 Category E errors share a pattern: the model conflates government financial actions (intergovernmental transfers, education appropriations, debt management instruments) with taxpayer-liability-changing fiscal measures. The 1 Category F error reveals R&R boundary ambiguity on organizational acts with fiscal implications (Energy Independence Authority). Key insight: codebook should clarify that fiscal measures must change liabilities *to or from taxpayers*, not merely involve government financial actions affecting other entities.
**Suggested edit:** Update C1 S3 status to "manual analysis complete." Consider adding a codebook clarification distinguishing taxpayer-facing fiscal measures from other government financial actions before proceeding to C2.

## ~~2026-03-09: Stale LOOCV references in strategy.md~~ RESOLVED

**Type:** correction
**Affects:** `docs/strategy.md` > multiple S2-context sections
**Detail:** S2 was refactored from LOOCV to single-pass zero-shot classification (resolved delta 2026-03-03). Several strategy.md references still say "LOOCV" in S2 context. LOOCV remains valid only for S3 few-shot ablation.
**Suggested edit:** Replace "LOOCV" with "zero-shot classification" in all S2-context references. Keep LOOCV references that explicitly refer to S3 few-shot ablation.
**Resolved:** Incorporated into strategy.md. Replaced 9 LOOCV references in S2 contexts (Phase 0 description, C2 success criteria, codebook_stage_2.R description, C2-C4 target definitions, Verification Plan). Kept LOOCV references in S3 few-shot ablation context and C2 migration note. Rationale: S2 is zero-shot for all codebooks; LOOCV infrastructure remains available for S3 few-shot ablation if zero-shot performance requires examples.

## ~~2026-03-09: S3 ablation simplified to 4 conditions — output_instructions non-ablatable~~ RESOLVED

**Type:** correction
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > S3 Error Analysis (general description, line ~194); also any per-codebook S3 ablation descriptions
**Detail:** H&K's ablation design assumes label-only output, but our pipeline requires structured JSON via `output_instructions`. Ablating `output_instructions` breaks JSON parsing, testing format compliance rather than task understanding. Commit b99dbe8 simplified ablation from 6 to 4 conditions: `full`, `no_label_def`, `no_examples`, `no_examples_no_clarifications`. Dropped `no_output_no_examples_no_neg_clar` and redesigned `all_removed` to preserve `output_instructions` as non-ablatable infrastructure. Also added `no_clarifications` to test combined clarification impact.
**Suggested edit:** Update S3 ablation description to note that `output_instructions` is infrastructure (not ablated) and list the 4 active conditions. Add rationale: structured output requirement means output format is not a codebook component but a pipeline constraint.
**Resolved:** Incorporated into strategy.md S3 descriptions (lines 118, 289) and targets pipeline plan. Rationale: H&K's 5th ablation condition assumes plain-text label output; our structured JSON requirement makes output_instructions non-ablatable infrastructure.

## ~~2026-03-09: H&K Figure 4 metrics added to S3 behavioral tests~~ RESOLVED

**Type:** status-change
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > S3 Error Analysis (Tests V-VII descriptions)
**Detail:** Commit bceb65e added metrics needed to reproduce H&K Figure 4: Test V `all_combos_correct_rate` (fraction of texts correct on all 4 combos), Test VI `original_f1`/`generic_f1`/`f1_difference` (F1 with original vs generic labels), Test VII `swapped_f1`/`swapped_accuracy` (performance under swapped definitions). These complement the existing accuracy-based metrics with F1-based comparisons matching H&K's reporting format.
**Suggested edit:** None needed (implementation detail enriching existing metrics, not changing methodology).
**Resolved:** No strategy edit needed. Rationale: F1-based metrics enrich existing test outputs for H&K Figure 4 comparability; strategy.md describes tests in plain English, not metric-level detail.

## ~~2026-03-07: Automated H&K error categorization removed, S3 decoupled from S2~~ RESOLVED

**Type:** correction
**Affects:** `docs/strategy.md` > Files to Create > `codebook_stage_3.R` description (line 353); also `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 S3 Error Analysis Plan (line 289); C3 S3 Error Analysis Plan (line 317); C4 S3 Error Analysis Plan (line 331); S3 general description (line 194)
**Detail:** Removed `categorize_errors_hk()` from `R/codebook_stage_3.R` and the `s2_results` parameter from `run_error_analysis()`. The automated categorization binned almost everything into category E and could not distinguish mislabeled ground truth (B) from genuine model confusion (E) — a poor substitute for what H&K intended as manual expert review. Removing it decouples `c1_s3_results` from `c1_s2_results`, so behavioral tests and ablation can run independently of zero-shot evaluation. The H&K taxonomy (A-F) remains a valid *framework* for manual error review; only the automated heuristic implementation was removed.
**Suggested edit:** Update line 353 from "Run Tests V-VII, ablation studies, and error categorization using H&K 6-category taxonomy (A-F)" to "Run Tests V-VII and ablation studies." Update line 194 and per-codebook S3 plans to note that error categorization is manual, not automated. Per-codebook "Error categories" lists (lines 289, 317, 331) are domain-specific failure modes and remain valid as manual review checklists.
**Resolved:** Incorporated into strategy.md: updated codebook_stage_3.R description, iteration strategy step 1, C1 S3 plan, and all S3 target definitions (removed s2_results dependency). Rationale: automated categorization binned everything into category E; H&K intended manual expert review. Decoupling S3 from S2 prevents unnecessary re-runs when switching models for behavioral tests.

## ~~2026-03-04: C1 success criteria revision — gate on Tier 1 recall, demote combined recall to diagnostic~~ RESOLVED

**Type:** new-constraint
**Affects:** `docs/strategy.md` > Success Criteria Per Codebook > C1 row; also `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 Implementation
**Detail:** C1 S2 v0.4.0 (iteration 12) revealed that Tier 2 labels depend on a noisy name-matching heuristic (53/70 Tier 1 chunks lack the act name; Tier 2 has known gaps for acronyms and compound names). Combined recall (83.7%) is dominated 10:1 by Tier 2 chunks, making it an unreliable gate. Tier 1 labels are high-confidence (verbatim R&R passage matches). Proposed revision: Tier 1 Recall ≥95% becomes the primary gate, Precision ≥70% remains, Combined Recall becomes diagnostic (reported but not gated). The 4 Tier 1 FNs are mislabeled positives (R&R context passages without identifiable fiscal measures), so true Tier 1 recall is likely ~100%.
**Suggested edit:** Change C1 success criteria table row from "Combined Recall ≥90%, Tier 1 Recall ≥95%, Precision ≥70%" to "Tier 1 Recall ≥95% (primary gate), Precision ≥70% (primary gate), Combined Recall (diagnostic, no gate)." Add note explaining Tier 2 label noise rationale.
**Resolved:** Incorporated into strategy.md. All three C1 metrics demoted to diagnostic benchmarks (not hard gates). Added note explaining label noise rationale and that S3 manual error audit is the actual stage gate. Rationale: ground truth label set is noisy (Tier 2 name-matching misses acronyms/compound names; FPs include real acts absent from the 44-act set), so hard gating on automated metrics is not feasible. Manual examination in S3 determines whether the model outperforms the artisan identification approach.

## ~~2026-03-04: C1 S2 v0.4.0 — label bias discovered in both recall and precision~~ RESOLVED

**Type:** new-constraint
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 Implementation > S2 description
**Detail:** C1 S2 iteration 12 found systematic label noise in both directions. (1) Recall bias: 4 Tier 1 FNs are mislabeled positives — chunks contain R&R passages cited for motivation context but no identifiable fiscal measure. Model correctly rejects them. (2) Precision bias: 35 FPs are predominantly real fiscal measures not in the 44-act label set (H&K Error Category F). Both metrics are conservative lower bounds. S3 error analysis will include a manual audit to estimate label error rates and compute bias-corrected metrics.
**Suggested edit:** Add note to C1 S2 description: "Reported metrics are conservative lower bounds due to IKA label noise. S3 includes bias estimation via manual FN/FP audit."
**Resolved:** No standalone edit — incorporated into the C1 success criteria revision (S2 metrics now described as "conservative bounds due to label noise; S3 manual audit is the actual stage gate"). C2-C4 cascading implications deferred to after C1 S3 manual evaluation.

## ~~2026-03-03: C1 v0.4.0 reframe removes enacted filter — contradicts strategy.md line 279~~ RESOLVED

**Resolved:** Removed "proposals that did not become law" from C1 exclusion criteria, updated note to cover enacted-status filtering deferred to C2, added enacted-status determination note to C2 blueprint.

## ~~2026-03-03: C1 S2 refactored from LOOCV to single-pass zero-shot~~ RESOLVED

**Resolved:** Updated C1 S2 description to "Zero-Shot Eval" with single-pass classification, 3-target pipeline, and note that LOOCV is reserved for S3 few-shot ablation. Updated targets code block accordingly.

## ~~2026-03-02: C1 S1 declared complete — proceeding to S2~~ RESOLVED

**Resolved:** Status update acknowledged. No strategy.md edit needed (status tracked in CLAUDE.md).

## ~~2026-02-28: raw_response preservation added to classify_with_codebook()~~ RESOLVED

**Type:** new-constraint
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > All codebooks
**Detail:** `classify_with_codebook()` now returns `raw_response` (the raw LLM output text) alongside parsed fields. This flows through S1 behavioral tests (`behavioral_tests.R`), S2 LOOCV (`codebook_stage_2.R`), and the self-consistency path (`functions_self_consistency.R`). Previously, when JSON parsing failed, the raw response was discarded, making diagnosis impossible. Discovered during C1 S1 iteration 4 where 2/20 chunks returned invalid JSON with no way to inspect what the model said.
**Suggested edit:** None needed (implementation detail, not strategy-level).
**Resolved:** No strategy edit needed. Rationale: raw_response capture is debugging infrastructure, not a methodology change.

## ~~2026-02-28: C1 S1 iteration 4 — exploration run on Qwen 2.5 72B via OpenRouter~~ RESOLVED

**Type:** status-change
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 Implementation
**Detail:** C1 S1 run on `qwen/qwen-2.5-72b-instruct` via OpenRouter (iteration 4, codebook v0.2.0). Test I failed at 90% (2/20 invalid JSON), Tests II-IV all pass. This was a proof-of-concept validating OpenRouter integration for cost-effective exploration. Per `_targets.R` comment: "Non-Anthropic providers are for cost/feasibility exploration only. Mixing providers invalidates stage comparability." Decision: re-run S1 on Qwen with raw_response capture to diagnose failures.
**Suggested edit:** None needed (exploration run, not a stage gate).
**Resolved:** No strategy edit needed. Rationale: proof-of-concept for OpenRouter integration; not a stage gate crossing.

## ~~2026-02-27: Docling/Lambda infrastructure removed, PyMuPDF is sole extraction method~~ RESOLVED

**Type:** status-change
**Affects:** `docs/phase_1/malaysia_strategy.md` > Phase 2A Deployment Checklist (line 264)
**Detail:** Commit `f250afc` removed all Docling and Lambda infrastructure: `python/docling_extract.py`, `python/lambda_handler.py`, `R/pull_text_lambda.R`, `pull_text_docling()` function, DOCLING_* env vars, and docling/sentence-transformers/torch from requirements.txt. The sole active extraction method is `pull_text_local()` using PyMuPDF+OCR. Line 264 of malaysia_strategy.md reads "Run PDF extraction (Docling or pdftools)" and should be updated.
**Suggested edit:** Change "Run PDF extraction (Docling or pdftools)" to "Run PDF extraction (PyMuPDF or pdftools)".
**Resolved:** Incorporated into `docs/phase_1/malaysia_strategy.md` line 264. Rationale: Docling/Lambda infrastructure fully removed; PyMuPDF is the sole active extraction method.

## ~~2026-02-27: Test IV enhanced to 3 orderings + Fleiss's kappa (all codebooks)~~ RESOLVED

**Resolved:** Updated C1 Test IV description to "original, reversed, and shuffled class orderings" with degenerate binary case note, matching C2 description.

## ~~2026-02-27: C1 codebook aligned with RR criteria, country-agnostic (v0.2.0)~~ RESOLVED

**Type:** status-change
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 Implementation
**Detail:** C1 codebook (`prompts/c1_measure_id.yml`) updated to v0.2.0 with five changes: (1) dropped "spending authorizations" to match RR's tax-only scope, (2) broadened executive action language for non-US contexts (ministerial decrees, regulatory changes, official policy directives), (3) added "significance = discussion depth, not revenue size" clarification from RR, (4) added "lists" exclusion for summary tables and measure enumerations per RR, (5) tightened retrospective references with concrete examples. S1 behavioral tests will need re-running on v0.2.0.
**Suggested edit:** If strategy.md specifies codebook scope as including spending measures, update to reflect tax-only scope per RR.
**Resolved:** Incorporated into strategy.md C1 S0 description. Added explicit tax-only scope, country-agnostic executive action language (ministerial decrees, regulatory changes, official policy directives), "lists" exclusion, and transfer learning note. Rationale: tax-only scope matches R&R methodology; country-agnostic language is the key mechanism for cross-country transfer.

## ~~2026-02-27: C1 codebook restructured — description merged, examples removed~~ RESOLVED

**Resolved:** Updated `codebook_stage_0.R` description to list `description`, `positive_examples`, `negative_examples` as optional fields.

## ~~2026-02-26: S2 LOOCV changed from few-shot (n=5) to zero-shot (n=0)~~ RESOLVED

**Resolved:** C1 S2 description updated to explicitly state "no few-shot examples" and note LOOCV reserved for S3 few-shot ablation.

## ~~2026-02-26: Test V redesigned to match H&K 4-combo specification~~ RESOLVED

**Resolved:** Updated C1 Test V description to H&K 4-combo design (normal/modified document × normal/modified codebook).

## ~~2026-02-26: make_chunks() now filters short chunks via min_chars parameter~~ RESOLVED

**Resolved:** Added "Chunk parameters" paragraph to C1 blueprint noting 10-page window, 3-page overlap, and `min_chars = 100` filter.

## ~~2026-02-25: Chunk window reduced from 50 to 10 pages~~ RESOLVED

**Resolved:** Added "Chunk parameters" paragraph to C1 blueprint noting 10-page window and 3-page overlap.

## ~~2026-02-25: Internal Revenue Code of 1954 excluded from evaluation data~~ RESOLVED

**Resolved:** Updated Phase 0 table (44 → 43 after exclusion note), S2 table (44 → 43), and C1 S2 description (43 acts). Kept "44" where it refers to the full label set.

## ~~2026-02-25: Legacy test_training_data.qmd removed from active notebooks~~ RESOLVED

**Type:** status-change
**Affects:** `docs/strategy.md` > Files to Create (if listed)
**Detail:** `notebooks/test_training_data.qmd` deleted from active directory and moved to `notebooks/unused/` (commit `c2f90db`). This notebook tested the legacy Model A/B/C training data pipeline, which is superseded by the C1-C4 codebook framework. Data quality is now validated through pipeline targets and `verify_chunk_tiers.qmd`.
**Suggested edit:** None needed (notebook was not referenced in strategy.md).
**Resolved:** No strategy edit needed. Rationale: legacy notebook superseded by C1-C4 codebook framework; not referenced in strategy.md.

## ~~2026-02-21: C1 S1 behavioral tests — all 4 tests pass (iteration 3)~~ RESOLVED

**Type:** status-change
**Affects:** `docs/strategy.md` > Phase 0 Implementation Blueprint > C1 Implementation
**Detail:** C1 S1 behavioral tests pass after 3 iterations (commit `d6ce722`). Iteration 3 fixed the root cause of Test III failure: NOT_FISCAL_MEASURE negative_example 2 had reasoning that contradicted its structural label (concluded "makes this NOT_FISCAL_MEASURE" for a text whose placement required FISCAL_MEASURE). Replaced with an enacted corporate rate cut in forward-looking language. Also tightened NE-1 reasoning (removed "borderline case" hedging), which resolved Test IV order sensitivity. Added `c1_codebook_file` target (format="file") for automatic YAML change detection. Test III implementation also updated to use recall-framed prompt per H&K memorization test spec.
**Suggested edit:** Update C1 S1 status to "complete" in Phase 0 blueprint.
**Resolved:** Incorporated into strategy.md. Added "(complete)" to C1 S1 Behavioral Tests heading. Rationale: S1 passed after 3 iterations (commit d6ce722).

## ~~2026-02-19: C1 evaluation corpus filtered to max_doc_year = 2007~~ RESOLVED

**Resolved:** Added "Corpus scope" paragraph to `docs/strategy.md` > C1 Blueprint, after the Chunk Tier System table.

## ~~2026-02-18: C1 pipeline code and targets fully implemented~~ RESOLVED

**Type:** status-change
**Affects:** `docs/strategy.md` > Step-by-Step Development (line 256) > Step 2
**Detail:** All C1 implementation files now exist: `prompts/c1_measure_id.yml` (S0 codebook), `R/behavioral_tests.R`, `R/codebook_stage_0.R` through `R/codebook_stage_3.R`, `R/generate_c1_examples.R`, and `notebooks/c1_measure_id.qmd`. Pipeline targets `c1_codebook`, `c1_s1_results`, `c1_s2_results`, `c1_s2_eval`, `c1_s3_results` are defined in `_targets.R`. Whether the targets have been executed (and results meet S1-S3 criteria) is not yet confirmed.
**Suggested edit:** Consider adding a status marker to Step 2 (e.g., "🔄 Code implemented, awaiting execution").
**Resolved:** Incorporated into strategy.md. Updated Step 2 with status marker reflecting current progress (S1 complete, S2 evaluated, S3 in progress).

## ~~2026-02-18: C1 Files to Create section — all listed files exist~~ RESOLVED

**Type:** status-change
**Affects:** `docs/strategy.md` > Files to Create (lines 335-364)
**Detail:** All codebook stage R files, `behavioral_tests.R`, `c1_measure_id.yml`, and `c1_measure_id.qmd` have been created. C2-C4 codebooks, C2-C4 notebooks, `rr6_aggregation.qmd`, and `pipeline_integration.qmd` remain to be created.
**Suggested edit:** Add ✅ markers to created files, matching the format used in `docs/phase_0/CLAUDE.md`.
**Resolved:** Incorporated into strategy.md. Added ✅ markers to all created files (c1_measure_id.yml, codebook_stage_0-3.R, behavioral_tests.R, c1_measure_id.qmd). C2-C4 codebooks and notebooks remain unmarked.

## ~~2026-02-18: C1 success criteria differ between CLAUDE.md and strategy.md~~ RESOLVED

**Resolved:** Root `CLAUDE.md` updated to match strategy.md: Combined Recall ≥90%, Tier 1 Recall ≥95%, Precision ≥70%.

## ~~2026-02-18: Legacy Model A/B notebooks deleted from repo~~ RESOLVED

**Type:** status-change
**Affects:** `docs/strategy.md` > C1 Blueprint > Migration from Legacy Code (line 285)
**Detail:** `notebooks/review_model_a.qmd` and `notebooks/review_model_b.qmd` have been deleted from the repository entirely (not moved to `notebooks/unused/`). The legacy code referenced in the Migration sections (`R/model_b_loocv.R`, `R/functions_llm.R`, etc.) still exists for reference.
**Suggested edit:** None needed in strategy.md (migration references are to R functions, not notebooks). Informational only.
**Resolved:** No strategy edit needed. Rationale: legacy notebooks deleted; migration references in strategy.md point to R functions which still exist.

