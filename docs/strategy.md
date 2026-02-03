# High-Level Strategy: R&R + H&K Framework for Fiscal Shock Identification

## Executive Summary

**Objective:** Transform a collection of fiscal policy documents (e.g., `us_body`) into a balanced quarterly dataset of exogenous fiscal shocks (e.g., `us_shocks.csv`) using LLMs to transfer the knowledge gathered by Romer & Romer in the US to other countries.

**Approach:** Integrate two rigorous frameworks:

- **Romer & Romer (2010)**: 6-phase methodology for identifying exogenous fiscal shocks
- **Halterman & Keith (2025)**: 5-stage framework for rigorous LLM content analysis

**Key Innovation:** Create 4 domain-specific codebooks (one per R&R LLM phase), each processed through the full H&K validation pipeline before moving to the next. The pipeline is designed to be **country-agnostic** to enable transfer learning across countries without retraining.

**Research Contribution:** Novel synthesis framing — first application of H&K validation framework to economic history/fiscal policy domain.

**Reference Documents:**

- R&R Methodology: `docs/methods/Methodology for Quantifying Exogenous Fiscal Shocks.md`
- H&K Framework: `docs/methods/The Halterman & Keith Framework for LLM Content Analysis.md`

---

## The Complete R&R Pipeline

The Romer & Romer methodology consists of 6 phases. Phases 2-5 are implemented as LLM codebooks; Phases 1 and 6 are data engineering tasks.

| Phase | Task | Implementation | Output |
|-------|------|----------------|--------|
| **1: Source Compilation** | Gather fiscal policy documents | Data engineering | Document corpus |
| **2: Measure ID** | Identify fiscal measures meeting "significant mention" rule | Codebook 1 (LLM) | Binary + extraction |
| **3: Quantification** | Extract fiscal impact in billions USD | Codebook 4 (LLM) | Magnitude per quarter |
| **4: Timing** | Extract implementation quarter(s) using midpoint rule | Codebook 3 (LLM) | List of quarters |
| **5: Motivation** | Classify motivation and filter exogenous shocks | Codebook 2 (LLM) | 4-class + exogenous flag |
| **6: Aggregation** | Normalize by GDP, aggregate to quarterly series | Data engineering | Shock time series |

---

## Phase 1: Source Compilation (Data Engineering)

### Required Sources (per R&R methodology)

| Source | Purpose | Status |
|--------|---------|--------|
| Economic Report of the President | Executive fiscal narrative | ✅ URLs and text extracted (`erp_urls`, `us_body`) |
| Treasury Annual Reports | Revenue estimates, implementation details | ✅ URLs and text extracted |
| Budget of the United States | Budget proposals, revenue projections | ✅ URLs and text extracted |
| House Ways & Means Committee Reports | Legislative intent, bill details | ❌ Not yet collected |
| Senate Finance Committee Reports | Legislative intent, bill details | ❌ Not yet collected |
| Congressional Record | Floor debates, stated motivations | ❌ Not yet collected |
| CBO Reports (post-1974) | Non-partisan revenue estimates | ❌ Not yet collected |
| Conference Reports | Final bill versions | ❌ Not yet collected |
| Social Security Bulletin | Payroll tax changes | ❌ Not yet collected |

### Existing Pipeline Resources

The current `_targets.R` pipeline already handles:

- PDF URL collection for ERP, Budget, and Treasury reports
- PDF download and text extraction (`us_text`)
- Document body extraction (`us_body`)
- Relevance filtering infrastructure

### Phase 1 Deliverables

**Existing notebooks to update:**

- `notebooks/verify_body.qmd` — Document coverage inventory, extraction quality, gap analysis
- `notebooks/data_overview.qmd` — Training data pipeline documentation

**Updates needed:**

- Align terminology with new codebook naming (C1-C4)
- Add source coverage table showing R&R required sources vs. available
- Document missing sources (Congressional committee reports, CBO, etc.)
- Remove references to legacy Models A/B/C



---

## Architecture: 4 Codebooks × 5 Stages

### The Four Codebooks (R&R Phases 2-5)

| Codebook | R&R Phase | Task | Output Type |
|----------|-----------|------|-------------|
| **C1: Measure ID** | Phase 2 | Does passage describe a fiscal measure meeting "significant mention" rule? | Binary + extraction |
| **C2: Motivation** | Phase 5 | Classify motivation: Spending-driven, Countercyclical, Deficit-driven, Long-run | 4-class + exogenous flag |
| **C3: Timing** | Phase 4 | Extract implementation quarter(s) using midpoint rule | List of quarters |
| **C4: Magnitude** | Phase 3 | Extract fiscal impact in billions USD | Magnitude per quarter + PV |

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

**Order:** C1 → C2 → C3 → C4 (following R&R phase order)

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

---

## Codebook Structure Template

Each codebook follows H&K machine-readable format (see `docs/methods/The Halterman & Keith Framework for LLM Content Analysis.md`):

```yaml
label: "CATEGORY_NAME"
label_definition: >
  Single-sentence definition from R&R methodology.

clarification:
  - Inclusion criterion 1
  - Inclusion criterion 2
  - Key evidence phrases

negative_clarification:
  - Explicit exclusion 1
  - Explicit exclusion 2
  - Common confusion cases

positive_examples:
  - text: "Example passage..."
    reasoning: "Why this qualifies"

negative_examples:
  - text: "Near-miss passage..."
    reasoning: "Why this does NOT qualify"

output_instructions: >
  JSON schema with required fields
```

---

## Implementation Approach

### Step-by-Step Development

Each R&R phase is implemented and validated independently before proceeding to the next. Each phase produces or updates a **Quarto notebook** demonstrating successful implementation.

| Step | Description | Deliverable |
|------|-------------|-------------|
| 1 | Complete source compilation, document coverage gaps | Update `notebooks/verify_body.qmd`, `notebooks/data_overview.qmd` |
| 2 | Implement C1 (Measure ID) through H&K S0-S3 | `notebooks/codebook_1_measure_id.qmd` |
| 3 | Implement C2 (Motivation) through H&K S0-S3 | `notebooks/codebook_2_motivation.qmd` |
| 4 | Implement C3 (Timing) through H&K S0-S3 | `notebooks/codebook_3_timing.qmd` |
| 5 | Implement C4 (Magnitude) through H&K S0-S3 | `notebooks/codebook_4_magnitude.qmd` |
| 6 | Implement aggregation, validate against `us_shocks.csv` | `notebooks/phase_6_aggregation.qmd` |
| 7 | End-to-end pipeline integration and testing | `notebooks/pipeline_integration.qmd` |

### Per-Codebook Implementation Steps

For each codebook (C1-C4):

1. **S0**: Draft codebook YAML based on R&R methodology
2. **S1**: Run behavioral tests, iterate on codebook until pass
3. **S2**: Run LOOCV evaluation, document baseline metrics
4. **S3**: Conduct error analysis, identify failure patterns
5. **Decision**: If metrics acceptable → proceed; if not → improve S0 or (last resort) S4
6. **Document**: Produce Quarto notebook with results

---

## Files to Create

### Codebooks (`/prompts/`)

- `codebook_1_measure_id.yaml`
- `codebook_2_motivation.yaml`
- `codebook_3_timing.yaml`
- `codebook_4_magnitude.yaml`

### H&K Stage Functions (`/R/`)

- `codebook_stage_0.R` - Codebook loading/validation
- `codebook_stage_1.R` - Behavioral tests
- `codebook_stage_2.R` - Zero-shot evaluation
- `codebook_stage_3.R` - Error analysis
- `behavioral_tests.R` - H&K test suite implementation

### Notebooks (`/notebooks/`)

**Existing (update):**

- `verify_body.qmd` — Add R&R source coverage analysis
- `data_overview.qmd` — Align with new codebook terminology

**New (create):**

- `codebook_1_measure_id.qmd`
- `codebook_2_motivation.qmd`
- `codebook_3_timing.qmd`
- `codebook_4_magnitude.qmd`
- `phase_6_aggregation.qmd`
- `pipeline_integration.qmd`

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

### End-to-End (After All Codebooks)

1. Run full pipeline on US documents
2. Verify end-to-end recall ≥85% on 44 known acts
3. Compare extracted shocks to `us_shocks.csv`
4. Document any systematic gaps

### Malaysia Pilot

1. Run pipeline on Malaysia documents (1980-2022)
2. Expert agreement ≥80% on measure identification
3. Expert agreement ≥70% on motivation classification
4. Document transfer learning performance

---

## Key Decisions Summary

- **Country-agnostic design**: Pipeline must transfer to countries without labeled data
- **Production-order sequencing**: C1 → C2 → C3 → C4 to test actual data flow
- **Fine-tuning as last resort**: Preserve transferability by improving codebooks first
- **One notebook per phase**: Clear documentation of each implementation step
- **Explicit methodology references**: Implementing agents consult `docs/methods/` for details
- **Incremental validation**: Each phase validated before proceeding to next

---

## Phase 6: Aggregation (Data Engineering)

### Steps (per R&R methodology)

1. **Normalize by GDP**: Express each nominal shock as percentage of nominal GDP in implementation quarter
2. **Aggregate multiple actions**: Sum GDP percentages for same-motivation shocks in same quarter
3. **Handle phased changes**: Record each implementation step in respective quarters
4. **Produce final series**: Quarterly time series with discrete exogenous shock entries

### Required Data

- Quarterly nominal GDP series (1945-present)
- Codebook outputs: measure ID, magnitude, timing, motivation

### Phase 6 Deliverable

**Quarto notebook:** `notebooks/phase_6_aggregation.qmd`

- Aggregation methodology verification against `us_shocks.csv`
- Validation of GDP normalization
- Final dataset generation