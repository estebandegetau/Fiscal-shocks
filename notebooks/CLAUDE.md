# notebooks/

Research notebooks for the Fiscal Shocks project. Every notebook is a Quarto (`.qmd`) document that reads from the `{targets}` pipeline via `tar_read()`. Notebooks test, verify, and document the data and evaluation pipeline; they do not generate data (that belongs in `R/` functions called by `_targets.R`).

## Configuration

- `_metadata.yml` -- Shared Quarto defaults for all notebooks (HTML output, `echo: true`, `code-fold`, `lightbox`, `self-contained`).
- `_targets.yaml` -- Points the targets store to `/workspaces/Fiscal-shocks/_targets` so notebooks resolve `tar_read()` correctly.

## Active Notebooks

### `review_data.qmd` -- Training Data Audit

**Purpose:** Audit the two ground-truth datasets (`us_shocks.csv`, `us_labels.csv`) that anchor all codebook evaluation.

**Key tests and decisions:**

- Confirms 49 acts in `us_shocks` and 40 acts in `us_labels`, with 40 in both datasets. The 9 shocks-only acts lack extracted quotation passages but retain full narrative text in the Reasoning column.
- Validates motivation category distribution: 26 exogenous vs. 23 endogenous acts. Four motivation types (Spending-driven, Countercyclical, Deficit-driven, Long-run) are consistently applied.
- Identifies 9 mixed-motivation acts (18%) that serve as hard cases for C2 evaluation.
- Cross-references labels vs. shocks for category/exogeneity consistency (all match).
- Reports 372 evidence passages across 40 acts (median 8 per act).
- **Decision:** Data is ready for codebook development. No quality issues found.

### `verify_body.qmd` -- Document Extraction Verification

**Purpose:** Verify PDF extraction quality and corpus completeness for `us_body`. Parameterized for country (currently US).

**Key tests and decisions:**

- **(i) URL Resolution:** 97.2% extraction success (350/360 documents). 10 failures are supplementary Budget PDFs with non-standard URLs; no critical years affected.
- **(ii) Boundary Documents:** All boundary documents (earliest/latest per source) have sufficient pages.
- **(iii) Known Act Validation:** 84.8% recall with expanded year window (year to year+2), accounting for retrospective ERP discussion. 7 missing acts have identifiable causes (compound names, Public Law numbers, date mismatches in labels).
- **(iv) Temporal Coverage:** 95%+ coverage across ERP, Budget, Treasury, and CBO documents (1946-2022).
- **(v) Text Quality:** Fiscal vocabulary present in 70%+ of pages; low suspicious page rate.
- **(vi) Anomalies:** 64 short Budget section PDFs (by design), 17 long early-era volumes (legitimate), 7 CBO boilerplate duplicates (expected).
- **Decision:** RR1 source coverage confirmed with 4 of 9 R&R source types. Corpus ready for chunking and Phase 0.

### `test_text_extraction.qmd` -- PDF Extraction Quality Test

**Purpose:** Early-stage test of PyMuPDF+OCR extraction on a small sample (2 ERP PDFs). Validates that extracted text is readable, contains expected act names, preserves numeric values, and fits within LLM context windows.

**Key tests and decisions:**

- Act name detection rate, dollar amount preservation, year mention counts, fiscal terminology presence.
- Token estimation vs. Claude context window (200K tokens).
- Quality metrics dashboard (PASS/WARN/FAIL).
- **Decision:** This was a proof-of-concept for the extraction pipeline. Superseded by the more comprehensive `verify_body.qmd` for production validation.

### `test_training_data.qmd` -- Training Data Quality Tests

**Purpose:** Comprehensive test suites (7 suites, 23 tests) verifying all training data generated for the legacy Model A/B/C framework. Tests alignment, splits, class balance, negative example quality, and cross-dataset consistency.

**Key tests and decisions:**

- **Suite 1 (Alignment):** 44/44 acts aligned (100%), median 8 passages per act, no missing fields.
- **Suite 2 (Splits):** 64/23/14% split (target 60/20/20). Test set deviation is a mathematical constraint with 44 acts + stratification, not a data error. No data leakage.
- **Suite 3 (Model A):** 1:4.5 class balance, 0% negative contamination, reasonable text lengths.
- **Suite 4 (Model B):** All 4 motivation categories present. 100% exogenous flag consistency. Countercyclical under-represented (6 acts, 0 in test set).
- **Suite 5 (Model C):** 41/41 acts have complete timing and magnitude. Both tax increases and cuts represented.
- **Suite 6 (Chunks):** 199/304 documents chunked (65.5%, reflecting extraction failures). Median 37K tokens, max 155K. 10-page overlap working correctly.
- **Suite 7 (Cross-Dataset):** 100% act name consistency and split consistency across all datasets.
- **Decision:** 22/23 tests pass. Single failure (split ratio) accepted for Phase 0. Data suitable for codebook development.

### `data_overview.qmd` -- Training Data Overview

**Purpose:** Document the complete data transformation pipeline from raw sources to evaluation-ready datasets. Transparency document showing observation-level changes at each stage.

**Key content:**

- Data flow: `us_labels` (340 passages) + `us_shocks` (90 quarter-rows) + `us_body` (360 PDFs) --> `aligned_data` (44 acts) --> `chunks` (sliding window) --> `c1_chunk_data` (tiered evaluation sets).
- Documents the passage-to-act aggregation (grouping, concatenation with `\n\n` separator).
- Documents fuzzy matching (Jaro-Winkler, threshold 0.85) for act name alignment.
- Documents first-quarter simplification for multi-quarter acts.
- Documents chunk sliding window parameters (50-page window, 10-page overlap, 160K token advisory limit).
- Documents the three-tier chunk classification: Tier 1 (verbatim passage match), Tier 2 (act name + keyword co-occurrence), Negative (no fiscal signals).
- Context window budget analysis showing all chunks fit within 200K with ~9.3K overhead.
- **Key findings:** 44 labeled acts (not 126), median 8 passages per act, multi-quarter acts (median 7 quarters), tier coverage gaps for some acts.

### `identifying_known_acts.qmd` -- Known Act Identification Strategies (Design Notebook)

**Purpose:** Investigate and solve the problem of matching labeled acts to document chunks. Explores why current Tier 2 matching misses 5 acts and proposes improvements. This is the **design notebook** that drove the implementation in `R/identify_chunk_tiers.R`; for programmatic verification of the implemented system, see `verify_chunk_tiers.qmd`.

**Key tests and decisions:**

- **OCR line breaks:** `str_squish()` normalization recovers substantial matches (some acts double their count) but doesn't rescue 5 structurally unmatched acts.
- **Five unmatched acts:** Compound names ("Taxpayer Relief Act of 1997 and Balanced Budget Act of 1997"), descriptive event labels ("Expiration of Excess Profits Tax..."), and Public Law numbers (89-800, 90-26).
- **Subcomponent decomposition:** Split on "and", extract parenthetical descriptions, find embedded formal names, Public Law numbers. All 5 acts become findable.
- **Broad term exclusions:** Identified 5 overly broad phrases ("investment tax credit", "balanced budget", etc.) that must be excluded from Tier 2 matching.
- **Excess Profits Tax deep-dive:** Co-occurrence matching ("expiration" AND "excess profits") is precise (18 chunks) vs. the overly broad single-term match (336 chunks).
- **Negative rethinking:** Proposes replacing binary easy/hard negative distinction with continuous `key_density` score for S3 error analysis.
- **Decision:** Implement whitespace normalization + subcomponent matching + co-occurrence for compound names. Relax negative criterion to include all non-positive chunks tagged with key density.

### `verify_chunk_tiers.qmd` -- Chunk Tier Verification

**Purpose:** Programmatic verification of the chunk tier identification system implemented in `R/identify_chunk_tiers.R`. Tests the pipeline output for correctness and completeness.

**Key tests and decisions:**

- **Tier distribution:** Three-tier breakdown (Tier 1 verbatim, Tier 2 name match, Negative with key_density). No gray zone.
- **Coverage check:** PASS/FAIL for all 44 acts having at least one tier match. Flags uncovered acts.
- **Per-act chunk matches:** Tier 1/2/total counts per act, sorted by total descending.
- **Matching mechanism breakdown:** Which mechanisms (full name, split-on-and, parenthetical, co-occurrence, etc.) produce matches for each act. Uses `generate_subcomponents()` and `COOCCURRENCE_RULES` from `R/identify_chunk_tiers.R`.
- **Temporal consistency:** Document-year distributions and year-difference analysis for matching chunks. Color-coded precision summary.
- **Tier overlap:** Verifies Tier 1 and Tier 2 are mutually exclusive (zero overlap expected).
- **Token distribution:** Checks for systematic size bias across tiers.
- **Key density distribution:** Histogram and binned summary of `key_density` in negative pool.
- **Negative quality check:** Contamination rate (act names in negatives) and source type distribution.
- **Summary dashboard:** PASS/FAIL/WARN status for all checks.

### `c1_measure_id.qmd` -- C1 Codebook Evaluation (S0-S3)

**Purpose:** Full H&K evaluation notebook for the C1 (Measure Identification) codebook. Reports S0 design, S1 behavioral tests, S2 LOOCV metrics, and S3 error analysis.

**Key content:**

- **S0:** Binary classification (FISCAL_MEASURE vs. NOT_FISCAL_MEASURE). Codebook structure summary, negative example stratification, evaluation data counts.
- **S1:** Behavioral test results (legal outputs, memorization, order invariance). Pass/fail dashboard.
- **S2:** LOOCV metrics with 95% bootstrap CIs (Recall, Precision, F1, Accuracy, Specificity). Confusion matrix. Per-act recall breakdown. Error details.
- **S3:** Error category distribution, ablation study (component importance ranking), Test VI (generic labels), Test VII (swapped labels to check definition vs. name following).
- **Status:** Reads from pipeline targets (`c1_s1_results`, `c1_s2_results`, `c1_s2_eval`, `c1_s3_results`). Notebook structure is complete; results depend on pipeline execution.

## Archived Notebooks

Located in `notebooks/unused/` unless noted otherwise. These are from earlier exploratory phases and are no longer active:

- `extract_text.qmd` -- Early text extraction experiments
- `clean_text.qmd` -- Text cleaning exploration
- `embedd.qmd` -- Embedding experiments
- `identify_shocks.qmd` -- Early shock identification attempts
- `review_us.qmd` -- Early US data review
- `review_model_a.qmd` -- Legacy Model A review (deleted from repo; superseded by C1-C4 framework)
- `review_model_b.qmd` -- Legacy Model B review (deleted from repo; superseded by C1-C4 framework)

## Reading Order for New Contributors

1. `review_data.qmd` -- Understand the ground-truth data (us_shocks, us_labels)
2. `verify_body.qmd` -- Understand the document corpus (us_body)
3. `data_overview.qmd` -- Understand the full transformation pipeline
4. `test_training_data.qmd` -- Verify data quality (legacy test suite, still informative)
5. `identifying_known_acts.qmd` -- Understand chunk-act matching design decisions
6. `verify_chunk_tiers.qmd` -- Verify the implemented tier system
7. `c1_measure_id.qmd` -- See the C1 evaluation framework (template for C2-C4)

## Conventions

- All notebooks use `gt` for tables (never `kableExtra`)
- All notebooks load data via `tar_read()` from the `{targets}` pipeline
- Notebooks set `tar_config_set(store = here("_targets"))` in their setup chunk
- Most notebooks source `R/gt_theme.R` for consistent table styling
- Tests use PASS/WARN/FAIL status with color-coded gt tables
- Interpretive commentary follows each test section explaining findings and decisions
