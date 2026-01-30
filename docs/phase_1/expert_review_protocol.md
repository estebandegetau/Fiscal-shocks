# Expert Review Protocol for Phase 1 Malaysia Deployment

## Purpose

This document establishes the expert validation protocol for LLM-assisted fiscal shock identification in Malaysia (1980-2022). Since self-consistency metrics cannot reliably flag errors (100% agreement even on incorrect predictions), we implement a rule-based flagging system combined with structured expert review.

## Review Categories

The flagging rules prioritize expert attention on cases where the model is most likely to err, based on error analysis from US test data.

### Category 1: Mandatory Review

**Condition**: Predicted exogenous + recession year

**Rationale**: EGTRRA-type errors occur when recession-era acts with reform language are misclassified as Long-run instead of Countercyclical. Economic context matters most for these cases.

**Expected volume**: ~10-15% of identified acts

**Review questions**:
1. Was this act enacted primarily in response to economic conditions?
2. Does the stated "efficiency" or "reform" language mask a countercyclical intent?
3. What do contemporary documents say about the timing motivation?

### Category 2: Secondary Review

**Condition**: Predicted Countercyclical OR Long-run motivation

**Rationale**: These two categories are most commonly confused (they share similar reform language). Spending-driven and Deficit-driven acts have clearer textual signals.

**Expected volume**: ~20-25% of identified acts

**Review questions**:
1. Was there an economic downturn in the 1-2 years preceding this act?
2. Were rebates or immediate stimulus components emphasized?
3. Was the act part of a multi-year structural reform agenda?

### Category 3: Auto-Accept

**Condition**: All other predictions (Spending-driven or Deficit-driven with no flagging criteria)

**Expected volume**: ~60-65% of identified acts

**Action**: Accept model classification; include in random validation sample (10% spot check)

## Flagging Implementation

### Recession Years for Malaysia (1980-2022)

Based on World Bank GDP growth data and IMF reports:

| Period | Context | Flag Level |
|--------|---------|------------|
| 1985-1986 | Commodity price crash | Recession |
| 1997-1998 | Asian Financial Crisis | Major recession |
| 2001 | Global slowdown | Mild recession |
| 2008-2009 | Global Financial Crisis | Recession |
| 2020 | COVID-19 | Major recession |

### Automatic Flagging Rules

```r
flag_for_review <- function(prediction, year) {
  recession_years <- c(1985, 1986, 1997, 1998, 2001, 2008, 2009, 2020)

  if (prediction$pred_exogenous && year %in% recession_years) {
    return(list(
      flag = "mandatory_review",
      reason = "Exogenous prediction during recession year - high error risk"
    ))
  }

  if (prediction$pred_motivation %in% c("Countercyclical", "Long-run")) {
    return(list(
      flag = "secondary_review",
      reason = "Countercyclical/Long-run boundary case - moderate error risk"
    ))
  }

  return(list(flag = "auto_accept", reason = NULL))
}
```

## Expert Validation Form

### Act Identification (Model A)

For each identified fiscal act:

| Field | Description |
|-------|-------------|
| Act Name | As identified by the model |
| Year | Year of enactment |
| Model Confidence | Model A probability score |
| **Expert Assessment** | |
| Is Fiscal Act? | Yes / No / Partially (components only) |
| Correct Act Name? | Yes / No (provide correction if No) |
| Missing Components? | Were significant provisions missed? |
| Comments | Free-text explanation |

### Motivation Classification (Model B)

For acts flagged for review:

| Field | Description |
|-------|-------------|
| Act Name | As identified |
| Model Prediction | Motivation category |
| Model Exogenous | TRUE/FALSE |
| Review Flag | Mandatory / Secondary |
| **Expert Assessment** | |
| Agree with Motivation? | Yes / No |
| Correct Motivation | If No, select: Spending-driven / Countercyclical / Deficit-driven / Long-run |
| Agree with Exogenous? | Yes / No |
| Key Evidence | What evidence supports your classification? |
| Error Type | If disagreement: (1) Language vs substance confusion (2) Missing economic context (3) Institutional difference (4) Other |
| Comments | Free-text explanation |

### Missed Acts Checklist

Known major Malaysia fiscal events the model MUST identify:

| Event | Year | Found by Model? | Expert Notes |
|-------|------|-----------------|--------------|
| Asian Crisis Response Package | 1997-1998 | | |
| National Economic Recovery Plan | 1998 | | |
| GST Introduction | 2015 | | |
| GST Repeal (return to SST) | 2018 | | |
| PRIHATIN COVID Stimulus | 2020 | | |
| [Other major acts expert identifies] | | | |

## Agreement Metrics

### Primary Metrics

| Metric | Formula | Target |
|--------|---------|--------|
| Act Identification Agreement | (Expert confirms) / (Model identified) | ≥80% |
| Motivation Agreement | (Expert agrees) / (Reviewed acts) | ≥70% |
| Exogenous Agreement | (Expert agrees on flag) / (Reviewed acts) | ≥75% |
| False Positive Rate | (Incorrectly identified) / (Model identified) | ≤10% |
| False Negative Rate | (Expert missed acts) / (All true acts) | Qualitative |

### Cohen's Kappa

For inter-rater reliability (if using multiple experts):

```r
calculate_agreement <- function(expert_labels, model_labels) {
  # Overall accuracy
  accuracy <- mean(expert_labels == model_labels)

  # Cohen's kappa for chance-corrected agreement
  confusion <- table(Expert = expert_labels, Model = model_labels)
  n <- sum(confusion)
  po <- sum(diag(confusion)) / n
  pe <- sum(rowSums(confusion) * colSums(confusion)) / n^2
  kappa <- (po - pe) / (1 - pe)

  list(
    accuracy = accuracy,
    kappa = kappa,
    interpretation = case_when(
      kappa >= 0.81 ~ "Almost perfect agreement",
      kappa >= 0.61 ~ "Substantial agreement",
      kappa >= 0.41 ~ "Moderate agreement",
      kappa >= 0.21 ~ "Fair agreement",
      TRUE ~ "Slight/poor agreement"
    )
  )
}
```

## Error Taxonomy

### Type 1: Language vs Substance Confusion

**Description**: Model classifies based on textual framing rather than economic substance.

**Example**: EGTRRA 2001 called "growth" act but enacted for countercyclical stimulus.

**Detection**: Expert identifies recession-era acts with "reform" language misclassified as Long-run.

**Mitigation**: Add economic context to prompts; adjust few-shot examples.

### Type 2: Missing Economic Context

**Description**: Model lacks awareness of contemporaneous economic conditions.

**Example**: Classifying 1997 Malaysia act as Long-run without knowing Asian Crisis context.

**Detection**: Acts during recession years flagged as exogenous.

**Mitigation**: Provide recession year data in prompt; train model on crisis-period acts.

### Type 3: Institutional Differences

**Description**: US-trained model misunderstands Malaysia parliamentary/fiscal structure.

**Example**: Misinterpreting "Budget speech" as proposal vs enacted legislation.

**Detection**: Expert notes systematic errors in Malaysia-specific terminology.

**Mitigation**: Add Malaysia-specific examples; clarify terminology in system prompt.

### Type 4: Document Extraction Errors

**Description**: PDF extraction missed or garbled text, model worked with incomplete information.

**Example**: Tables with fiscal figures not extracted, model couldn't assess magnitude.

**Detection**: Expert notes missing information that was in source documents.

**Mitigation**: Improve extraction pipeline; supplement with manual review.

### Type 5: Ambiguous Ground Truth

**Description**: Even experts disagree on correct classification.

**Example**: Act with both deficit reduction AND growth objectives.

**Detection**: Multiple experts disagree; extended discussion needed.

**Resolution**: Document as ambiguous case; not counted as model error.

## Review Workflow

### Phase 1B: Initial Validation (Weeks 5-8)

1. **Week 5**: Prepare review materials
   - Export all identified acts with model predictions
   - Flag acts according to rules above
   - Create expert validation spreadsheet

2. **Week 6**: Expert reviews mandatory + secondary flagged acts
   - Expected: 30-40% of acts need review
   - Provide economic context documents for reference

3. **Week 7**: Expert reviews random sample of auto-accept acts
   - Sample 10% for spot-check
   - Identify missed major acts

4. **Week 8**: Calculate agreement metrics
   - Run agreement calculation functions
   - Identify systematic error patterns
   - Prepare refinement recommendations

### Phase 1C: Refinement (Weeks 9-10)

1. **Week 9**: Analyze errors by type
   - Group errors using taxonomy above
   - Prioritize high-impact fixes

2. **Week 10**: Re-run on error cases
   - Update prompts/examples
   - Validate fixes don't introduce regression

## Quality Control

### Expert Qualification

- Familiar with Malaysia fiscal policy history (1980-2022)
- Can access/interpret primary source documents
- Understanding of Romer & Romer methodology
- Available for 10-20 hours over 4-week period

### Documentation Requirements

- All expert judgments must include brief reasoning
- Disagreements with model should cite specific evidence
- Ambiguous cases flagged for secondary review

### Audit Trail

All validation stored in:
```
data/processed/malaysia_expert_validation.csv
data/processed/malaysia_review_log.md
```

## Success Thresholds

| Metric | Threshold | Action if Below |
|--------|-----------|-----------------|
| Act Identification Agreement | <80% | Document as transfer failure; consider Option 2 |
| Motivation Agreement | <70% | Add Malaysia few-shot examples; re-run |
| Exogenous Precision | <90% | Flag ALL exogenous predictions for mandatory review |
| False Positive Rate | >10% | Raise Model A confidence threshold |

## Integration with Phase 1 Documents

This protocol integrates with:
- **[malaysia_strategy.md](malaysia_strategy.md)**: Overall strategic approach
- **[CLAUDE.md](CLAUDE.md)**: Implementation context for Claude Code
- **[README.md](README.md)**: Quick reference

## Appendix: Sample Validation Spreadsheet

```csv
act_id,act_name,year,pred_motivation,pred_exogenous,pred_confidence,review_flag,expert_is_fiscal_act,expert_motivation,expert_exogenous,expert_agrees_motivation,error_type,expert_comments
1,1997 Economic Stimulus Act,1997,Long-run,TRUE,0.95,mandatory_review,Yes,Countercyclical,FALSE,No,language_vs_substance,"Act framed as 'structural reform' but clearly crisis response"
2,2015 GST Implementation,2015,Deficit-driven,TRUE,0.92,auto_accept,Yes,Deficit-driven,TRUE,Yes,,"Correctly identified as deficit reduction measure"
...
```
