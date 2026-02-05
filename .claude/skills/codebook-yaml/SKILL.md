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
