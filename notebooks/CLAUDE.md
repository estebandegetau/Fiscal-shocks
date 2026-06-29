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

**Purpose:** Two-part H&K results notebook for the C1 (Measure Identification) codebook: (1) the full final-iteration (v0.7.0) battery mimicking the Halterman & Keith presentables, and (2) the development history sourced programmatically from the iteration log so log edits invalidate the figures/tables.

**Key content:**

- **Part 1 — Final codebook (v0.7.0), live targets.** S0 codebook/negatives/data summary tables; the **full assembled prompt** the LLM saw (`construct_codebook_prompt()` from `R/codebook_stage_0.R`, US tokens resolved). H&K Figure 3 (S1, via `plot_s1_behavioral()`); S2 metrics (`tt_s2_metrics_table()`) plus live detail not in the log — confusion matrix, per-act recall, multi-measure act recall, error examples (`c1_s2_eval`). H&K Figure 4 (S3, via `plot_s3_behavioral()`); ablation Table 4 (`tt_ablation_table()`); the v0.7.0 multi-measure diagnostics (over-listing, country distribution, under-listing from `c1_s3_results`). Manual error analysis Table 5 (`tt_manual_analysis_table()`) + bias-corrected gate metrics (`tt_bias_corrected_table()`).
- **Part 2 — Development history, log-sourced.** Iteration timeline; performance trajectories (`plot_metric_trajectory()`); a per-version narrative rendering the `interpretation`/`decision` prose from the log.
- **Data sourcing.** Standard H&K figures/tables come from `tar_read(iteration_logs)` filtered to the latest formal (Claude) C1 iteration via an inline `latest()` helper (numerically identical to the live run; log edits re-render them). Live targets (`c1_codebook`, `c1_s2_eval`, `c1_s3_results`) supply only the richer detail and the prompt not captured in the log.
- **Reuse.** H&K plot helpers and the `tt_*` table helpers live in `R/iteration_reporting.R` (shared with `iteration_summary.qmd`, which still uses the `gt_*` variants). The cross-codebook rollup is `iteration_summary.qmd`.
- **Conventions.** Uses tinytable (`tt()` + `tt_theme_report()`) and `pacman::p_load()`.

### `c0_aggregator.qmd` -- C0 Act Aggregator Method Comparison

**Purpose:** Compares strategies for collapsing C1 `measure_name` strings into act-level canonical clusters. Not an H&K S0-S3 codebook eval — methods are scored by RR-mapped recovery against the 49 Romer & Romer reference acts (keyword + Jaro-Winkler name gates, plus year alignment), with a Malaysia EN/BM paired stress test.

**Key content:**

- **Methods:** M1 Jaro-Winkler single-linkage; M2/M3 HDBSCAN (unblocked + year-blocked); M4 hybrid embedding-NN + LLM pairwise judge (Phase B pending); M5 LLM canonical clustering (`prompts/c0_canonicalize.yml`, Haiku).
- **Embedding probes:** f16 vs fp32 quantization, UMAP grid reduction, tier-1-restricted variants.
- **RR-mapped eval:** First gate = RR-act recovery (ceiling 40/49; the 9 unrecoverable are upstream C1 pool gaps); second gate = year alignment; fragmentation and spurious-rate diagnostics.
- **Status:** Reads `c0_*` pipeline targets. M5 is the leading method (v0.2.0, iter 2); see `prompts/iterations/c0.yml`.
- **Decision:** Empirical input for designing the C0 codebook. M5 single-shot matches the tuned UMAP grid on RR recovery and beats it on year alignment; bill-number prefix merges remain the open failure mode.

### `malay_consistency.qmd` -- Malaysia EN/BM Cross-Language Consistency Test

**Purpose:** Test whether the full **C1 → C0 → C2** pipeline produces equivalent fiscal reasoning regardless of input language, on parallel Economic Report EN+BM pairs (2014-2020 + 2022). A **consistency test, not a validity test** (no Malaysia labels; EN treated as reference because the codebooks crossed S3 gates on EN-only US data). Necessary-but-not-sufficient gate for extending deployment to the **BM-only-document slice (38 of 99 ready docs)**; not a substitute for Phase 2 expert agreement on EN-side outputs.

**Reworked 2026-06-03** around the C0 act aggregator (replaced the within-doc Jaro-Winkler clusterer) and **dropped the Sonnet matcher + human-curation step** (it injected an unverified LLM judgment into the headline). Comparison is now distributional + visual, no auxiliary-API matching.

**Key content:**

- **Self-contained sub-pipeline:** slices `country_chunks` to ERs with parallel EN+BM coverage, runs its own C1 → C2a chain, then aggregates measure names into acts with **C0** (M5 LLM canonical clustering, `prompts/c0_canonicalize.yml`, Haiku) at **three scopes** — per-document (granular aggregation), per-language (deployment-realistic; feeds C2 + timeline), joint EN+BM (cross-language merge probe). C2b classifies every per-language act (no pairing).
- **Plots over tables (2026-06-05):** the diagnostic tables were converted to figures for an external-paper audience, and body prose was scrubbed of code/file identifiers (margin notes/callouts left as internal caveats). New `plot_malay_*` helpers in `R/malay_consistency.R`: `plot_malay_scope` (a Scope subsection — pages + chunks per doc-year-language), `plot_malay_c1_comparability`, `plot_malay_c0_perdoc`, `plot_malay_c0_perlang_labels` (neat motivation labels via `pretty_motivation()`), `plot_malay_act_years`. Only `tbl-c0-perlang-counts` and `tbl-c0-joint` remain as tables.
- **C1-step comparability:** distinct C1 measure-name counts per year by language (pre-aggregation drift, now `fig-c1-comparability`); carries forward the foreign-comparator contamination + 2018-BM low-recall residuals as C1-level (not aggregation) findings.
- **C0 aggregation diagnostics:** per-doc compression figure (does C0 aggregate symmetrically across languages where JW fragmented BM more?); per-language act-count / exo-endo tables + label-marginal figure; joint cross-language merge rate (does C0 bridge *Subsidi Bahan Api* ↔ *fuel subsidy*?).
- **Headline — final-output consistency:** act-name-year multiset figure by language plus **two timeline figures** (`plot_malay_act_timeline()`, timing = act-name year vs. source-doc year). Reworked to **diverging stacked bars**: acts counted per year × language × motivation × sign, increases growing the bar upward and decreases downward, colour = motivation (neat labels), faceted by language. The "BM over-uses LONG_RUN" signal survives as a label-marginal shift without pairing.
- **Decision:** Data/statistical evidence only — tallies + timeline, no untrusted matcher. The dropped matcher's verification role is replaced by an eyeball audit of joint-scope mixed clusters. Speaks only to modern professionally-translated MoF ERs (2014+) — NOT older ER BM, Budget Speech BM, or crisis-booklet BM.

### `deployment.qmd` -- Cross-Country Deployment Headline

**Purpose:** The deployment headline — end-to-end output of the validated **C1 → C0 → C2** pipeline run on each deployment country's full corpus. Presents the same figures/tables as `malay_consistency.qmd` but with the comparison axis swapped from **language (EN/BM)** to **country**. A deployment inventory, **not a validity test**: no ground-truth labels exist for any deployment country, so the act-level outputs are inputs requiring Phase 2 expert validation (≥80% C1, ≥70% C2 agreement), not findings. Today only Malaysia is deployed; the notebook auto-extends to a panel per country as Indonesia, Thailand, the Philippines, and Vietnam are onboarded.

**Key content:**

- **Reads existing deployment targets** (`country_chunks`, `country_c1_measures`, `country_c0_clusters`, `country_c0_acts`, `country_c2b`, `country_measure_pool`); tallies computed inline (no `_targets.R` change). Helpers in `R/deployment_report.R`: `bind_country()` (positional-zip country identity onto the country-less branched targets), `compute_deployment_tallies()` (its `inventory` now carries the act-level `year`, `enacted`, `n_evidence_items`, `n_chunks`, `cluster_id`), `inventory_marginals()` (counts/labels from any inventory subset), `mark_chosen_acts()` (per-country relevance + 80% cut), `compute_deployment_scope_tally()`, and the `plot_deployment_*` family. Reuses `pretty_motivation()` + the motivation palette from `R/malay_consistency.R` (unmodified).
- **Scope:** pages/chunks per country × document year (`fig-scope`) + per-country headline tally (`tbl-scope`: years analysed, documents, pages, chunks, surfaced/clustered/exogenous measures, over all acts).
- **C1-step comparability:** surfaced fiscal measures (= `country_c1_measures`) per year by country (`fig-c1-comparability`). The rank-1 framing and the measure-density/fiscal-rate subsection were removed (2026-06-11) — the deployment no longer foregrounds the rank-1 filter mechanism.
- **C0 aggregation diagnostics:** merge rate ((surfaced/acts) − 1) per year (`fig-c0-perdoc`); per-country cluster summary (`tbl-c0-summary`: measure variants, acts, merge rate, N singletons, largest cluster — the per-country analog of the consistency report's joint EN/BM merge probe; acts are clustered within each country only, never merged across countries).
- **Identification by frequency (2026-06-11):** R&R's "significant change" language over-identifies through the LLM chain, so acts are ranked by a frequentist relevance proxy `relevance = n_evidence_items × n_chunks` (over enacted, in-range acts) and the top set accumulating 80% of relevance is kept (`mark_chosen_acts`, per country). `fig-relevance-scatter`, `fig-acts-chosen`, `fig-chosen-count`, and `tbl-top-20` (chosen acts; cluster-id suffixes stripped; footnoted year/evidence/effect definitions). Everything from the act-inventory marginals onward (`tbl-c0-counts`, `fig-c0-labels`, the timeline) is restricted to the chosen set.
- **Headline — act inventory timeline:** a single diverging-stacked-bar figure (`fig-timeline`, increases up, decreases down, no-change at baseline, colour = motivation, faceted by country), dated by the single act-level `year` (`timing = "year"` in `plot_deployment_act_timeline`). The earlier dual doc-year/act-name timelines and `fig-act-years` were collapsed/removed (2026-06-11). All year-x figures use 5-year axis breaks (numeric year axis).
- **Decision:** Deployment deliverable / expert-review starting point. Comparable structure across countries (similar merge rate, plausible motivation marginals, no degenerate years) is the signal that the country-agnostic codebooks transferred. Uses tinytable + `pacman::p_load()`.

### `cit_identification.qmd`, `pit_identification.qmd`, `vat_identification.qmd` -- Statutory Tax-Shock Identification (per instrument)

**Purpose:** Provenance notebooks for the per-instrument statutory tax-shock datasets, one per instrument — corporate income tax (CIT), personal income tax (PIT), and broad consumption tax (CONSUMPTION = VAT/GST/SST). Each documents an **AI-assisted manual identification** pass (produced by the `/identify-cit`, `/identify-pit`, `/identify-vat` skills, duplicated by design) run directly over the deployment evidence the C1/C0 pipeline surfaced. The method mirrors `/manual-analysis`: keyword scan of the full C1 pool → semantic sweep → **recall recovery by reading `country_body` source documents directly** → consolidation at the announced-act grain → mandatory recall scorecard → human stamp. C0 is **not** used as the event layer (it fragments tight instrument tracks and never bridges EN/BM).

**Key tests and decisions:**

- Each notebook renders its recall scorecard and structured table from the single source of truth — the frozen `data/validated/{ISO}_{INSTRUMENT}_shocks.qs` — once the skill has stamped it (shared column contract in `docs/phase_1/tax_shock_schema.md`, one row per announced act × tax type).
- **Malaysia frozen (2026-06):** CIT 9 events (headline path 34%→24% + single-tier reform + 2022 Cukai Makmur; 2 recall misses recovered), PIT 9 events, CONSUMPTION 4 events (service tax 5%→6% 2011; GST introduction at 6% 2015; GST abolition 2018; SST reinstatement 2018).
- Preliminary exogeneity is a **suggestion with its supporting quote, pending expert adjudication** — carried alongside, never replacing, C2b's downstream label.
- **Decision:** Hand-curated reference inputs (analogous to `data/raw/us_shocks.csv`), the data-policy carve-out for the non-pure agentic pass; read back into the pipeline via the `tax_shock_files` target. Human-stamped, not auto-generated.

### `tax_shocks.qmd` -- Statutory Tax-Shock Deliverable

**Purpose:** The cross-instrument statutory tax-change deliverable. Binds the frozen per-instrument datasets (`bind_tax_shocks()` over `tax_shock_files`), re-runs C2a **only on the corpus chunks C1 omitted** (reusing existing `country_c2a_evidence` for the rest), runs the frozen C2b v0.9.1 classifier, and assembles the final table keeping **both** the preliminary narrative exogeneity read and C2b's `pred_exogenous`/`pred_sign`/reasoning. Pipeline tail in `R/tax_shock_dataset.R`.

**Key tests and decisions:**

- **Decision:** The C2a re-run and C2b classification are **API-gated** and run via the `/identify-tax-shocks` orchestrator with explicit user approval; the binding/assembly targets are empty-input safe (inert until the first frozen file exists). Candidate Phase 2 expert-validation artifact (open question logged in `docs/deltas.md` 2026-06-25).

### `spending_identification.qmd` -- Government Spending-Shock Identification

**Purpose:** Provenance notebook for the spending-side component of the composite fiscal-events deliverable — the analogue of the per-instrument tax notebooks, for *discretionary government spending changes* (major programs & policy changes: stimulus/relief packages, subsidy-policy changes, large allocations, Five-Year Plan launches). Produced by the `/identify-spending` skill. Unlike the tax notebooks, **C1 does not pre-screen spending** (C1 is tax-scoped), so the method is **direct reading of `country_body` / `country_chunks`** rather than a C1-pool scan; the near-empty C1 floor is itself logged in the recall scorecard. Preliminary exogeneity uses the **Das et al. (2026) two-condition screen**.

**Key tests and decisions:**

- Renders its recall scorecard and structured table from the single source of truth — the frozen `data/validated/{ISO}_SPENDING_shocks.qs` — once the skill has stamped it (**parallel** contract `docs/phase_1/spending_shock_schema.md`: identical to the tax contract except `instrument_type = "Expenditure"`, `tax_type = NA`, rate fields `NA`, `direction ∈ {Increase, Decrease, Neutral}`, plus a `spending_category` enum from the Das component families). Empty-safe: renders a "pending" callout before the first freeze.
- Malaysia recall checkpoints: NERP 1998 / 2009 GFC stimulus / 2020 PRIHATIN-PENJANA-PEMERKASA.
- **Malaysia frozen (2026-06-29):** 14 events. Crisis stimulus per-package (reviewer grain decision): NERP 1998; 2001 pre-emptive RM3bn + additional RM4.3bn; First (RM7bn) + Second (RM60bn, mini-budget) GFC ESPs; COVID PRIHATIN/PENJANA/PERMAI/PEMERKASA/PEMERKASA+/PEMULIH (RM530bn+, 8 packages, KITA PRIHATIN/SME+ folded into PRIHATIN). Structural: subsidy rationalisation 2010– (exogenous), 2008 fuel-subsidy restructuring kept separate (endogenous, oil-price-driven), 1Malaysia/Keluarga cash-transfer programme BR1M→BKM 2012– (ambiguous). RMK Five-Year Plans **excluded** as baseline development-expenditure framework. Preliminary Das split: 12 endogenous / 1 exogenous / 1 ambiguous. **C1 floor was NOT near-empty (189 spending-regex hits)** — BNM/ER/Budget docs discuss stimulus + subsidy alongside tax, so `recovered_chunks` is ~empty for every act (recorded in the scorecard as a deviation from the skill's expectation).
- **Decision:** Hand-curated reference input (same data-policy carve-out as the tax datasets); read back via the `spending_shock_files` target. The spending pipeline (`spending_shock_files` → `spending_shocks_identified` → `spending_shocks_evidence` → `spending_shocks_c2b` → `spending_shocks` in `_targets.R`) reuses `assemble_shock_evidence()` / `run_c2b_on_shocks()` / `assemble_tax_shock_deliverable()` unchanged; only `bind_spending_shocks()` (`R/spending_shock_dataset.R`) is new. The frozen **tax-validated C2b** assigns the final motivation/sign label (deferred a Das-style spending codebook). A dedicated cross-instrument `spending_shocks.qmd` deliverable notebook is deferred until the first enrichment run.

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
10. `deployment.qmd` -- See the cross-country deployment headline (C1 → C0 → C2 act inventory per country)
11. `cit_identification.qmd` / `pit_identification.qmd` / `vat_identification.qmd` → `tax_shocks.qmd` -- See the statutory tax-shock identification layer (per-instrument frozen datasets → bound deliverable with C2a/C2b enrichment)

## Conventions

- New notebooks use `tinytable` (`tt()`) for tables (never `gt` or `kableExtra`). Existing notebooks may still use `gt` and will migrate when next edited.
- New notebooks load packages with `pacman::p_load()` instead of repeated `library()` calls.
- All notebooks load data via `tar_read()` from the `{targets}` pipeline
- Notebooks set `tar_config_set(store = here("_targets"))` in their setup chunk
- Existing notebooks source `R/gt_theme.R`; new notebooks should source `R/tt_theme.R` instead for consistent table styling
- Tests use PASS/WARN/FAIL status with color-coded tables (`gt` in existing notebooks, `tinytable` in new ones)
- Interpretive commentary follows each test section explaining findings and decisions
