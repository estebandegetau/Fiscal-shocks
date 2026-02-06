---
name: codebook-yaml
description: Format guide for writing and editing YAML codebooks (C1-C4) following the Halterman & Keith (2025) semi-structured codebook format. Apply when creating or modifying any codebook YAML file in prompts/.
user-invocable: false
---

# Codebook YAML Format Guide

This skill defines conventions for all YAML codebook files (`prompts/c1_*.yml`, `prompts/c2_*.yml`, etc.). Apply these rules when creating or editing codebook definitions.

## Reference Documents

Before writing or modifying a codebook, read:

1. `docs/strategy.md` for codebook-to-R&R-phase mapping and success criteria
2. `docs/literature_review.md` for implementation-critical details from R&R and H&K
3. `docs/methods/Methodology for Quantifying Exogenous Fiscal Shocks.md` for R&R operationalizations
4. `docs/methods/The Halterman & Keith Framework for LLM Content Analysis.md` for H&K format specs

## File Structure

Each codebook is a single YAML file in `prompts/`:

```
prompts/
  c1_measure_id.yml     # C1: Measure Identification
  c2_motivation.yml     # C2: Motivation Classification
  c3_timing.yml         # C3: Timing Extraction
  c4_magnitude.yml      # C4: Magnitude Extraction
```

## Top-Level Structure

```yaml
codebook:
  name: "C1: Measure Identification"
  version: "0.1.0"
  description: >
    One-paragraph task description explaining what the LLM must do.

  instructions: >
    Overall task instructions provided to the LLM before the class definitions.
    Must describe the input format, expected output format, and any global rules.

  classes:
    - label: "CATEGORY_NAME"
      # ... class definition (see below)

  output_instructions: >
    Output reminder enumerating all valid labels.
    Example: "Classify the passage using exactly one of the following labels:
    FISCAL_MEASURE, NOT_FISCAL_MEASURE"
```

## Class Definition Structure (Required Fields)

Every class MUST include all of the following fields. This follows H&K Figure 1.

```yaml
- label: "DEFICIT_DRIVEN"
  label_definition: >
    A single sentence defining the class. Must be precise enough that a domain
    expert could apply it without additional context.

  clarification:
    - "Inclusion criterion 1: specific enough to ablate individually"
    - "Inclusion criterion 2: each item testable in isolation"
    - "Key evidence phrases that indicate this category"

  negative_clarification:
    - "Exclusion rule 1: addresses the most common confusion case"
    - "Exclusion rule 2: distinguishes from the nearest neighboring class"
    - "Boundary case: how to handle ambiguous situations"

  positive_examples:
    - text: >
        A passage from a real or realistic document that clearly belongs
        to this category.
      reasoning: >
        Explanation of why this passage fits the definition, referencing
        specific phrases and connecting them to the clarification criteria.

  negative_examples:
    - text: >
        A passage that is a plausible near-miss for this category but
        actually belongs to a different class or fails an exclusion criterion.
      reasoning: >
        Explanation of why this passage does NOT fit, referencing the
        specific negative clarification rule that excludes it.
```

## Rules

### Field Requirements

- **label**: UPPER_SNAKE_CASE string. This is the exact string the LLM must return.
- **label_definition**: Exactly one sentence. No bullet points or sub-items.
- **clarification**: List of 2-5 items. Each item must be specific enough to remove individually for ablation testing (H&K Table 4).
- **negative_clarification**: List of 2-5 items. Must address the most common confusion cases between this class and its nearest neighbors.
- **positive_examples**: At least 1, ideally 2-3. Each must have both `text` and `reasoning`.
- **negative_examples**: At least 1, ideally 2-3. Each must have both `text` and `reasoning`. Should be near-misses, not obviously wrong examples.
- **output_instructions**: Must enumerate every valid label explicitly.

### Example Quality

- **text** fields should be realistic passages (from R&R data, government documents, or closely modeled on them)
- **reasoning** fields must reference specific codebook criteria, not just assert correctness
- Positive examples should demonstrate the prototypical case AND at least one edge case
- Negative examples should be near-misses that test the boundary between classes
- Each example pair (positive + negative) should illuminate one specific distinction

### Country-Agnostic Language (CRITICAL)

Codebooks must transfer across countries without modification. Follow these rules:

| Instead of... | Write... |
|---------------|----------|
| "Tax liabilities" (when US-specific) | "Fiscal liabilities or obligations" |
| "Ways and Means Committee" | "Relevant legislative committee" |
| "Economic Report of the President" | "Official economic outlook or assessment documents" |
| "Billions USD" | "Domestic currency, billions" |
| "Congress" | "Legislature" or "legislative body" |
| "President" | "Head of government" or "executive" |
| US-specific act names in definitions | Generic descriptions of fiscal actions |

**Exception**: US-specific terminology IS allowed in examples (text + reasoning fields), since examples are inherently country-specific. But definitions, clarifications, and negative clarifications must be country-agnostic.

### Ablation-Ready Design

Per H&K Table 4, each codebook component may be individually removed during S3 error analysis. Design with this in mind:

- Each clarification item should make an independent, testable contribution
- Removing any single clarification should measurably change model behavior
- Do not combine multiple criteria into a single clarification bullet
- Negative clarifications should each address a distinct confusion pattern

### Output Instructions Format

The output_instructions field must:

1. Remind the LLM of the exact valid labels
2. Specify the output format (plain text label, JSON, etc.)
3. Include any structured output requirements

Example for C2 (Motivation):
```yaml
output_instructions: >
  Classify the motivation using exactly one of: SPENDING_DRIVEN,
  COUNTERCYCLICAL, DEFICIT_DRIVEN, LONG_RUN.

  Then determine exogeneity: EXOGENOUS if the motivation is DEFICIT_DRIVEN
  or LONG_RUN; ENDOGENOUS if SPENDING_DRIVEN or COUNTERCYCLICAL.

  Return your answer as:
  Label: [MOTIVATION]
  Exogenous: [EXOGENOUS/ENDOGENOUS]
  Reasoning: [Brief explanation citing specific evidence from the passage]
```

## S0-S3 Workflow

Codebook development follows a sequential stage-gate process. Each stage must pass before proceeding to the next.

1. **S0 (Codebook Preparation)**: Draft the YAML codebook following the structure in this SKILL. All required fields must be present. Submit for domain expert approval before proceeding.
2. **S1 (Behavioral Tests)**: Run Tests I-IV (see below) to verify the codebook produces sane model behavior. All tests must pass thresholds before proceeding to evaluation.
3. **S2 (Zero-Shot Evaluation)**: Run LOOCV on 44 US acts using `R/codebook_stage_2.R`. Compare results to success criteria in `docs/strategy.md`. If targets are not met, return to S0 for codebook revision.
4. **S3 (Error Analysis)**: Run Tests V-VII plus ablation studies. Categorize errors using H&K taxonomy (A-F). Use findings to inform S0 revisions or, as a last resort, trigger S4.

The stage-gate rule: **do not proceed to S(N+1) until S(N) passes.** Iteration loops back to S0 (codebook revision), not forward to the next stage.

## Behavioral Test Design (S1)

H&K define 7 behavioral tests (their Table 3). Tests I-IV run during S1; Tests V-VII run during S3.

### S1 Tests (Run Before Evaluation)

| Test | Name | What It Checks | Codebook Fields Used |
|------|------|---------------|---------------------|
| **I** | Legal Output | Does the model always return valid output matching the schema? | `output_instructions` |
| **II** | Definition Recovery | Given the label definition as input text, does the model return the correct label? | `label`, `label_definition` |
| **III** | Example Recovery | Given positive/negative examples, does the model return the correct labels? | `positive_examples`, `negative_examples` |
| **IV** | Order Invariance | Does shuffling the order of class definitions change predictions? | `classes` (ordering) |

**Pass criteria for all codebooks**: Test I: 100% valid outputs. Test II: 100% correct labels. Test III: 100% correct labels. Test IV: <5% label change rate across orderings.

### S3 Tests (Run During Error Analysis)

| Test | Name | What It Checks | Codebook Fields Used |
|------|------|---------------|---------------------|
| **V** | Exclusion Criteria | Does removing a negative clarification increase errors for that confusion case? | `negative_clarification` (individual items) |
| **VI** | Generic Labels | Does replacing label names with LABEL_1..N change predictions? | `label` (names vs. definitions) |
| **VII** | Swapped Labels | Does swapping definitions across label names change predictions? | `label`, `label_definition` (cross-assignment) |

Tests VI and VII detect whether the model relies on the semantic content of label names rather than the definitions. This is especially critical for C2 (motivation), where class names like `DEFICIT_DRIVEN` carry strong semantic priors.

## Semantic Label Risk (Tests VI/VII)

H&K find that LLMs can rely on the semantic meaning of label names rather than reading the actual definitions. This is a major risk for this project because C2's labels (`SPENDING_DRIVEN`, `COUNTERCYCLICAL`, `DEFICIT_DRIVEN`, `LONG_RUN`) are highly semantically loaded.

**Mitigation guidance for codebook authors:**

- Write definitions that add information beyond what the label name implies
- Include negative clarifications that explicitly contradict the "obvious" reading of the label name (e.g., "An act is NOT `DEFICIT_DRIVEN` merely because the word 'deficit' appears in the passage")
- Ensure the distinction between classes cannot be resolved by label name alone
- For C2 specifically: the countercyclical/long-run boundary requires the "return to normal" test, which is NOT implied by either label name

**When to worry:** If Test VI (generic labels) produces significantly different results than the original labels, the model is relying on label semantics. If Test VII (swapped labels) produces results that follow the swapped names rather than the swapped definitions, the model is ignoring definitions entirely.

## Output Instruction Templates

### C1: Measure Identification

```yaml
output_instructions: >
  Classify the passage using exactly one of: FISCAL_MEASURE, NOT_FISCAL_MEASURE.

  Return your answer as JSON:
  {
    "label": "FISCAL_MEASURE" or "NOT_FISCAL_MEASURE",
    "measure_name": "Name of the act if FISCAL_MEASURE, null otherwise",
    "reasoning": "Brief explanation citing specific evidence from the passage"
  }
```

### C2: Motivation Classification

```yaml
output_instructions: >
  Classify the motivation using exactly one of: SPENDING_DRIVEN,
  COUNTERCYCLICAL, DEFICIT_DRIVEN, LONG_RUN.

  Then determine exogeneity: EXOGENOUS if the motivation is DEFICIT_DRIVEN
  or LONG_RUN; ENDOGENOUS if SPENDING_DRIVEN or COUNTERCYCLICAL.

  Return your answer as JSON:
  {
    "label": "MOTIVATION_LABEL",
    "exogenous": true or false,
    "reasoning": "Brief explanation citing specific evidence from the passage"
  }
```

### C3: Timing Extraction

```yaml
output_instructions: >
  Extract the implementation timing for the fiscal measure.

  Return your answer as JSON:
  {
    "timing": [
      {"quarter": "YYYY-QN", "amount_at_annual_rate": number_or_null}
    ],
    "retroactive": true or false,
    "reasoning": "Brief explanation of how timing was determined"
  }

  Use the midpoint rule for phased changes. Record each phase as a
  separate entry. Use null for amount if not extractable from this passage.
```

### C4: Magnitude Extraction

```yaml
output_instructions: >
  Extract the fiscal impact magnitude of the measure.

  Return your answer as JSON:
  {
    "magnitude_billions": number,
    "currency": "USD",
    "annual_rate": true or false,
    "source_tier": 1-4,
    "sign_convention": "positive = tax increase / revenue gain",
    "reasoning": "Brief explanation citing the source of the estimate"
  }

  Source tier: 1 = ERP/official economic assessment, 2 = calendar year estimate,
  3 = fiscal year estimate, 4 = conference report / legislative estimate.
  Prefer the highest-tier (lowest number) source available.
```

## Codebook-Specific Notes

### C1: Measure Identification
- Binary classification: FISCAL_MEASURE vs NOT_FISCAL_MEASURE
- Must operationalize R&R's "significant mention" rule
- Must exclude extensions and withholding-only changes
- Include extraction instruction for identified measure text

### C2: Motivation Classification
- 4-class: SPENDING_DRIVEN, COUNTERCYCLICAL, DEFICIT_DRIVEN, LONG_RUN
- Plus derived exogeneity flag (not a separate classification)
- Must handle mixed motivations (apportionment guidance)
- Boundary between COUNTERCYCLICAL and LONG_RUN is the critical distinction

### C3: Timing Extraction
- Structured extraction, not classification
- Must operationalize the midpoint rule
- Must handle phased changes (multiple quarters per act)
- Must handle retroactive components (standard vs adjusted series)

### C4: Magnitude Extraction
- Structured extraction of revenue estimates
- Must specify the fallback hierarchy for sources
- Must distinguish policy-driven from growth-driven revenue changes
- Annual rate convention must be explicit

## Validation Checklist

Before finalizing any codebook, verify:

- [ ] All required fields present for every class
- [ ] label_definition is exactly one sentence per class
- [ ] Every example has both text and reasoning
- [ ] Negative examples are near-misses, not strawmen
- [ ] No US-specific terminology in definitions or clarifications
- [ ] Each clarification item is independently testable (ablation-ready)
- [ ] output_instructions enumerate all valid labels
- [ ] Version number follows semver (start at 0.1.0)
