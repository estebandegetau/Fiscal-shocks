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
