# notebooks/

Research notebooks for the Fiscal Shocks project. Every notebook is a Quarto (`.qmd`) document that reads from the `{targets}` pipeline via `tar_read()`. Notebooks test, verify, and document the data and evaluation pipeline; they do not generate data (that belongs in `R/` functions called by `_targets.R`).

## Configuration

- `_metadata.yml` -- Shared Quarto defaults for all notebooks (HTML output, `echo: true`, `code-fold`, `lightbox`, `self-contained`).
- `_targets.yaml` -- Points the targets store to `/home/user/Fiscal-shocks/_targets` so notebooks resolve `tar_read()` correctly.

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

### `verify_country_body.qmd` -- Deployment Corpus Verification

**Purpose:** Text-extraction and chunk-integrity QA across all deployment countries (currently Malaysia; future Indonesia, Thailand, Philippines, Vietnam). Runs on `country_body` and `country_chunks` before C1 deployment. Six of `verify_body.qmd`'s seven tests port directly; "Known Act Validation" is omitted (no labeled passages outside US); chunk-integrity, language audit, and era-stratified OCR quality are added.

**Key tests and decisions:**

- **(i) URL resolution and extraction success:** Per-country share of `country_urls` rows that produced extracted text in `country_body`. `manual_pending` rows excluded from the success-rate denominator. ≥95% PASS / ≥85% WARN.
- **(ii) Boundary documents:** Earliest/latest doc per country × source × body must have ≥10 pages.
- **(iii) Temporal and source coverage:** Coverage rate against the URL manifest grid; clean replacement for the US notebook's hardcoded grid since each country's URL fetcher encodes its own coverage rules.
- **(iv) Text quality:** Sampled page-level metrics with country-aware fiscal vocabulary (US: `$` + English fiscal terms; Malaysia: `RM`/`ringgit` + English + Bahasa terms). Suspicious-page rate target ≤5%; fiscal vocab presence ≥70%.
- **(v) Anomaly detection:** Diagnostic — short/long docs, suspected duplicates by first-page hash, year-on-year page drops within a series.
- **(vi) Chunk integrity:** Verifies the chunk layer (start_page=1, contiguous chunk_ids, no oversized chunks vs 190.7K context budget, marker counts match `n_pages-1`).
- **(vii) Language audit:** Bahasa stopword vs English stopword counts per chunk; flags chunks with Bahasa dominance in claimed-English docs. Diagnostic, never blocks deployment.
- **(viii) Era stratification of OCR quality:** Pre-digital vs digital-era OCR rate and special-character rate, per country (Malaysia breakpoint 1995; US 1990). Surfaces era-specific extraction quality so future SEA countries can be benchmarked.
- **Decision:** Headline gate for advancing a country corpus to C1 deployment. Test (iv) suspicious-page rate flagged the original Malaysia OCR-missing issue and now flags the residual cover/divider floor after the per-page OCR rescue went in.

### `test_text_extraction.qmd` -- PDF Extraction Quality Test

**Purpose:** Early-stage test of PyMuPDF+OCR extraction on a small sample (2 ERP PDFs). Validates that extracted text is readable, contains expected act names, preserves numeric values, and fits within LLM context windows.

**Key tests and decisions:**

- Act name detection rate, dollar amount preservation, year mention counts, fiscal terminology presence.
- Token estimation vs. Claude context window (200K tokens).
- Quality metrics dashboard (PASS/WARN/FAIL).
- **Decision:** This was a proof-of-concept for the extraction pipeline. Superseded by the more comprehensive `verify_body.qmd` for production validation.

### `data_overview.qmd` -- Training Data Overview

**Purpose:** Document the complete data transformation pipeline from raw sources to evaluation-ready datasets. Transparency document showing observation-level changes at each stage.

**Key content:**

- Data flow: `us_labels` (340 passages) + `us_shocks` (90 quarter-rows) + `us_body` (360 PDFs) --> `aligned_data` (44 acts) --> `chunks` (sliding window) --> `c1_chunk_data` (tiered evaluation sets).
- Documents the passage-to-act aggregation (grouping, concatenation with `\n\n` separator).
- Documents fuzzy matching (Jaro-Winkler, threshold 0.85) for act name alignment.
- Documents first-quarter simplification for multi-quarter acts.
- Documents chunk sliding window parameters (10-page window, 3-page overlap, 40K token advisory limit).
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

- **Corpus year filter:** Evaluation corpus filtered to `max_doc_year = 2007` (documents R&R had access to). Post-2007 documents excluded to avoid inflating Tier 2 recall via retrospective mentions.
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

### `verify_api_inputs.qmd` -- Pre-Flight API Input Verification

**Purpose:** Systematic validation of data integrity before running S2 zero-shot API calls. Runs 12 pass/fail tests on pipeline outputs to catch data issues before spending API budget.

**Key tests and decisions:**

- **T1 (Chunking completeness):** Verifies every document is fully chunked (first chunk starts at page 1, last chunk covers final page).
- **T2 (No short chunks):** Verifies `make_chunks()` `min_chars` filter is active (no chunks with <=100 characters).
- **T3 (No text-less tier rows):** Tier 1/2 rows have non-empty text after join.
- **T4 (Act name alignment):** Symmetric match between `aligned_data` and tier act names.
- **T5 (Passage delimiter integrity):** Multi-passage acts split correctly on `\n\n`.
- **T6 (Usable passages per act):** Every act has at least one passage >50 chars.
- **T7 (No within-tier duplicates):** No true duplicate rows; multi-passage matches flagged as WARN.
- **T8 (Token budget fit):** Max chunk + overhead fits within 200K context window.
- **T9 (Text encoding safety):** No null bytes or control characters in sampled chunks.
- **T10 (Year filter consistency):** Tier data respects `max_doc_year = 2007`.
- **T11 (Few-shot example preview):** Renders one fold's examples for visual inspection.
- **T12 (Summary dashboard):** Aggregates all results into PASS/WARN/FAIL dashboard.
- **Decision:** All tests must pass before proceeding to S2 zero-shot evaluation.

### `c1_measure_id.qmd` -- C1 Codebook Evaluation (S0-S3)

**Purpose:** Full H&K evaluation notebook for the C1 (Measure Identification) codebook. Reports S0 design, S1 behavioral tests, S2 zero-shot metrics, and S3 error analysis.

**Key content:**

- **S0:** Binary classification (FISCAL_MEASURE vs. NOT_FISCAL_MEASURE). Codebook structure summary, negative example stratification, evaluation data counts.
- **S1:** Behavioral test results (legal outputs, memorization, order invariance). Pass/fail dashboard.
- **S2:** Zero-shot chunk classification metrics with 95% bootstrap CIs (Recall, Precision, F1, Accuracy, Specificity). Confusion matrix. Per-act recall breakdown. Error details.
- **S3:** Test V (exclusion criteria consistency), Test VI (generic labels), Test VII (swapped labels), and ablation study (H&K Table 4 component-type ablation).
- **Status:** Reads from pipeline targets (`c1_s1_results`, `c1_s2_results`, `c1_s2_eval`, `c1_s3_results`). Notebook structure is complete; results depend on pipeline execution.

### `c0_aggregator.qmd` -- C0 Act Aggregator Method Comparison

**Purpose:** Compares strategies for collapsing C1 `measure_name` strings into act-level canonical clusters. Not an H&K S0-S3 codebook eval — methods are scored by RR-mapped recovery against the 49 Romer & Romer reference acts (keyword + Jaro-Winkler name gates, plus year alignment), with a Malaysia EN/BM paired stress test.

**Key content:**

- **Methods:** M1 Jaro-Winkler single-linkage; M2/M3 HDBSCAN (unblocked + year-blocked); M4 hybrid embedding-NN + LLM pairwise judge (Phase B pending); M5 LLM canonical clustering (`prompts/c0_canonicalize.yml`, Haiku).
- **Embedding probes:** f16 vs fp32 quantization, UMAP grid reduction, tier-1-restricted variants.
- **RR-mapped eval:** First gate = RR-act recovery (ceiling 40/49; the 9 unrecoverable are upstream C1 pool gaps); second gate = year alignment; fragmentation and spurious-rate diagnostics.
- **Status:** Reads `c0_*` pipeline targets. M5 is the leading method (v0.2.0, iter 2); see `prompts/iterations/c0.yml`.
- **Decision:** Empirical input for designing the C0 codebook. M5 single-shot matches the tuned UMAP grid on RR recovery and beats it on year alignment; bill-number prefix merges remain the open failure mode.

### `malay_consistency.qmd` -- Malaysia EN/BM Cross-Language Consistency Test

**Purpose:** Test whether the C1 → C2a → C2b pipeline produces equivalent fiscal reasoning regardless of input language, on parallel Economic Report EN+BM pairs (2014-2020 + 2022). A **consistency test, not a validity test** (no Malaysia labels; EN treated as reference because the codebooks crossed S3 gates on EN-only US data). Necessary-but-not-sufficient gate for extending deployment to the **BM-only-document slice (38 of 99 ready docs)**; not a substitute for Phase 2 expert agreement on EN-side outputs.

**Key content:**

- **Self-contained sub-pipeline:** slices `country_chunks` to ERs with parallel EN+BM coverage, runs its own C1 → C2a → C2b chain, clusters near-duplicate `measure_name` strings within each doc (JW ≤ 0.15), has **Sonnet** propose EN ↔ BM cluster matches for **human curation**, then compares C2b labels/signs on curated matched pairs. Sonnet matches (different family); Haiku runs C1/C2a/C2b (deployment model).
- **Level 1 (act counts + drift):** per-year distinct-cluster counts by language with signed drift; within-doc JW-distance heatmaps and a threshold-sensitivity sweep distinguish clustering artifacts (2015/2016 collapse as threshold relaxes) from real extraction asymmetry (2017/2018/2020 — foreign-comparator contamination, low BM recall).
- **Level 2 (matching):** 27 of 28 LLM-proposed pairs accepted (96.4% match rate); zero human-added matches — itself a finding, since BM fragments what EN aggregates so no clean 1-to-1 manual match exists.
- **Level 3 (classification agreement):** label agreement 63%, sign 74% on matched pairs (≈70.8%/70.8% after dropping 3 foreign-comparator curation artifacts) — just touching the Phase 2 C2 ≥70% floor but with a CI too wide to resolve readiness alone.
- **Known bug:** `both_high_confidence` sorts as a no-op due to an `identical()`-on-vector bug at [malay_consistency.R:752](R/malay_consistency.R#L752); confidence asymmetry not yet readable.
- **Decision:** Diagnosis over headline rates. Within-doc JW clustering is the upstream bottleneck (motivates the C0 act aggregator); C2b is robust to degraded inputs; Phase-2 BM-only readiness unresolved until clustering is fixed. Speaks only to modern professionally-translated MoF ERs (2014+) — NOT older ER BM, Budget Speech BM, or crisis-booklet BM.

## Archived Notebooks

Located in `notebooks/unused/` unless noted otherwise. These are from earlier exploratory phases and are no longer active:

- `extract_text.qmd` -- Early text extraction experiments
- `clean_text.qmd` -- Text cleaning exploration
- `embedd.qmd` -- Embedding experiments
- `identify_shocks.qmd` -- Early shock identification attempts
- `review_us.qmd` -- Early US data review
- `review_model_a.qmd` -- Legacy Model A review (deleted from repo; superseded by C1-C4 framework)
- `review_model_b.qmd` -- Legacy Model B review (deleted from repo; superseded by C1-C4 framework)
- `test_training_data.qmd` -- Legacy Model A/B/C training data quality tests (moved to `notebooks/unused/`; superseded by C1-C4 pipeline targets)

## Reading Order for New Contributors

1. `review_data.qmd` -- Understand the ground-truth data (us_shocks, us_labels)
2. `verify_body.qmd` -- Understand the document corpus (us_body)
3. `data_overview.qmd` -- Understand the full transformation pipeline
4. `identifying_known_acts.qmd` -- Understand chunk-act matching design decisions
5. `verify_chunk_tiers.qmd` -- Verify the implemented tier system
6. `verify_api_inputs.qmd` -- Pre-flight validation before S2 zero-shot evaluation
7. `c1_measure_id.qmd` -- See the C1 evaluation framework (template for C2-C4)
8. `c0_aggregator.qmd` -- See the C0 act-aggregator method comparison (RR-mapped eval; not H&K S0-S3)
9. `malay_consistency.qmd` -- See the Malaysia EN/BM cross-language consistency test (Phase 2 BM-only readiness diagnostic)

## Conventions

- New notebooks use `tinytable` (`tt()`) for tables (never `gt` or `kableExtra`). Existing notebooks may still use `gt` and will migrate when next edited.
- New notebooks load packages with `pacman::p_load()` instead of repeated `library()` calls.
- All notebooks load data via `tar_read()` from the `{targets}` pipeline
- Notebooks set `tar_config_set(store = here("_targets"))` in their setup chunk
- Existing notebooks source `R/gt_theme.R`; new notebooks should source `R/tt_theme.R` instead for consistent table styling
- Tests use PASS/WARN/FAIL status with color-coded tables (`gt` in existing notebooks, `tinytable` in new ones)
- Interpretive commentary follows each test section explaining findings and decisions
