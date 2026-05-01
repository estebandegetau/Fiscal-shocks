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
| **Phase 0** | Codebook Development | Develop and validate codebooks C1-C4 on a subset of `us_body` chunks using H&K S0-S3 on 44 US labeled acts (43 after excluding the Internal Revenue Code of 1954, whose name is identical to the title of the ongoing US tax code, creating pervasive false Tier 2 matches across the corpus; this act is accounted for separately in Phase 1 end-to-end validation) | Validated codebooks meeting success criteria |
| **Phase 1** | US Full Production | Run validated codebooks on the full `us_body` corpus; compare end-to-end results against `us_shocks.csv` | Reproduced US shock series |
| **Phase 2** | Malaysia Pilot | Deploy codebooks to Malaysia documents (1980-2022) with expert validation | Expert-validated Malaysia fiscal shock dataset |
| **Phase 3** | Regional Scaling | Extend to Indonesia, Thailand, Philippines, Vietnam | Multi-country fiscal shock panel |

**Phase 0 vs. Phase 1 distinction:** Phase 0 validates codebook accuracy using zero-shot evaluation on a cost-efficient subset of chunks (relevant + irrelevant text around the 44 labeled acts). Phase 1 tests whether the validated codebooks can recover `us_shocks.csv` when run on the full document corpus, which is far more expensive but validates production readiness.

---

## The Complete R&R Pipeline

The Romer & Romer methodology consists of 6 steps (RR1-RR6). Steps RR2-RR5 are implemented as LLM codebooks; RR1 and RR6 are data engineering tasks.

| R&R Step | Task | Implementation | Output |
|----------|------|----------------|--------|
| **RR1: Source Compilation** | Gather fiscal policy documents | Data engineering | Document corpus |
| **RR2: Measure ID** | Identify fiscal measures meeting "significant mention" rule | Codebook C1 (LLM) | Binary + extraction |
| **RR3: Quantification** | Extract fiscal impact in billions USD | Codebook C4 (LLM) | Magnitude per quarter |
| **RR4: Timing** | Extract implementation quarter(s) using midpoint rule | Codebook C3 (LLM) | List of quarters |
| **RR5: Motivation** | Classify motivation and filter exogenous shocks | Codebook C2 (LLM) | Exogenous flag + sign |
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
| **C2: Motivation** | RR5 | Classify whether the act's stated motivation is exogenous and the directional effect on fiscal liabilities | Exogenous flag + sign |
| **C3: Timing** | RR4 | Extract implementation quarter(s) using midpoint rule | List of quarters |
| **C4: Magnitude** | RR3 | Extract fiscal impact in billions USD | Magnitude per quarter + PV |

### H&K Stages (Applied to Each Codebook)

| Stage | Purpose | Key Activities |
|-------|---------|----------------|
| **S0: Codebook Prep** | Machine-readable definitions | Label, definition, clarifications, +/- examples, output instructions |
| **S1: Behavioral Tests** | Model sanity checks | Legal output (100%), memorization (100%), order sensitivity (<5%) |
| **S2: Zero-Shot Eval** | Performance measurement | Evaluation on 43 US acts, compute primary metrics |
| **S3: Error Analysis** | Failure mode identification | Ablation studies (4 conditions), behavioral Tests V-VII, manual error review |
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

**Note on C1→C2 handoff.** C2 receives C1-filtered chunks (`FISCAL_MEASURE` with `discusses_motivation = TRUE`) via C1 v0.6.0's extra_output_fields, not raw heuristic tier labels. This two-stage architecture (evidence extraction per chunk, then act-level classification) compresses signal and fits any context window. See C2 Blueprint for details.

**Note on enacted-status filtering.** C1 is a recall-optimized relevance filter that captures proposals alongside enacted measures (see C1 Blueprint). A post-C1 enacted-status filter — operating at the act level, not the chunk level — is required before C2-C4 in production. This filter aggregates C1's chunk-level output by act, then determines enacted status from the combined evidence. In Phase 0, this pathway is untestable (ground truth contains only enacted acts). Phase 1 validates the filter against `us_shocks.csv`; Phase 2 relies on expert review.

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
| C1: Measure ID | Tier 1 Recall | ≥95% | Diagnostic benchmark (label noise limits hard gating) |
| C1: Measure ID | Combined Recall (Tier 1+2) | ≥90% | Diagnostic benchmark (Tier 2 labels are noisy) |
| C1: Measure ID | Precision | ≥70% | Diagnostic benchmark (FPs include unlabeled real acts) |
| C2: Motivation | Exogenous Precision | ≥85% | Critical for shock series (binary) |
| C2: Motivation | Sign Accuracy on True-Exogenous | ≥90% | Sign correctness on the deliverable population |
| C3: Timing | Exact Quarter | ≥85% | R&R accuracy |
| C3: Timing | ±1 Quarter | ≥95% | Acceptable tolerance |
| C4: Magnitude | MAPE | <30% | R&R accuracy |
| C4: Magnitude | Sign Accuracy | ≥95% | Critical (tax increase vs cut) |

**Note on C1 metrics.** C1 metrics are diagnostic benchmarks, not hard gates. The ground truth label set (44 acts identified in chunks via name matching) is noisy: Tier 2 matching misses acronyms and compound names, and FPs include real fiscal measures absent from the 44-act set (H&K Error Category F). S3 manual error audit is the actual stage gate for C1.

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

1. **Review S3 error analysis.** Identify the dominant error pattern using H&K taxonomy (A-F) via manual review of misclassified cases. Automated categorization is not used — H&K intended this as expert judgment, not heuristic binning.
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
| 2 | ✅ C1 (Measure ID): S0-S3 complete. May require adjustments based on C2-C4 development | `notebooks/c1_measure_id.qmd` |
| 3 | Implement C2 (Motivation) through H&K S0-S3 | `notebooks/c2_motivation.qmd` |
| 4 | Implement C3 (Timing) through H&K S0-S3 | `notebooks/c3_timing.qmd` |
| 5 | Implement C4 (Magnitude) through H&K S0-S3 | `notebooks/c4_magnitude.qmd` |
| 6 | Implement RR6 aggregation, validate against `us_shocks.csv` | `notebooks/rr6_aggregation.qmd` |
| 7 | End-to-end pipeline integration and testing | `notebooks/pipeline_integration.qmd` |

### C1: Measure Identification Blueprint

**Design Rationale.** C1 is the top of the C1-C4 pipeline funnel. It must maximize recall so downstream codebooks (C2-C4) have access to timing, magnitude, and motivation details. False positives at C1 are filtered by C2-C4; false negatives are permanently lost. Evaluation uses full document chunks (~40K tokens) matching production conditions, not isolated passages.

**Chunk Tier System.** Evaluation uses three tiers of ground truth:

| Tier | Definition | Ground Truth | Role |
|------|-----------|-------------|------|
| 1 | Chunk contains verbatim `us_labels` passage text | FISCAL_MEASURE (high confidence) | Primary positive |
| 2 | Chunk mentions known act name (not Tier 1) | FISCAL_MEASURE (pipeline rationale) | Secondary positive |
| Negative | No Tier 1/2 match, no relevance key match | NOT_FISCAL_MEASURE | Clean negative |

Chunks with relevance keys but no Tier 1/2 match are excluded from evaluation (ambiguous gray zone).

**Corpus scope.** The evaluation corpus is restricted to documents published through **2007** (`max_doc_year = 2007`). R&R's last identified act was signed in 2003, and documents through approximately 2007 represent the universe they had access to when writing their 2010 paper. Post-2007 documents only contribute retrospective mentions that would inflate Tier 2 recall beyond what the actual identification task requires. The full 1946-2022 corpus can be restored (`max_doc_year = NULL`) for sensitivity analysis.

**Chunk parameters.** 10-page sliding window with 3-page overlap. Chunks shorter than 100 characters are filtered as extraction artifacts (`min_chars = 100`).

**S0 Codebook Design.** Operationalize the "significant mention" rule from `docs/literature_review.md` Section 1.2. Scope: enacted changes in tax liabilities only, not spending changes (per R&R). Two classes: `FISCAL_MEASURE`, `NOT_FISCAL_MEASURE`. Inclusion criteria: legislated liability changes, executive actions affecting tax liabilities (depreciation orders, ministerial decrees, regulatory changes, official policy directives), any action receiving more than incidental reference in primary sources, retrospective references with substantive detail about provisions. Exclusion criteria: extensions of existing provisions without rate changes, withholding-only adjustments, automatic renewals, summary lists or tables enumerating measures without substantive discussion. Country-agnostic language in definitions and clarifications enables transfer learning; US-specific terms appear only in examples. Note: enacted-status filtering and retrospective exclusion are handled by C2 (motivation classification), not C1. C1 is a recall-optimized relevance filter that captures enacted, proposed, and under-consideration measures.

**S1 Behavioral Tests (complete).** Test I: valid JSON on chunk-length inputs (~20 chunks: 10 Tier 1+2, 10 negative). Test II: feed codebook definitions back as input, verify correct label recovery. Test III: feed positive/negative examples, verify correct label. Test IV: original, reversed, and shuffled class orderings on chunk-length inputs (binary codebooks have a degenerate shuffled = reversed case). Pass criteria: 100% legal outputs, 100% memorization, <5% order sensitivity.

**S2 Zero-Shot Eval.** Ground truth: `aligned_data` (43 acts, see note below) with chunk-level evaluation via `c1_chunk_data`. Single-pass zero-shot classification of all evaluation chunks (no LOOCV, no few-shot examples). LOOCV is reserved for few-shot ablation in S3. Pipeline targets: `c1_s2_test_set` (chunk sampling) → `c1_s2_results` (API classification) → `c1_s2_eval` (metrics). Primary metrics (diagnostic benchmarks, not hard gates): Tier 1 Recall ≥95%, Combined Recall (Tier 1+2) ≥90%, Precision ≥70%. All metrics are conservative bounds due to label noise; S3 manual audit is the actual stage gate. Bootstrap 1000 resamples for 95% CIs. Per-act recall reported for error analysis.

**S3 Error Analysis Plan.** Primary risk: context dilution (measure buried in 40K tokens of surrounding text) and false positive inflation (chunks with fiscal vocabulary but no specific act). Test V: H&K 4-combo design — (normal/modified document) × (normal/modified codebook). Injects a distractor paragraph and corresponding exclusion rule, verifies the model only applies the exclusion when both trigger and rule are present. Ablation uses 4 conditions: full, no_label_def, no_examples, no_examples_no_clarifications. Output instructions are non-ablatable infrastructure (ablating them breaks JSON parsing, testing format compliance rather than task understanding; H&K's 5th condition assumes plain-text label output). Error review follows H&K taxonomy (A-F) via manual inspection.

**Migration from Legacy Code.** Reuse `R/functions_llm.R` (`call_claude_api()`), `R/functions_self_consistency.R` (self-consistency sampling), `R/prepare_training_data.R` (`align_labels_shocks()`), `R/make_chunks.R` (`make_chunks()`). New: `R/identify_chunk_tiers.R` for tier identification.

**Iteration Strategy.** If combined recall <90%: examine FN chunks for context dilution patterns; consider shorter chunk windows or multi-pass detection. If Tier 1 recall <95%: check substring matching in tier identification. If precision <70%: strengthen negative clarifications for fiscal-vocabulary-without-act patterns; add chunk-level negative examples to few-shot.

### C2: Motivation Classification Blueprint

**Design Rationale (v0.7.0).** C2 outputs a signed exogenous flag matching the proxy convention of Das et al. (2026, IMF WP/26/43): for each act, it returns `{enacted, exogenous, sign}` plus a confidence and short reasoning. The 4-class R&R motivation taxonomy (`SPENDING_DRIVEN`, `COUNTERCYCLICAL`, `DEFICIT_DRIVEN`, `LONG_RUN`) is preserved as a diagnostic concept used in error analysis and aligned-data ground truth, but is not a codebook output. This collapse is motivated by three converging signals: (a) iter 35's structural-ceiling diagnosis (wF1 ≈ 0.66 under any v0.5–v0.6.x rule density on Haiku); (b) iter 36's evidence-shuffle leakage diagnostic showing F-cluster acts are order-fragile under v0.6.1's dense decision rules (F–A median-stability gap = −0.333); (c) Das et al.'s demonstration that an off-the-shelf, fixed, ~250-word prompt achieves 87.5–95% direction agreement and 94–97% motivation-category agreement against expert RR19 coding. The deliverable framing — "the signed exogenous shock series feeds RR6 and downstream multipliers" — matches Das et al.'s empirical target.

**Two-stage architecture (unchanged).** C2 keeps the C2a (per-chunk evidence extraction) → C2b (act-level classification) split. C2a remains at v0.4.0; only C2b is rewritten under v0.7.0. The two-stage pattern compresses signal, eliminates dilution from irrelevant text, and fits any context window. C2b receives an act_name, year, evidence array (from C2a), and enacted-status signals; it returns the v0.7.0 schema below. Cached `c2a_evidence` means v0.7.0 testing only re-runs C2b (~$0.50 per S2 run on Haiku).

**Output schema.** `{enacted: bool, exogenous: "TRUE"|"FALSE"|"UNCLEAR", sign: "+"|"-"|"0"|"UNCLEAR", confidence: HIGH|MEDIUM|LOW, reasoning: str}`. Sign refers to the change in fiscal liabilities (positive = tax increase, negative = tax cut, zero = no net effect, UNCLEAR = direction not determinable from evidence). Multi-component acts that mix exogenous and endogenous motives in roughly comparable shares return `exogenous: UNCLEAR` rather than an inferred dominant — the conservative-aggregation rule replaces v0.6.1's DR3 + tiebreaker hierarchy.

**Input Architecture (unchanged).** C2 receives C1-filtered chunks as input: chunks classified as `FISCAL_MEASURE` with `discusses_motivation = TRUE` by C1 v0.6.0. Rationale: C1's output is a better proxy for "chunks containing motivation-relevant fiscal discussion" than heuristic tier labels, and has been expert-vetted through C1 S3 manual analysis (31A/6B/0E/3F — zero semantic errors). The `discusses_motivation` flag provides targeted compression (635 → 531 chunks, 83.6%).

**Error Decomposition (unchanged).** Using C1's `discusses_motivation` flags as the input filter enables decomposable error attribution: when C2 misclassifies, we can distinguish C1 filtering errors (motivation evidence existed but C1 flagged `discusses_motivation = FALSE`) from C2 classification errors. The S2 sensitivity condition (relax `discusses_motivation`) tests this.

**S0 Codebook Design (v0.7.0).** Minimal Das-et-al.-style prompt. Single instructions block with: definition of exogenous (long-run, structural reform, inherited deficit, treaty/rule compliance), definition of endogenous (response to current macro conditions or contemporaneous spending), one critical clarifier verbatim from Das et al. ("Acknowledging current conditions does not by itself imply endogeneity if the stated motive is explicitly non-cyclical"), conservative aggregation rule for mixed components, sign convention, and enacted-status determination. Four short illustrative examples covering the four corners of the {exogenous, sign} schema. No per-class definitions, no DR1–DR4, no BCR1–BCR4, no share/dominant tiebreaker, no US-specific worked examples. Country-agnostic by construction.

**S1 Behavioral Tests.** Test I (legal outputs): full schema validation against `{enacted, exogenous, sign, confidence, reasoning}`. Test II (schema recovery, replacing definition recovery): four synthetic evidence sets each with known expected `(exogenous, sign)`; C2b must recover both. Test III (example recovery): skipped (no per-class examples to recover under v0.7.0). Test IV (order invariance): skipped — degenerate without a `classes` block; legal-output stability is covered by Test I and the iter 36-style evidence-shuffle diagnostic.

**S2 Zero-Shot Eval.** Ground truth: `aligned_data` (39 acts after alignment filtering). Two evaluation conditions retained: (a) **Primary** — C1-filtered inputs through the two-stage pipeline. (b) **Sensitivity** — relax the `discusses_motivation` requirement to test whether C2 finds evidence C1 missed. Two co-equal headline metrics, each with bootstrap 95% CIs:

- **Exogenous Precision** ≥ 85% (binary, TRUE-class precision; UNCLEAR predictions are abstentions, excluded from precision denominators)
- **Sign Accuracy on True-Exogenous** ≥ 90% (denominator is the true-exogenous subset, since sign of endogenous acts does not enter the shock series; UNCLEAR pred_sign counts as incorrect)

A joint diagnostic (`signed_exo_precision`: P(pred_exo == TRUE AND correct sign | true exogenous)) is also reported for transparency. Confusion matrices: 2×2 exogenous, 4×5 sign-on-true-exo (rows: pred_sign in {+, −, 0, UNCLEAR, NA}, columns: true_sign in {+, −, 0, UNCLEAR}).

**S3 Error Analysis Plan (v0.7.0).** Tests V–VII (exclusion criteria, generic labels, swapped labels) are degenerate without a `classes` block and are guarded to skip cleanly when the codebook has no classes. Stability analysis is delegated to the **evidence-shuffle diagnostic** (`c2b_evidence_shuffle_diagnostic` target): per-act fingerprint stability under k=3 deterministic permutations of the C2a evidence array. The fingerprint auto-detects codebook generation: v0.7.0+ → `{exogenous}|{sign}`; legacy 4-class → `{sorted-categories}|{exogenous}`. F–A median-stability gap remains the overfit signal; the v0.7.0 minimalism predicts the gap should narrow toward zero. Manual error review on misclassified acts (the iter-30-style audit) is retained as the qualitative complement to the binary metrics.

**Iteration Strategy.** If exogenous_precision < 0.81 (v0.6.1 baseline floor): investigate per-act regressions in `per_act_results`; consider folding back one specific clarifier at a time, preserving the minimalism principle. If sign_accuracy < 0.85: add a `direction_signals` array to C2a v0.5.0 (currently c2a only extracts motivation evidence + enacted_signals; sign extraction would be the obvious gap). If sensitivity outperforms primary: relax C1's `discusses_motivation` filter rather than re-tune C2b.

### C3: Timing Extraction Blueprint

**S0 Codebook Design.** Structured extraction (not classification). Operationalize the midpoint rule from `docs/literature_review.md` Section 1.5: if legislation specifies a range, use the quarter containing the midpoint. Phased changes are recorded as separate entries with distinct quarters. Retroactive components appear in both the standard series (implementation quarter) and the adjusted series (quarter the legislation was signed). Output format: list of `{quarter, amount_at_annual_rate}` tuples. Include Excess Profits Tax 1950 as a worked example of phased timing.

**S1 Behavioral Tests.** Test I checks valid structured output format (list of quarter-amount tuples, quarters as YYYY-QN). Tests II-IV follow standard pattern. Pass criteria: 100% legal outputs, 100% memorization, <5% order sensitivity.

**S2 Zero-Shot Eval.** Compare extracted quarters to `us_shocks.csv` ground truth quarter assignments. Primary metrics: Exact quarter match ≥85%, ±1 quarter match ≥95%. Bootstrap 1000 resamples for 95% CIs.

**S3 Error Analysis Plan.** Ablation on midpoint rule clarification vs. phased change examples to determine which component drives accuracy. Error categories: wrong quarter (off by 1+), missed phase (fewer entries than ground truth), spurious phase (more entries than ground truth), incorrect retroactive handling, date parsing error.

**Migration from Legacy Code.** Split timing extraction from `R/model_c_extract_info.R`. Reuse quarter comparison logic from `R/evaluate_model_c.R`.

**Iteration Strategy.** If exact quarter <85%: examine whether errors cluster on phased/retroactive acts (systematic) or are distributed (noise). If clustered: improve midpoint rule clarification with additional worked examples.

### C4: Magnitude Extraction Blueprint

**S0 Codebook Design.** Structured extraction. Operationalize the fallback hierarchy from `docs/literature_review.md` Section 1.4: Economic Report of the President > calendar year estimates > fiscal year estimates > conference report estimates. Annual rate convention: all magnitudes expressed at annual rates. Distinguish policy-driven revenue changes from growth-driven changes (only policy-driven count). Output format: `{magnitude_billions, currency, annual_rate: true/false, source_tier: 1-4}`. Present-value alternative for multi-year provisions.

**S1 Behavioral Tests.** Test I checks valid numeric output with required fields (magnitude, currency, annual_rate flag, source_tier). Tests II-IV follow standard pattern. Pass criteria: 100% legal outputs, 100% memorization, <5% order sensitivity.

**S2 Zero-Shot Eval.** Compare extracted magnitude to `change_in_liabilities_billion` column in `us_shocks.csv`. Primary metrics: MAPE <30%, Sign accuracy ≥95%. Report scatter plot of predicted vs. actual. Bootstrap 1000 resamples for 95% CIs.

**S3 Error Analysis Plan.** Ablation on fallback hierarchy guidance to test whether the model follows source priority correctly. Primary risk: multiple revenue estimates in the same passage (e.g., ERP estimate vs. conference report estimate) confuse the model. Error categories: wrong source tier selected, magnitude off by order of magnitude, sign error, policy/growth confusion.

**Migration from Legacy Code.** Split magnitude extraction from `R/model_c_extract_info.R` and `R/evaluate_model_c.R`.

**Iteration Strategy.** If MAPE >30%: examine whether errors are systematic (e.g., consistently picking wrong source tier, or confusing fiscal year vs. calendar year estimates) vs. random. If sign accuracy <95%: examine whether sign errors correlate with ambiguous language about "revenue effects" vs. "tax changes."

---

## Files to Create

### Codebooks (`/prompts/`)

- ✅ `c1_measure_id.yml`
- ✅ `c2a_extraction.yml` — per-chunk motivation evidence extraction (v0.4.0)
- ✅ `c2b_classification.yml` — act-level signed-exogenous classification from extracted evidence (v0.7.0)
- `c3_timing.yml`
- `c4_magnitude.yml`

### H&K Stage Functions (`/R/`)

- ✅ `codebook_stage_0.R` — Load YAML codebook, validate required fields (label, label_definition, clarification, negative_clarification, output_instructions) and optional fields (description, positive_examples, negative_examples). Examples are optional to preserve country-agnostic transferability — H&K ablation shows examples are the highest-impact individual component, but US-specific examples would reduce cross-country applicability (see Cross-Country Transfer Strategy). Few-shot evaluation with country-specific examples is available as an S3 ablation to quantify the precision cost. Construct LLM prompt from structured components. Returns a validated codebook object.
- ✅ `codebook_stage_1.R` — Run Tests I-IV on a codebook. Takes codebook object + test documents. Returns tibble of test results with pass/fail per test.
- ✅ `codebook_stage_2.R` — Zero-shot classification and optional LOOCV for any codebook type (C1-C4). Zero-shot is the primary S2 evaluation; LOOCV is available for S3 few-shot ablation. Returns predictions + metrics with bootstrap CIs.
- ✅ `codebook_stage_3.R` — Run Tests V-VII and ablation studies. Returns error analysis report with ablation results. Error categorization (H&K taxonomy A-F) is manual, not automated.
- ✅ `behavioral_tests.R` — Shared test functions: `test_legal_outputs()` (Test I), `test_definition_recovery()` (Test II), `test_example_recovery()` (Test III), `test_order_invariance()` (Test IV), `test_exclusion_criteria()` (Test V), `test_generic_labels()` (Test VI), `test_swapped_labels()` (Test VII).

### Notebooks (`/notebooks/`)

**Existing (updated):**

- `verify_body.qmd` — ✅ RR1 source coverage, 6 verification tests with interpretive commentary
- `data_overview.qmd` — Align with new codebook terminology

**New (create):**

- ✅ `c1_measure_id.qmd`
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
tar_target(c2a_codebook, load_validate_codebook("prompts/c2a_extraction.yml"))
tar_target(c2b_codebook, load_validate_codebook("prompts/c2b_classification.yml"))
tar_target(c3_codebook, load_validate_codebook("prompts/c3_timing.yml"))
tar_target(c4_codebook, load_validate_codebook("prompts/c4_magnitude.yml"))

# C1: Measure ID pipeline
tar_target(c1_s1_results, run_behavioral_tests_s1(c1_codebook, aligned_data))
tar_target(c1_s2_test_set, assemble_zero_shot_test_set(c1_codebook, aligned_data))
tar_target(c1_s2_results, run_zero_shot(c1_codebook, c1_s2_test_set))
tar_target(c1_s2_eval, evaluate_zero_shot(c1_s2_results, aligned_data))
tar_target(c1_s3_results, run_error_analysis(c1_codebook, c1_s3_test_set, aligned_data))

# C2: Motivation pipeline (two-codebook architecture)
# S1: independent behavioral tests per sub-codebook
tar_target(c2_input_data, assemble_c2_input_data(c1_classified_chunks))
tar_target(c2a_s1_results, run_c2a_behavioral_tests_s1(c2a_codebook, c2_input_data))
tar_target(c2b_s1_results, run_c2b_behavioral_tests_s1(c2b_codebook))
# S2/S3: end-to-end evaluation of composed C2a→C2b pipeline
tar_target(c2_s2_results, run_zero_shot(c2a_codebook, c2b_codebook, c2_s2_test_set))
tar_target(c2_s3_results, run_error_analysis(c2a_codebook, c2b_codebook, c2_s3_test_set))

# C3: Timing pipeline
tar_target(c3_s1_results, run_behavioral_tests_s1(c3_codebook, aligned_data))
tar_target(c3_s2_results, run_zero_shot(c3_codebook, c3_s2_test_set))
tar_target(c3_s3_results, run_error_analysis(c3_codebook, c3_s3_test_set, aligned_data))

# C4: Magnitude pipeline
tar_target(c4_s1_results, run_behavioral_tests_s1(c4_codebook, aligned_data))
tar_target(c4_s2_results, run_zero_shot(c4_codebook, c4_s2_test_set))
tar_target(c4_s3_results, run_error_analysis(c4_codebook, c4_s3_test_set, aligned_data))

# Aggregation
tar_target(shocks_llm, aggregate_outputs(c1_s2_results, c2_s2_results,
                                          c3_s2_results, c4_s2_results))
```

**Model configuration.** Each API-calling target hardcodes its own model config (provider, model ID, base URL, API key) directly in the `tar_target()` call — no shared globals. This prevents changing one codebook/stage's model from invalidating another's cached results. Validated stages (C1 S1-S3) use `claude-haiku-4-5-20251001`; exploration and S1 iteration use `qwen/qwen-2.5-72b-instruct` via OpenRouter (see `docs/model_discovery.md`). The code block above omits model arguments for readability; see `_targets.R` for the actual target definitions.

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
3. **S2 Baseline:** Zero-shot metrics computed and documented
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
- **C2 two-stage architecture**: Evidence extraction per chunk, then act-level classification from extracted evidence — fits any context window, compresses signal, enables C1/C2 error decomposition

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