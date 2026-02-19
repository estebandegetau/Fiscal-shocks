# Strategy Delta Log

Bottom-up discoveries from implementation that may require updates to
human-authored specification documents (`docs/strategy.md`, `docs/proposal.qmd`,
`docs/two_pager.qmd`, `docs/phase_1/malaysia_strategy.md`).

Review this log periodically and incorporate relevant changes into the
source documents. Delete entries after they have been addressed.

---

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

