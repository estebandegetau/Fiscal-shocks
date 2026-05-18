# C2 Deployment Design Decisions

Decisions made during the C1→C2 transition, documenting how the pipeline architecture adapts from binary chunk-level classification (C1) to 4-class act-level motivation classification (C2).

---

## Decision 1: Classification Unit — Act-Level, Not Chunk-Level

**Context.** C1 classifies at the chunk level: each ~10-page window receives a binary label (FISCAL_MEASURE / NOT_FISCAL_MEASURE). C2 must assign one of four motivation categories per fiscal act, matching the ground truth structure in `aligned_data` (one `motivation_category` per act).

**Decision.** C2 classifies at the **act level**. Each classification call receives all relevant text for a single act and returns one motivation label.

**Rationale.** R&R's methodology (RR5) determines motivation by weighing evidence across all sources discussing an act — "use the most frequently cited motivation across all sources." This is inherently an act-level judgment. Chunk-level classification would require an aggregation step (majority vote, confidence weighting) that introduces unnecessary complexity and obscures error sources.

---

## Decision 2: Input Assembly — Curated Multi-Chunk Context (Option C)

**Context.** Three options were considered for assembling C2's LLM input:

- **Option A:** Concatenate all chunks for an act into one blob.
- **Option B:** Classify each chunk independently, aggregate decisions downstream.
- **Option C:** Curate a structured input per act from its constituent chunks.

**Decision.** Option C — **structured, curated input per act.**

For each act, gather all chunks C1 tagged to it and present them as a structured prompt:

> *"The following passages discuss [Act Name]. Based on these passages, classify the primary motivation..."*

**Rationale.**

- Mirrors R&R methodology (weigh all evidence for an act together).
- Avoids Option B's aggregation problem (many chunks lack motivation-relevant language; aggregating arbitrary chunk-level labels is noisy).
- Improves on Option A by framing what the model is classifying (the act) and from what evidence (the passages), rather than dumping undifferentiated text.
- Context length is not a concern: most acts appear in a handful of chunks, well within Haiku's 200K context. For rare outliers, cap at the N most relevant chunks.

**Superseded (2026-04-07).** Empirical analysis of `c2_act_data` (39 acts, tier2 capped at 20/act) showed median 157K tokens, max 366K, with 6 acts exceeding 190K tokens. Context length *is* a concern. See strategy.md C2 Blueprint for the two-stage architecture (evidence extraction per chunk, then act-level classification) that resolves this.

---

## Decision 3: Phase 0 Ground Truth — Simulate C1 Production Output

**Context.** In production, C2 receives C1's output: `(chunk_text, act_name)` pairs for chunks classified as containing fiscal measures. In Phase 0 development, we need a ground truth dataset for evaluating C2 in isolation, without compounding C1 errors.

**Decision.** Build `c2_act_data` from existing pipeline artifacts:

1. **Source:** `c1_chunk_data$tier1` (70 chunks) + `c1_chunk_data$tier2` (1,986 chunks) — these are chunks already mapped to specific acts via gold-standard passage matching and name matching.
2. **Join:** Attach `motivation_category` and `exogenous_flag` from `aligned_data` on `act_name`.
3. **Group by act:** Concatenate chunk texts per act, producing one row per act with assembled evidence text.
4. **Ground truth label:** `motivation_category` from `aligned_data` (one of: `SPENDING_DRIVEN`, `COUNTERCYCLICAL`, `DEFICIT_DRIVEN`, `LONG_RUN`).

This yields **39 act-level observations** (matching `aligned_data`), each with all relevant passages assembled as they would be in production after C1 runs.

**Rationale.**

- Mimics production data flow (C1 identifies relevant chunks → C2 classifies motivation) without depending on C1's actual predictions.
- Uses gold-standard chunk-to-act mappings, isolating C2 codebook quality from C1 error propagation.
- Reuses existing `c1_chunk_data` and `aligned_data` — no new data collection needed.
- The 39-act sample matches strategy.md's S2 evaluation plan: "Ground truth: `aligned_data` motivation labels (44 acts)." (39 after alignment filtering.)

**Partially superseded (2026-04-07).** The flat `tier1 + tier2` source and count-cap approach is replaced by C1-filtered chunks (`FISCAL_MEASURE` with `discusses_motivation = TRUE`), which are expert-vetted through C1 S3 manual analysis. The assembly logic, label distribution, and evaluation isolation principle remain valid.

**Label distribution** (from `aligned_data`):

| Motivation | Count | Exogenous? |
|-----------|-------|------------|
| Long-run | 15 | Yes |
| Spending-driven | 10 | No |
| Deficit-driven | 8 | Yes |
| Countercyclical | 6 | No |

**Note on evaluation isolation:** Phase 0 evaluates each codebook independently using gold-standard inputs. C1 errors do not propagate into C2 evaluation. End-to-end error propagation is tested in Phase 1 when validated codebooks run sequentially on the full `us_body` corpus.

---

## Decision 4: No Tier System for C2

**Context.** C1 uses a two-tier system: Tier 1 (verbatim R&R passage matches, high confidence) and Tier 2 (act name substring matches, noisier). This distinction was necessary because C1's ground truth is at the chunk level, and chunk-to-act mapping quality varies.

**Decision.** C2 does not use tiers. All chunks for an act are assembled into a single input regardless of how they were matched.

**Rationale.** C2's ground truth is at the act level (one label per act), not the chunk level. The tier distinction served C1's need to stratify evaluation by label confidence — C2 doesn't have this problem because its labels come directly from `aligned_data`, not from a fuzzy matching heuristic.

---

## Implications for Code

### Reusable as-is
- `codebook_stage_0.R` — All functions (load, validate, prompt construction, classification)
- `behavioral_tests.R` — All 7 H&K tests (label-agnostic)
- `functions_llm.R` — API calls, JSON parsing, self-consistency
- `prepare_training_data.R` — Act-level alignment

### Minor adaptation
- `codebook_stage_1.R` — Replace `c1_chunk_data` parameter with generic chunk data input
- `codebook_stage_3.R` — Remove hardcoded `"FISCAL_MEASURE"` / `"NOT_FISCAL_MEASURE"`; pull from `get_valid_labels()`

### New functions needed
- **`prepare_c2_act_data()`** — Assemble act-level inputs from `c1_chunk_data` + `aligned_data`
- **`generate_c2_examples()`** — Few-shot examples stratified across 4 motivation classes
- **`compute_multiclass_metrics()`** — Per-class P/R/F1, weighted F1, 4×4 confusion matrix, 2×2 exogenous matrix, bootstrap CIs

### Not reusable (C1-specific)
- `identify_chunk_tiers.R` — Tier system doesn't apply to C2
- `generate_c1_examples.R` — C1-specific data structures

---

## Decision 5: Replace Within-Doc JW Clustering with LLM Dedup (2026-05-17)

**Context.** Across the C2a → cluster path, `cluster_measure_names_within_doc()` groups raw `measure_name` strings by Jaro-Winkler distance ≤ 0.15, producing the per-act evidence bundles that feed C2b. The Malaysia EN/BM consistency test (`notebooks/malay_consistency.qmd`) revealed that JW at 0.15 fails to merge semantically-identical measures across four distinct failure modes within a *single* document:

- **Verbose-vs-bare phrasing.** Same measure named with and without contextual suffixes. Example (2016 EN): `Goods and Services Tax (GST)` vs `Goods and Services Tax (GST) implementation in April 2015` vs `Goods and Services Tax (GST) and subsidy rationalization measures` — three separate clusters, all pairwise JW 0.17-0.19.
- **Within-doc cross-language naming.** Same measure named in different languages within the same document. Example (2015 BM): the BM Economic Report has 9 chunks discussing GST; cluster 1 contains 4 chunks named `Goods and Services Tax (GST) / Cukai Barangan dan Perkhidmatan` (MIXED), cluster 2 contains 5 chunks named `Goods and Services Tax (GST) implementation in April 2015` (EN-only). Roughly half of BM-document extractions emerge in English regardless of source language, so this is structural rather than incidental.
- **Word-order paraphrase.** Same act named with words reordered. Example (2014 BM): clusters 13/14 are `Islamic Financial Services Act 2013 (IFSA) and Financial Services Act 2013 (FSA)` vs `Financial Services Act 2013 (FSA) and Islamic Financial Services Act 2013 (IFSA)`.
- **Mega-bundles (inverse problem).** C2a sometimes returns one `measure_name` describing 4-8 distinct measures (e.g. 2020 EN cluster 14: RPGT + NAHP + RTO + YHS + HOC + travel relief + tourism exemption). This is *under*-clustering at the LLM-extraction stage and cannot be fixed by any post-hoc clustering algorithm.

Threshold sensitivity table in the consistency notebook quantified the JW failure: 2015 and 2016 drift fully collapses at JW ≤ 0.20 (entirely artifact); 2014 and 2019 partial. Bumping the JW threshold is not a real fix — paraphrase variants (Foreign Workers Levy JW=0.36) require thresholds so loose that genuinely distinct measures begin to over-merge.

**Decision.** Replace the JW-based `cluster_measure_names_within_doc()` with an **LLM-based within-document dedup step** (Sonnet) that takes one document's `(chunk_id, measure_name, c2a_valid)` rows and returns cluster assignments. Insert this step between `c2a_evidence` and the clusters target.

**Rationale.**

- The four failure modes (verbose suffixes, within-doc cross-language naming, word-order paraphrase, mega-bundle splitting) are all natural-language reasoning problems that string-distance metrics cannot solve.
- Sonnet is already in the pipeline for cross-doc EN↔BM matching (Level 2 of the consistency test). Reusing the same matcher for within-doc dedup keeps the architectural surface small.
- Cost is modest: ~16 doc-level API calls for the Malay ER consistency test, ~99 for the full Malaysia deployment corpus. The within-doc input size is small (a list of 5-20 measure names per document) so per-call cost is low.
- Cost-conscious variant: keep JW as an auto-merge pre-filter for the < 0.10 band, send only the ambiguous 0.10-0.40 middle band to the LLM. Pure-LLM is defensible at this corpus scale.
- For the mega-bundle problem (E above), the LLM dedup step can also be asked to **split** a single measure name describing N distinct measures into N separate cluster members, which JW cannot do. This requires explicit prompt design and is a secondary objective.

**Sequencing.**

- The consistency test's Level 2 and Level 3 results are downstream of the cluster target. After this change is implemented, `malay_er_clusters` must be regenerated and the consistency notebook re-rendered before any Phase 2 expert validation runs. Corrupted (fragmented) C2b inputs would invalidate any expert-agreement metric.

---

## Decision 6: Country-of-Enactment Tagging to Filter Foreign Comparators (2026-05-17)

**Context.** C1's S0 definition asks "does this passage describe an enacted fiscal measure" without specifying *which country's* fiscal measure. This was unproblematic for the US-only Phase 0 corpus because the Economic Report of the President rarely describes a *Mexican* (etc.) fiscal measure as if it were US policy. It becomes a deployment problem for Malaysia (and future SEA countries) because Economic Reports systematically discuss Japan, India, China, Australia, Egypt, Philippines, and Korea fiscal measures as comparators. C1 (correctly per its current definition) labels these passages FISCAL_MEASURE.

The Malaysia EN/BM consistency test surfaced this clearly:

- **2020 EN:** 15 clusters vs BM's 4. At least 3 EN clusters are foreign comparators — `Japan's Sales Tax Hike (8% to 10%)`, `India's income support scheme to farmers`, `Australia's Four Stimulus Packages` — bloating the EN-side count and creating apparent cross-language drift that is actually content-asymmetry of comparator coverage between the EN and BM editions.
- **2017 BM:** Analogous BM-side contamination — `Japan's Consumption Tax Rate Increase Postponement` is a Japanese fiscal measure, and `Malaysia Sukuk Global Wakalah (April 2016 issuance)` is sovereign debt issuance rather than a fiscal-policy *measure* in the R&R sense.
- **Other years:** Similar patterns across 2014 EN (Japan + Mexico + India + Brazil + Russia in one mega-cluster), 2015 EN (Egypt), 2019 EN (US, Japan, Philippines), 2019 BM (Philippines, Japan, Australia, Korea), 2020 BM (Japan, China).

R&R did not address this problem because their methodology was designed for US-only analysis and the US economy is large enough that domestic fiscal policy dominates the source documents. The methodology must be extended for cross-country deployment.

**Decision.** Add country-of-enactment tagging to C1 output. **Preferred architecture: standalone C1F filter codebook** running between C1 and C2a, producing a `country_iso` field per surviving fiscal-measure chunk. Filter `country_iso != target_country` before evidence assembly. Final architectural choice (standalone C1F vs C1 extension) deferred to implementation review.

**Schema.** `country_iso` is an enum constrained to the deployment country list (`MY`, `US`, future SEA codes) plus `OTHER` as a required fallback for unanticipated comparators.

**Rationale (standalone C1F preferred).**

- **Avoids reopening C1's frozen S3 gate.** C1 v0.6.0 crossed S3 with the current schema. Extending C1 with a `country_iso` extra_output_field is structurally analogous to v0.6.0's `discusses_motivation/timing/magnitude` additions and could be defended with a narrow re-verification (Tests V/VI/VII subset showing the binary FISCAL_MEASURE decision is unchanged) — but this is still a re-gating exercise. A standalone C1F is cleaner.
- **Isolates the new failure mode.** Country misidentification is a different kind of error than measure misidentification. Keeping them in separate codebooks makes per-failure-mode error analysis tractable and allows C1F to iterate independently of C1.
- **Required for Phase 2 expert validation.** Without country filtering, expert agreement metrics will be biased downward because the model is "right" about a Japanese measure that the Malaysian expert reviewer will mark out-of-scope. This is a methodologically invalid form of disagreement.
- **`OTHER` fallback is non-negotiable.** Malaysian Economic Reports cite at least 8 comparator countries in the 2014-2022 sample alone. An exhaustive enum would be brittle as new SEA countries come online; `OTHER` absorbs the unexpected.

**Sequencing.**

- Tackle in the same deployment-pipeline work cycle as Decision 5. Both are upstream of any expert-validation work and both invalidate Level 2/3 outputs of the consistency test, so deferring either creates rework.
