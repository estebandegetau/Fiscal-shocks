# Prompts Directory

This directory contains YAML codebook definitions for the C1-C4 fiscal shock identification pipeline, following the Halterman & Keith (2025) semi-structured codebook format.

## Codebooks (C1-C4)

| File | Codebook | R&R Step | Task | Status |
|------|----------|----------|------|--------|
| `c1_measure_id.yml` | C1: Measure ID | RR2 | Binary classification: does passage describe a fiscal measure meeting "significant mention" rule? | Not started |
| `c2_motivation.yml` | C2: Motivation | RR5 | 4-class motivation classification + derived exogenous flag | Not started |
| `c3_timing.yml` | C3: Timing | RR4 | Structured extraction of implementation quarter(s) using midpoint rule | Not started |
| `c4_magnitude.yml` | C4: Magnitude | RR3 | Structured extraction of fiscal impact magnitude | Not started |

## Format Specification

Codebook YAML files follow the format defined in `.claude/skills/codebook-yaml/SKILL.md`. Key requirements:

- Top-level `codebook:` wrapper with `name`, `version`, `description`, `instructions`, `classes`, `output_instructions`
- Each class has: `label`, `label_definition`, `clarification`, `negative_clarification`, `positive_examples`, `negative_examples`
- Labels use `UPPER_SNAKE_CASE`
- Definitions and clarifications must be country-agnostic (US-specific terms only in examples)
- Each clarification item must be independently testable for H&K ablation studies

## Legacy Files (Retained for Reference)

These files belong to the superseded Model A/B/C approach. They are retained for reference but are not used in the current C1-C4 pipeline.

- `model_a_system.txt` -- System prompt for Model A (Act Detection)
- `model_a_examples.json` -- Few-shot examples for Model A

## References

- `docs/strategy.md` -- Authoritative methodology (C1-C4 blueprints, success criteria, targets pipeline)
- `docs/literature_review.md` -- Implementation-critical details from R&R and H&K for codebook design
- `.claude/skills/codebook-yaml/SKILL.md` -- YAML format specification and validation checklist
