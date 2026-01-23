# Phase 1: Malaysia Deployment — CLAUDE.md

This file provides context for Claude Code when working on Phase 1 implementation.

## Phase 1 Overview

**Goal**: Deploy US-trained LLM models to Malaysia government documents (1980-2022) with expert validation to test cross-country transfer learning.

**Timeline**: 12 weeks (4 weeks deployment, 4 weeks validation, 2 weeks refinement, 2 weeks documentation)

**Status**: PLANNING (Phase 0 must complete first)

**Expected Output**: 20-40 expert-validated Malaysia fiscal acts

## Key Documents

- **[malaysia_strategy.md](malaysia_strategy.md)** - Full strategic plan with 4 options evaluated (READ THIS FIRST)
- **[README.md](README.md)** - Quick reference guide to Phase 1
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - What was implemented in the strategic planning

## Critical Context: Data Constraints

### Reality Check

- **US training data**: 44 labeled fiscal acts (not 126)
- **Malaysia estimate**: 20-40 acts (1980-2022, 42-year political stable window)
- **No ground truth labels** for Malaysia (expert validation required)
- **Cannot expect**: 100+ acts per country

### Strategic Pivot

❌ **NOT**: Fully automated pipeline generating large-scale datasets
✅ **YES**: LLM-assisted methodology with expert validation loop

**Research Contribution**: Transfer learning methodology, not just dataset scale

## Recommended Approach: Option 1

**Cross-Country Transfer Learning with Expert Validation**

See [malaysia_strategy.md](malaysia_strategy.md) for full details. Summary:

1. Deploy US-trained Models A/B/C to Malaysia documents (no retraining)
2. Expert reviews random sample of outputs (10-20 acts)
3. Analyze error patterns, refine prompts
4. Re-run on error cases, final expert sign-off
5. Document methodology transfer lessons

**Why this is strong**: Shows LLMs can work with limited training data across countries, reducing expert effort from months to weeks.

## Four Strategic Options (Summary)

See [malaysia_strategy.md](malaysia_strategy.md) for detailed comparison.

### Option 1: Cross-Country Transfer Learning (RECOMMENDED)
- Train US, deploy Malaysia, expert validates
- **Pros**: Leverages existing data, tests core hypothesis
- **Cons**: Different institutions/language may cause errors
- **Resources**: 10-20 hours expert time, ~$1,520 total

### Option 2: Semi-Supervised Active Learning
- LLM generates candidates, expert labels 20-30, retrain
- **Pros**: Creates Malaysia training data
- **Cons**: Requires 40-60 hours expert labeling upfront
- **Resources**: Higher expert time, 2-3 weeks delay

### Option 3: Qualitative Validation (Low-Resource)
- Deploy to 5-10 major known acts only, deep validation
- **Pros**: Minimal expert time (5-10 hours)
- **Cons**: Not a "scaled" dataset, limited contribution
- **Resources**: Lowest cost, proof-of-concept only

### Option 4: Pivot to Different Country
- Choose UK/Canada/Australia with better archives
- **Pros**: May have more acts (50-80), English language
- **Cons**: Delays timeline, loses Malaysia research focus
- **Resources**: New data acquisition needed

## Implementation Timeline (12 Weeks)

### Phase 1A: Deployment (Weeks 1-4)
**Goal**: Extract Malaysia documents, run Models A/B/C, generate candidate dataset

**Tasks**:
1. Identify Malaysia document sources:
   - Parliamentary Hansard records (1980-2022)
   - Budget speeches and documents
   - Treasury/Finance Ministry annual reports
   - Economic reports
2. Extract PDFs (use Docling or pdftools)
3. Run Models A/B/C with US prompts (no modification initially)
4. Generate candidate fiscal shock dataset

**Deliverables**:
- Malaysia document corpus (estimated 200-300 PDFs)
- Extracted text in targets pipeline
- Candidate dataset: 20-40 fiscal acts identified by Model A
- Motivation classifications from Model B
- Timing/magnitude extractions from Model C (if applicable)

### Phase 1B: Expert Validation (Weeks 5-8)
**Goal**: Expert reviews LLM outputs, quantifies agreement, identifies errors

**Tasks**:
1. Engage Malaysia fiscal policy expert (World Bank economist or academic)
2. Prepare validation protocol:
   - Random sample of 50% of identified acts (~10-20)
   - Known major acts checklist (1997 Asian crisis measures, GST introduction, etc.)
   - Structured feedback form (agree/disagree + reasoning)
3. Expert reviews:
   - Act identification (Model A): Is this truly a fiscal act?
   - Motivation classification (Model B): Correct category?
   - Missed acts: What did LLM miss?
4. Calculate agreement metrics:
   - Act identification agreement rate (target ≥80%)
   - Motivation agreement rate (target ≥70%)
   - False positive rate (target = 0%)

**Deliverables**:
- Expert validation report
- Agreement metrics
- Error taxonomy (what types of errors occurred?)
- List of missed major acts

### Phase 1C: Refinement (Weeks 9-10)
**Goal**: Analyze errors, adjust prompts, re-run on error cases

**Tasks**:
1. Error analysis:
   - Do errors cluster by time period? (e.g., pre-1990 worse?)
   - Specific language issues? (Malaysian English vs US English?)
   - Institutional differences? (parliamentary system vs presidential)
2. Prompt refinement:
   - Add Malaysia-specific examples to few-shot prompts
   - Clarify terminology (e.g., "Budget speech" vs "Economic Report")
   - Adjust motivation criteria for Malaysian political context
3. Re-run models on error cases
4. Final expert validation round (quick check on refinements)

**Deliverables**:
- Error analysis report
- Updated prompts (Malaysia-adapted versions)
- Re-run results on error cases
- Final expert agreement metrics

### Phase 1D: Documentation (Weeks 11-12)
**Goal**: Update papers, report findings, prepare for Phase 2

**Tasks**:
1. Update `docs/two_pager.qmd` with Malaysia results
2. Write Phase 1 report:
   - Expert agreement rates
   - Error analysis findings
   - Methodology lessons learned
   - Comparison: What worked vs what didn't
3. Create visualization:
   - Expert agreement by category
   - Error distribution by type
   - Timeline of identified Malaysia acts (1980-2022)
4. Prepare Phase 2 plan (other SEA countries)

**Deliverables**:
- Phase 1 report (`docs/phase_1/phase1_report.qmd`)
- Updated two-pager with Malaysia validation results
- Visualization of expert agreement
- Phase 2 implementation plan

## Success Criteria

### Primary (Must Achieve)
- ✅ Expert agreement ≥80% on act identification (Model A)
- ✅ Expert agreement ≥70% on motivation classification (Model B)
- ✅ Correctly identified ≥3 known major acts (e.g., 1997 crisis measures, GST, major tax reforms)

### Secondary (Desirable)
- ✅ Zero false positives on expert review (precision critical)
- ✅ Timing/magnitude extraction within ±10% (Model C, if applicable)
- ✅ Error analysis identifies clear patterns (not random noise)

### Research Contribution (Critical)
- ✅ Demonstrated cross-country transfer without retraining
- ✅ Quantified where LLM succeeds (act detection) and struggles (magnitude extraction)
- ✅ Methodology generalizes beyond US (replicable for other countries)

## Malaysia-Specific Context

### Political Stability Window
**1980-2022 (42 years)** is the reliable window for Malaysia fiscal policy analysis:
- Pre-1980: Independence transition, limited archives
- 1980-1997: Development era, stable governance
- 1997-1998: Asian Financial Crisis (MAJOR fiscal response expected)
- 1998-2018: Post-crisis reforms, alternating coalitions
- 2018-2022: Political transitions, COVID-19 fiscal response

### Known Major Fiscal Acts (Validation Checkpoints)
The LLM MUST identify these if it's working correctly:

1. **1997-1998 Asian Crisis Response**
   - National Economic Recovery Plan (1998)
   - Tax incentives for foreign investment
   - Infrastructure stimulus spending

2. **2015 Goods and Services Tax (GST)**
   - Major tax reform replacing sales tax
   - Highly controversial, later repealed

3. **2018 GST Repeal**
   - Return to sales and service tax (SST)
   - Campaign promise after regime change

4. **2020 COVID-19 Fiscal Packages**
   - PRIHATIN economic stimulus (RM250 billion)
   - Multiple relief packages

If Model A misses 2+ of these, **something is wrong** with the transfer.

### Document Sources (To Be Identified in Week 1)
- **Parliamentary Hansard**: Budget debate transcripts (Bahasa Malaysia + English)
- **Budget Speeches**: Annual, usually in English with Malay translation
- **Economic Reports**: Ministry of Finance annual reports
- **Central Bank Reports**: Bank Negara Malaysia annual reports (may reference fiscal policy)
- **IMF Article IV Reports**: External perspective (supplement, not primary source)

**Language Note**: Many documents are bilingual (English + Bahasa Malaysia). Prefer English versions for initial deployment.

## Targets Pipeline Integration

### New Targets for Phase 1

```r
# Malaysia document acquisition
tar_target(malaysia_urls, fetch_malaysia_document_urls())
tar_target(malaysia_pdfs, download_pdfs(malaysia_urls))
tar_target(malaysia_text, extract_text_docling(malaysia_pdfs))

# Document processing
tar_target(malaysia_documents, structure_documents(malaysia_text))
tar_target(malaysia_paragraphs, extract_paragraphs(malaysia_documents))
tar_target(malaysia_relevant, filter_relevant(malaysia_paragraphs))

# Model deployment (using Phase 0 trained models)
tar_target(
  malaysia_model_a,
  run_model_a(malaysia_relevant),
  # Uses same prompts/functions as Phase 0
)
tar_target(
  malaysia_model_b,
  run_model_b(malaysia_model_a %>% filter(contains_act == TRUE)),
  # Uses same prompts/functions as Phase 0
)
tar_target(
  malaysia_model_c,
  run_model_c(malaysia_model_b),
  # Uses same prompts/functions as Phase 0
)

# Expert validation (manual step, store results)
tar_target(
  expert_validation,
  read_expert_validation("data/processed/malaysia_expert_validation.csv"),
  format = "file"
)

# Evaluation
tar_target(
  malaysia_agreement_metrics,
  calculate_agreement(malaysia_model_a, malaysia_model_b, expert_validation)
)

# Final dataset
tar_target(
  malaysia_shocks,
  finalize_malaysia_dataset(malaysia_model_b, malaysia_model_c, expert_validation)
)
```

### Running Phase 1 Pipeline

```r
# Phase 1A: Deployment
tar_make(malaysia_model_c)  # Runs all dependencies

# Phase 1B: After expert validation file created
tar_make(malaysia_agreement_metrics)

# Phase 1C: Re-run with updated prompts
tar_invalidate(malaysia_model_a)  # Force re-run
tar_make(malaysia_shocks)

# View results
tar_read(malaysia_agreement_metrics)
tar_read(malaysia_shocks)
```

## Resource Requirements

| Resource | Estimate | Notes |
|----------|----------|-------|
| Malaysia fiscal policy expert | 10-20 hours | Validation + refinement feedback |
| API costs (LLM deployment) | $8-12 | 20-40 acts × 3 models |
| PDF extraction | $3-5 | 200-300 Malaysia PDFs |
| Expert consultation (if external) | ~$1,500 | Assuming $100/hr × 15 hours |
| **Total** | **~$1,520** | Dominated by expert time |

**Budget Notes**:
- If expert is internal (World Bank economist), cost drops to ~$20 (API + extraction only)
- If expert unavailable, consider Option 4 (pivot to UK/Canada where internal expertise may exist)

## Common Tasks

### Download Malaysia Documents
```r
# 1. Create URL list (manual or scripted)
malaysia_urls <- tibble(
  url = c(
    "https://www.parliament.gov.my/...",  # Hansard
    "https://www.treasury.gov.my/...",    # Budget
    # ...
  ),
  year = c(1980:2022),
  source = "Parliamentary Hansard"
)

# 2. Add to targets
tar_target(malaysia_urls, create_malaysia_urls())

# 3. Download
tar_make(malaysia_pdfs)
```

### Run Models on Malaysia Data
```r
# Use existing Phase 0 functions, just point at Malaysia data
tar_make(malaysia_model_a)
tar_make(malaysia_model_b)
tar_make(malaysia_model_c)
```

### Expert Validation Workflow
```r
# 1. Export candidate acts for expert review
malaysia_acts <- tar_read(malaysia_model_a) %>%
  filter(contains_act == TRUE)

write_csv(malaysia_acts, "for_expert_review.csv")

# 2. Expert fills out validation form (manual)
# 3. Import expert responses
tar_make(expert_validation)

# 4. Calculate agreement
tar_make(malaysia_agreement_metrics)

# 5. View results
tar_read(malaysia_agreement_metrics)
```

### Refine Prompts After Expert Feedback
```r
# 1. Analyze errors
errors <- tar_read(expert_validation) %>%
  filter(expert_agree == FALSE)

# 2. Update prompts/model_a_examples_malaysia.json
# (Add Malaysia-specific examples)

# 3. Modify model to use Malaysia prompts
# In R/model_a_detect_acts.R:
# - Add `country` parameter
# - Load different examples based on country

# 4. Re-run
tar_invalidate(malaysia_model_a)
tar_make(malaysia_model_a)
```

## Multilingual Considerations

### Document Languages
Malaysia documents may be in:
- **English** (preferred for Phase 1): Budget speeches, economic reports, some Hansard
- **Bahasa Malaysia** (Malay): Parliamentary debates, some official documents
- **Bilingual**: Many documents have both versions

### LLM Handling
**Claude 3.5 Sonnet** has native Bahasa Malaysia support:
- No translation step needed
- Direct comprehension reduces error propagation
- Add language context to prompts:

```r
model_a_detect_acts <- function(text, language = "en") {
  lang_instruction <- switch(language,
    "ms" = "The following passage is in Malay (Bahasa Malaysia).",
    "en" = ""
  )

  # Prepend to user_input
  # ...
}
```

### Strategy
1. **Phase 1A**: Use English documents only (lower risk)
2. **Phase 1C**: If successful, add Bahasa Malaysia documents to test multilingual capability

## Troubleshooting

### Error: Malaysia Documents Not Found
**Cause**: URLs changed, archives moved, paywalls
**Fix**:
- Check `malaysia_urls` target for broken links
- Supplement with IMF Article IV reports (always available)
- Contact Malaysia Treasury/Parliament directly for archives

### Error: Expert Disagrees on 50%+ of Acts
**Cause**: Transfer learning failed, prompts too US-specific
**Decision Point**: This is a **research finding**, not a failure!
- Document what went wrong (institutional differences? language?)
- Consider Option 2 (add Malaysia few-shot examples, retrain)
- Publish findings: "When does cross-country transfer fail?"

### Error: LLM Missed All Known Major Acts
**Cause**: Document extraction failed OR prompts incompatible
**Fix**:
1. Check `malaysia_text` - are documents extracted correctly?
2. Manually verify: Do documents actually discuss fiscal acts?
3. Test on known act (e.g., 1997 crisis response) in isolation
4. If still fails, revert to Option 3 (manual case studies)

### Error: API Costs Exceed Budget
**Cause**: More acts than expected (good problem!)
**Fix**:
- Batch processing with rate limiting
- Use smaller sample for initial validation
- Switch to Haiku for Model A (cheaper, faster)

## Next Steps After Phase 1

**If successful** (expert agreement ≥80%):
→ **Phase 2 (SEA Scaling)**: Indonesia, Thailand, Philippines, Vietnam
→ Methodology proven, replicate across region
→ Each country: 4-week deployment + 2-week expert validation

**If partially successful** (60-79% agreement):
→ **Option 2**: Add Malaysia few-shot examples, retrain
→ **Hybrid approach**: LLM generates candidates, expert reviews all (not sample)
→ Still valuable: Reduces expert workload from 100% manual to 40% review

**If failed** (<60% agreement):
→ **Research contribution**: Document failure modes
→ **Paper focus**: "When Cross-Country Transfer Fails: Institutional Barriers to LLM Fiscal Shock Identification"
→ **Alternative**: Option 4 (pivot to UK/Canada for Phase 2)

## Open Questions (To Be Resolved in Week 1)

1. **Expert Identified?**
   - [ ] World Bank Malaysia economist
   - [ ] External academic (Malaysian university)
   - [ ] Backup: IMF country desk economist

2. **Document Sources Confirmed?**
   - [ ] Parliamentary Hansard access (digital archives)
   - [ ] Budget speech archive (Treasury website)
   - [ ] Economic reports availability

3. **Timeline Constraints?**
   - [ ] 12 weeks acceptable?
   - [ ] Can compress to 8 weeks if needed (reduce refinement phase)?

4. **Research Focus?**
   - [ ] Methodology validation (Option 1) → Academic paper
   - [ ] Dataset creation (Option 2) → Policy impact
   - [ ] Proof-of-concept (Option 3) → Quick win

## References

- **[malaysia_strategy.md](malaysia_strategy.md)** - Full strategic plan (READ THIS)
- **Romer & Romer (2010)**: Original narrative approach methodology
- **Phase 0 Models**: See `docs/phase_0/CLAUDE.md` for model details
- **Targets Guide**: https://books.ropensci.org/targets/

## Contact

For Phase 1 specific questions, see [malaysia_strategy.md](malaysia_strategy.md) or [README.md](README.md).
