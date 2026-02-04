# Archived Documentation

This directory contains historical documentation from the project's earlier Model A/B/C approach. These files are preserved for reference but have been superseded by the new C1-C4 codebook framework documented in `docs/strategy.md`.

## Why These Files Were Archived

In January 2026, the project transitioned from an ad-hoc Model A/B/C approach to a structured methodology integrating:

- **Romer & Romer (2010)**: 6-phase methodology for identifying exogenous fiscal shocks
- **Halterman & Keith (2025)**: 5-stage framework for rigorous LLM content analysis

The new approach uses 4 domain-specific codebooks (C1-C4) that map to R&R phases, each processed through the full H&K validation pipeline.

## Archive Contents

### `phase_0/`

Historical Model A/B/C implementation documents:

- `plan_phase0.md` - Original Phase 0 implementation plan
- `model_a_development.md` - Model A development history
- `model_A_extractor_design.md` - Model A passage extractor design
- `model_a_results_summary.md` - Model A performance evaluation
- `model_a_precision_improvements.md` - Precision enhancement strategies
- `model_a_implementation.md` - Model A implementation details
- `days_1-2_implementation_summary.md` - Early implementation notes
- `failed_extraction_investigation.md` - Extraction failure analysis

### `phase_1/`

- `IMPLEMENTATION_SUMMARY.md` - Original Phase 1 implementation summary

### `claude_plans/`

Historical Claude Code agent plan files (auto-generated during development).

## Current Documentation

For the current methodology, see:

- `docs/strategy.md` - Authoritative strategy document (C1-C4 + H&K framework)
- `docs/methods/` - Reference methodology documents (R&R, H&K)
- `docs/phase_0/CLAUDE.md` - Phase 0 implementation context
- `docs/phase_1/CLAUDE.md` - Phase 1 deployment context
