# Strategic Plan: Malaysia Deployment Given Data Constraints

## Problem Statement

**User Concern**: "I don't think Malaysia has more fiscal acts than the US, as the political stable window in Malaysia is maybe 1980-2022s. Moreover, we do not have proper labels for Malaysia, we're going to have to test after deployment: we'll need to send the final dataset to someone who actually knows a bit about the economic history of the country."

**Reality Check**:

- US training data: 44 acts with full labels (1945-2022, 77 years)
- Malaysia estimate: 20-40 acts (1980-2022, 42 years, fewer regime changes)
- No ground truth labels for Malaysia
- Validation = post-deployment expert review

**Core Challenge**: The original plan assumed 126 acts and recommended "100+ acts for Malaysia" — both infeasible.

**Authoritative Methodology**: See `docs/strategy.md` for the complete R&R + H&K framework. Phase 1 applies validated codebooks (C1-C4) to Malaysia with expert validation.

## Strategic Options

### Option 1: Cross-Country Transfer Learning (Recommended)

**Approach**: Validate codebooks on US data, deploy to Malaysia with expert validation loop

**Implementation**:

1. **Phase 0 (Current)**: Develop and validate codebooks C1-C4 on 44 US acts using H&K stages S0-S3
2. **Phase 1**: Deploy validated codebooks to Malaysia documents (1980-2022)
3. **Validation**: Expert reviews codebook outputs, provides corrections
4. **Iteration**: Use expert feedback to refine codebook definitions (S0 revision)

**Advantages**:
- Leverages existing US training data
- No need for upfront Malaysia labeling
- Expert validates final outputs (quality over quantity)
- Tests true "zero-shot transfer" capability

**Risks**:
- Different fiscal policy language/institutions
- Model may miss Malaysia-specific patterns
- Expert time required for validation

**Success Metrics**:
- Expert agreement rate (target: 80%+ on random sample)
- Coverage: Did we find known major acts? (e.g., 1997 crisis measures)
- Precision: False positive rate on expert review

**Resource Requirements**:
- 1 Malaysia fiscal policy expert (10-20 hours)
- Iterative deployment cycles (3-4 rounds)

---

### Option 2: Semi-Supervised Active Learning

**Approach**: LLM generates candidates, expert labels subset, refine codebooks

**Implementation**:

1. Deploy codebooks C1-C4 to Malaysia documents
2. Expert labels top 20-30 codebook-identified acts (high confidence)
3. Add Malaysia-specific examples to codebook definitions (S0 revision)
4. Re-run H&K S2 evaluation and validate

**Advantages**:

- Creates Malaysia-specific examples for codebooks
- Codebooks adapt to local language/patterns
- Expert focuses on highest-value labeling

**Risks**:

- Requires expert time upfront (labeling 20-30 acts = 40-60 hours)
- May not improve over zero-shot if sample too small
- Delays Phase 1 timeline

**Success Metrics**:

- Same as Option 1, plus:
- Performance improvement after codebook revision (∆F1)

**Resource Requirements**:
- 1 Malaysia expert (40-60 hours for labeling)
- 2-3 weeks additional timeline

---

### Option 3: Qualitative Validation (Low-Resource)

**Approach**: Focus on methodology validation, not scale

**Implementation**:
1. Deploy to Malaysia, extract 5-10 major known acts
2. Expert validates these specific cases in depth
3. Use as proof-of-concept, not comprehensive dataset

**Advantages**:
- Minimal expert time (5-10 hours)
- Validates methodology cross-country
- Honest about limitations in paper

**Risks**:
- Not a "scaled" dataset (contradicts two-pager narrative)
- Limited research contribution
- May not justify LLM approach vs manual

**Success Metrics**:
- Case study agreement (did we correctly extract known acts?)
- Qualitative assessment of LLM reasoning

---

### Option 4: Adjust Phase 1 Target Country

**Approach**: Choose country with more fiscal volatility/documentation

**Candidates**:
- **UK**: Parliamentary system, extensive Hansard records, 1945-present
- **Canada**: Federal budgets well-documented, similar to US
- **Australia**: Comparable institutions, good digital archives

**Advantages**:
- May have more acts (50-80 range)
- Better documentation/digitization
- English language (no translation issues)

**Risks**:
- Delays Phase 1 (need new data acquisition)
- May face same ground truth problem
- Malaysia-specific research questions lost

---

## Recommended Path Forward

**Primary: Option 1 (Cross-Country Transfer)** with elements of Option 3

### Rationale:
1. **Realistic about data constraints**: Acknowledge Malaysia has ~20-40 acts
2. **Tests core hypothesis**: Can LLMs scale narrative identification across countries?
3. **Feasible validation**: Expert review is achievable (10-20 hours)
4. **Honest contribution**: Methodology validation, not just dataset scale

### Implementation Plan:

**Phase 1A: Deployment (Weeks 1-4)**

1. Extract Malaysia documents (1980-2022)
2. Run codebooks C1-C4 with US-validated definitions
3. Generate candidate dataset (~20-40 acts expected)

**Phase 1B: Expert Validation (Weeks 5-8)**
1. Engage Malaysia fiscal policy expert
2. Review random sample (50% of acts, ~10-20)
3. Flag errors, suggest corrections
4. Check for missed major acts (e.g., 1997 crisis, GST introduction)

**Phase 1C: Refinement (Weeks 9-10)**

1. Analyze error patterns using H&K S3 methodology
2. Adjust codebook definitions (S0 revision)
3. Re-run on error cases
4. Final expert sign-off

**Phase 1D: Paper Revisions (Weeks 11-12)**
1. Update two-pager: Emphasize **methodology transfer**, not just scale
2. Add Malaysia as "cross-country validation" section
3. Report expert agreement rates + qualitative findings
4. Acknowledge sample size limitations honestly

### Adjusted Success Criteria:

**Primary**:

- Expert agreement ≥80% on measure identification (C1)
- Expert agreement ≥70% on motivation classification (C2)
- Correctly identified ≥3 known major acts (e.g., 1997 crisis measures)

**Secondary**:

- False positive rate ≤10% on expert review (precision critical)
- Timing/magnitude extraction within ±10% (C3/C4, if applicable)

**Research Contribution**:
- Demonstrated cross-country transfer without retraining
- Identified where LLM succeeds/fails (error analysis)
- Methodology generalizes beyond US

---

## Paper Framing Adjustments

### Current Two-Pager Claim:
> "The project begins by training and benchmarking an LLM on the US narrative corpus with Romer & Romer's original tax-shock labels"

**Issue**: Implies large-scale benchmark (126 acts) and perfect scalability.

### Revised Framing:

> "Phase 0 develops and validates codebooks C1-C4 on 44 US fiscal acts using the H&K validation framework. Phase 1 tests cross-country transfer to Malaysia (1980-2022) with expert validation, demonstrating methodology generalizability despite limited training data."

**Emphasis Shift**:

- FROM: "Scale" (100+ acts per country)
- TO: "Transfer learning" (validate US, deploy elsewhere)
- FROM: "Automated pipeline" (no human in loop)
- TO: "LLM-assisted extraction" (expert validation)

---

## Open Questions

1. **Expert Access**: Do we have a Malaysia fiscal policy expert identified?
   - If yes → Option 1 viable
   - If no → Consider Option 4 (UK/Canada)

2. **Timeline Constraints**: Is 12-week Phase 1 acceptable?
   - If yes → Option 1
   - If urgent → Option 3 (limited validation)

3. **Research Goals**: What's the primary contribution?
   - Methodology validation → Option 1/3
   - Dataset creation → Option 2/4
   - Proof-of-concept → Option 3

4. **Two-Pager Audience**: Can we adjust framing?
   - Academic paper → Honest about limitations (Option 1)
   - Grant proposal → May need Option 4 (different country with more acts)

---

## Next Steps (Pending User Decision)

1. **Decide on Option**: Which strategic path to pursue?
2. **Expert Engagement**: Identify Malaysia expert or pivot country?
3. **Update Documents**:
   - `docs/two_pager.qmd`: Revise scalability claims
   - `docs/strategy.md`: Authoritative methodology reference
   - Create `docs/phase_1/phase1_report.qmd` with results after completion
4. **Targets Pipeline**: No changes needed yet (Phase 0 complete)

---

## Recommendation Summary

**Go with Option 1**: Cross-country transfer learning with expert validation.

**Key Message**: "We're not building 100-act datasets for every country. We're demonstrating that country-agnostic codebooks validated on limited US data can assist experts in identifying fiscal shocks cross-country, reducing manual effort from months to weeks."

This is a **stronger** research contribution than just "we labeled more acts."

---

## Implementation Checklist

### Immediate (Week 1)
- [ ] Secure Malaysia expert commitment
- [ ] Update two-pager framing
- [ ] Identify Malaysia document sources
- [ ] Create Phase 1 data acquisition plan

### Phase 1A: Deployment (Weeks 1-4)

- [ ] Download Malaysia government documents (1980-2022)
- [ ] Run PDF extraction (Docling or pdftools)
- [ ] Deploy codebooks C1-C4 with US-validated definitions
- [ ] Generate candidate measure dataset
- [ ] Document any extraction failures

### Phase 1B: Expert Validation (Weeks 5-8)
- [ ] Prepare validation protocol for expert
- [ ] Send random sample (10-20 acts) for review
- [ ] Collect expert feedback (errors, missed acts)
- [ ] Identify known major fiscal events (e.g., 1997 crisis)
- [ ] Calculate agreement metrics

### Phase 1C: Refinement (Weeks 9-10)

- [ ] Analyze systematic errors using H&K S3 methodology
- [ ] Adjust codebook definitions based on error patterns (S0 revision)
- [ ] Re-run on error cases
- [ ] Final expert validation round
- [ ] Finalize Malaysia fiscal shock dataset

### Phase 1D: Documentation (Weeks 11-12)
- [ ] Update two-pager with Malaysia results
- [ ] Write Phase 1 report with error analysis
- [ ] Create visualization of expert agreement
- [ ] Document methodology transfer lessons
- [ ] Prepare for Phase 2 (other SEA countries)

---

## Cost Estimates (Option 1)

| Component | Estimated Cost |
|-----------|----------------|
| PDF Extraction (Malaysia docs) | $3-5 |
| Codebook C1-C4 Deployment (20-40 acts × 4 codebooks) | $8-12 |
| Expert Consultation (15 hours @ $100/hr) | $1,500 |
| Refinement Round (Re-run models) | $4-6 |
| **Total** | **~$1,520** |

**Note**: Expert time dominates cost. If expert unavailable, pivot to Option 4 (UK/Canada) where World Bank may have internal expertise.

---

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Expert unavailable | Medium | High | Identify backup expert or pivot country |
| Malaysia docs poor quality | Medium | Medium | Supplement with IMF Article IV reports |
| Expert disagreement >20% | Low | High | Add second expert for tie-breaking |
| Codebooks fail to transfer | Low | Critical | This validates research question! Document failure modes using H&K S3 |
| Timeline slips to 16 weeks | High | Low | Acceptable delay for quality validation |

---

## Success Definition

**This project succeeds if**:

1. We demonstrate country-agnostic codebooks can assist (not replace) experts in cross-country fiscal shock identification
2. Expert validation shows ≥80% agreement on measure identification
3. We honestly document where the method works and where it fails using H&K S3 error analysis
4. The methodology can be replicated for other countries

**This project does NOT require**:

- 100+ acts per country
- Perfect accuracy without human review
- Fully automated pipeline
- Matching Romer & Romer's 77-year US dataset in other countries

The contribution is **methodology**, not **scale**.
