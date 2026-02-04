# Phase 1: Malaysia Deployment

## Overview

Phase 1 focuses on deploying US-validated codebooks (C1-C4) to Malaysia government documents (1980-2022) with expert validation to test cross-country transfer learning.

## Key Documents

1. **[malaysia_strategy.md](malaysia_strategy.md)** — Full strategic plan addressing data constraints and outlining four strategic options for Phase 1 deployment
   - **Recommended approach**: Option 1 (Cross-Country Transfer Learning with Expert Validation)
   - Implementation timeline: 12 weeks
   - Expected output: 20-40 expert-validated fiscal acts

2. **[expert_review_protocol.md](expert_review_protocol.md)** — Expert validation protocol aligned with H&K S3 error analysis methodology

## Authoritative Methodology

See `docs/strategy.md` for the complete R&R + H&K framework specification including:

- The 4 codebook definitions (C1-C4)
- H&K 5-stage validation pipeline
- Cross-country transfer strategy
- Malaysia adaptation protocol

## Strategic Framing

**Reality Check**:

- US training data: 44 acts with labels (not 126 as initially assumed)
- Malaysia estimate: 20-40 acts (1980-2022, 42-year political stable window)
- No ground truth labels for Malaysia

**Emphasis**:

- FROM: "Scale" (100+ acts per country)
- TO: "Transfer learning methodology" (train US, validate cross-country)
- FROM: "Automated pipeline"
- TO: "LLM-assisted extraction with expert validation"

## The Four Codebooks

| Codebook | Task | Output |
|----------|------|--------|
| C1: Measure ID | Does passage describe a fiscal measure? | Binary + extraction |
| C2: Motivation | Classify motivation category | 4-class + exogenous flag |
| C3: Timing | Extract implementation quarter(s) | List of quarters |
| C4: Magnitude | Extract fiscal impact | Magnitude per quarter |

## Success Criteria

**Primary**:

- Expert agreement ≥80% on measure identification (C1)
- Expert agreement ≥70% on motivation classification (C2)
- Correctly identified ≥3 known major acts (e.g., 1997 crisis measures)

**Secondary**:

- False positive rate ≤10% on expert review (precision critical)
- Timing/magnitude extraction within ±10% (C3/C4, if applicable)

**Research Contribution**:

- Demonstrated cross-country transfer without retraining
- Identified where codebooks succeed/fail (error analysis)
- Methodology generalizes beyond US

## Implementation Phases

1. **Phase 1A: Deployment (Weeks 1-4)** — Extract Malaysia documents, run codebooks C1-C4
2. **Phase 1B: Expert Validation (Weeks 5-8)** — Expert reviews outputs, flags errors
3. **Phase 1C: Refinement (Weeks 9-10)** — Adjust codebook definitions, re-run error cases
4. **Phase 1D: Documentation (Weeks 11-12)** — Update papers, report findings

## Resource Requirements

- 1 Malaysia fiscal policy expert (10-20 hours validation time)
- API costs: ~$8-12 for LLM deployment
- Expert consultation: ~$1,500 (if external)
- Timeline: 12 weeks

## Next Steps

1. Complete Phase 0 codebook validation (C1-C4 through H&K S0-S3)
2. Secure Malaysia expert commitment
3. Identify Malaysia document sources (parliamentary records, budget documents, treasury reports)
4. Create Phase 1 data acquisition targets
5. Prepare expert validation protocol

## Contact

For questions about Phase 1 strategy, see the full [malaysia_strategy.md](malaysia_strategy.md) document or contact the project team lead.
