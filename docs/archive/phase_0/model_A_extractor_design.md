# Model A Extractor Design: From Classifier to Passage Extractor

**Status:** Implementation Complete
**Date:** 2026-01-31
**Author:** Claude (implementation), Esteban Degetau (design direction)

## Executive Summary

This document describes the redesign of Model A from a binary classifier ("does this passage contain a fiscal act?") to a passage extractor ("extract all fiscal act passages from this document chunk"). This change bridges a critical gap between Phase 0 training and Phase 1 production deployment.

---

## 1. The Problem: Training-Production Gap

### Phase 0 Training Architecture

In Phase 0 (US Benchmark), we have access to `us_labels.csv`—human-curated passages that describe specific fiscal acts. The original Model A was designed as a binary classifier:

```
Input:  Pre-segmented passage (from us_labels.csv)
Output: {contains_act: bool, act_name: string, confidence: float}
```

This works for **validation**: we can measure whether the model correctly identifies passages we already know contain acts.

### Phase 1 Production Reality

For Malaysia (Phase 1) and other new countries, we have:
- Raw government documents (PDFs)
- No `us_labels.csv` equivalent
- No pre-segmented passages

The classifier cannot help us because **there is nothing to classify**. We need a model that can:

```
Raw documents → ??? → Passages for Models B & C
                ^
           The missing step
```

### The Gap

| Phase | Available Input | Required Output |
|-------|----------------|-----------------|
| Phase 0 | Pre-segmented passages | Classification |
| Phase 1 | Raw documents | Extracted passages |

The classifier assumption (passages exist) doesn't hold in production.

---

## 2. The Solution: Passage Extractor

### New Architecture

Transform Model A from classifier to extractor:

```
Input:  Document chunk (25 pages, ~20K tokens)
Output: {
  "acts": [
    {
      "act_name": "Revenue Act of 1964",
      "year": 1964,
      "passages": [
        {"text": "The Revenue Act...", "page_numbers": [12], "confidence": 0.95}
      ],
      "reasoning": "Contemporaneous description of tax legislation"
    }
  ],
  "no_acts_found": false,
  "extraction_notes": "..."
}
```

### Key Changes

| Aspect | Old (Classifier) | New (Extractor) |
|--------|------------------|-----------------|
| Input | Single passage (~500 tokens) | Document chunk (~20K tokens) |
| Output | Single decision | List of extracted acts |
| Task | Binary classification | Passage identification + extraction |
| Granularity | Per-passage | Per-chunk |
| Page tracking | Not applicable | Absolute page numbers |
| Grouping | Not applicable | Passages grouped by act |

---

## 3. System Prompt Design Decisions

### 3.1 Why Keep the Same Core Criteria?

The extraction prompt (`model_a_extract_system.txt`) preserves the classification criteria from the original prompt (`model_a_system.txt`):

```
CRITERIA FOR FISCAL ACT PASSAGES (must meet ALL):
1. References specific legislation
2. Describes the POLICY CHANGE ITSELF
3. Must be contemporaneous or near-contemporaneous to enactment
4. Involves federal taxes or spending (not state/local)
5. Shows clear enactment language OR implementation details
```

**Rationale:** These criteria were validated during Phase 0 classification experiments. Changing them would invalidate our training-time validation. The extractor must find the same passages that the classifier would approve.

### 3.2 The Contemporaneous vs. Retrospective Distinction

The prompt emphasizes this distinction heavily:

```
INCLUDE: "The Revenue Act of 1964 reduces tax rates by..." (describing the change)
EXCLUDE: "Since the 1993 deficit reduction plan, the economy has..." (retrospective)
EXCLUDE: "The 1986 tax reform was enacted to..." (historical summary in later document)
```

**Why this matters:** Government documents frequently reference past legislation. The ERP 2000 mentions the Tax Reform Act of 1986, but this is a historical reference, not contemporaneous documentation. Without this distinction, the extractor would generate massive false positives by extracting every historical mention.

**This is the single most important precision control** in the prompt. Error analysis during Phase 0 showed that most false positives were retrospective references classified as contemporaneous.

### 3.3 Explicit Page Number Instructions

```
PAGE NUMBER EXTRACTION:
- Page numbers are indicated by "--- PAGE BREAK ---" markers in the text
- Count page breaks to determine page numbers (first section = page 1, after first break = page 2, etc.)
- Add the start_page offset provided in the metadata to get absolute page numbers
```

**Rationale:** Page numbers enable:
1. **Expert validation:** Reviewers can verify extractions by jumping to the source page
2. **Deduplication:** Overlapping chunks may extract the same passage; page numbers help identify duplicates
3. **Traceability:** The final fiscal shock dataset can reference source pages

Without explicit instructions, the model often returns relative page numbers within the chunk rather than absolute document pages.

### 3.4 Grouping Instructions

```
GROUPING INSTRUCTIONS:
- Group all passages about the SAME act together under one act entry
- Different provisions or sections of the same act should be in the same act entry
- If multiple acts are mentioned in the chunk, create separate entries for each
```

**Rationale:** A single act (e.g., Tax Reform Act of 1986) may span multiple pages and paragraphs within a chunk. Without grouping instructions, the model might return separate entries for "rate reduction provisions" and "base broadening provisions" of the same act, creating duplicates downstream.

### 3.5 Empty Chunk Handling

```
If NO fiscal acts are found in the chunk, return:
{
  "acts": [],
  "no_acts_found": true,
  "extraction_notes": "Reason why no acts were found..."
}
```

**Rationale:** Most chunks contain no fiscal acts. Budget tables, appendices, and economic forecasts dominate government documents. Explicit handling:
1. Prevents hallucination of acts to "fill" the response
2. Provides insight into document composition ("chunk contains only tables")
3. Enables debugging when expected acts aren't found

---

## 4. Design Decisions and Alternatives Considered

### 4.1 Chunk Size: 25 Pages vs. 50 Pages

**Decision:** Use 25-page chunks with 5-page overlap for extraction.

**Alternatives considered:**
- **50 pages (original):** Better for full-document context but risks missing details in dense sections
- **10 pages:** Higher precision but more API calls, higher cost, and loss of cross-section context

**Rationale:**
- Extraction requires closer attention than classification
- 25 pages ≈ 20K tokens, well within model limits with room for examples
- Smaller chunks mean more chunks, but extraction quality is paramount
- The 5-page overlap (vs. 10-page for 50-page chunks) handles boundary cases

### 4.2 Self-Consistency for Extraction

**Decision:** Use self-consistency sampling (n=5, temperature=0.7) with majority voting on extracted acts.

**How it works:**
1. Run extraction 5 times with temperature 0.7
2. Normalize act names for matching across samples
3. Include act if it appears in ≥50% of samples
4. Aggregate passages from all samples that found the act

**Rationale:** Extraction is more uncertain than classification. An act mentioned in 5/5 samples is more reliable than one mentioned in 1/5. The 50% threshold filters noise while allowing legitimate acts that the model sometimes misses.

**Implication:** Each chunk requires 5 API calls, increasing cost 5x. For 500 chunks, this is 2,500 API calls (~$15-20). Worth it for extraction quality.

### 4.3 Post-Extraction Grouping

**Decision:** Implement `group_passages.R` with fuzzy matching (Jaro-Winkler, threshold 0.85).

**Problem solved:** The same act may be extracted from multiple chunks with slightly different names:
- "Revenue Act of 1964"
- "The Revenue Act of 1964"
- "Revenue Act, 1964"

**Alternative considered:** Require exact name matches. Rejected because government documents use inconsistent naming.

**Implication:** Fuzzy matching may incorrectly merge distinct acts with similar names (e.g., "Revenue Act of 1962" and "Revenue Act of 1964"). Mitigated by:
- Including year in matching
- Year mismatch >1 year blocks merge
- Expert checkpoint reviews grouped acts

### 4.4 Staged Transition Strategy

**Decision:** Keep both classifier (`model_a_detect_acts.R`) and extractor (`model_a_extract_passages.R`) during transition.

**Validation approach:**
1. Run extractor on US documents
2. Compare: Does extractor find the same acts that classifier would approve from us_labels passages?
3. Target: Recall ≥90%, Precision ≥80%

**Rationale:** The extractor is a new model with different failure modes. Keeping the classifier allows:
- A/B comparison on US data
- Fallback if extractor underperforms
- Gradual deprecation after validation

---

## 5. Downstream Implications

### 5.1 Training Example Generation

The pipeline now generates extraction examples (`model_a_extract_examples`) from `aligned_data` + `us_body`:

```r
tar_target(
  model_a_extract_examples,
  generate_model_a_extraction_examples(
    aligned_data = aligned_data,
    us_body = us_body,
    n_positive = 5,
    n_negative = 3
  )
)
```

**Implication:** Examples show the model how to extract passages **from real document context**, not just classify pre-segmented text. This is synthetic (we embed known passages into random context) but approximates production conditions.

### 5.2 Expert Review Checkpoint

The production pipeline includes an explicit checkpoint after extraction:

```
Model A Extraction → Expert Checkpoint 1 → Model B Classification
```

**Expert tasks at Checkpoint 1:**
- Validate extracted acts are real (not hallucinations)
- Add missed acts
- Remove false positives
- Correct act names

**Implication:** The extractor doesn't need perfect precision. Expert review catches errors. The goal is high recall (don't miss real acts) with acceptable precision (some false positives tolerable if caught by review).

### 5.3 Model B Input Changes

Model B (`model_b_classify_motivation`) previously received passages from `us_labels.csv`. In production, it receives:
- `grouped_acts$act_name` - canonical name from extraction
- `grouped_acts$passages_text` - concatenated passages from all chunks
- `grouped_acts$year` - extracted or inferred year

**Implication:** Passages may be longer (multiple chunks concatenated) or shorter (only one mention found). Model B must handle variable passage lengths. The prompt doesn't assume fixed-length input.

### 5.4 Evaluation Metrics Shift

**Phase 0 (classifier):**
- Precision, Recall, F1 on passage classification

**Phase 1 (extractor):**
- **Act Recall:** % of known acts (from us_shocks.csv) extracted
- **Passage Precision:** Manual review of extracted passages
- **False Discovery Rate:** % of extracted "acts" that aren't real acts

**Implication:** We can't compute precision automatically (no ground truth for what's NOT an act). Requires sampling + manual review.

### 5.5 Cost Implications

| Component | Classifier | Extractor |
|-----------|-----------|-----------|
| Input tokens/call | ~1K | ~20K |
| Calls per doc | ~10 passages | ~4 chunks |
| Self-consistency | 5x | 5x |
| Total per doc | 50 calls × 1K = 50K tokens | 20 calls × 20K = 400K tokens |

**Implication:** Extractor is ~8x more expensive per document.

---

## 5.6 Cost Estimation Formula

### Parameters

| Parameter | Symbol | Default Value | Notes |
|-----------|--------|---------------|-------|
| Number of documents | D | varies | Total PDFs to process |
| Average pages per document | P | 200 | US ERPs ~250, Budgets ~150, Treasury ~100 |
| Chunk window size | W | 25 | Pages per chunk |
| Chunk overlap | O | 5 | Overlapping pages |
| Self-consistency samples | N | 5 | API calls per chunk |
| Input tokens per chunk | T_in | 20,000 | ~4 chars/token, 25 pages |
| Output tokens per chunk | T_out | 2,000 | JSON response with passages |
| Input price (per 1K tokens) | $P_in | $0.003 | Claude Sonnet pricing |
| Output price (per 1K tokens) | $P_out | $0.015 | Claude Sonnet pricing |

### Formulas

**Chunks per document:**
```
C = ceil((P - W) / (W - O)) + 1
```

For default values: C = ceil((200 - 25) / (25 - 5)) + 1 = ceil(8.75) + 1 = **10 chunks/document**

**API calls per document:**
```
API_calls = C × N = 10 × 5 = 50 calls/document
```

**Tokens per document:**
```
Tokens_in  = C × N × T_in  = 10 × 5 × 20,000 = 1,000,000 input tokens
Tokens_out = C × N × T_out = 10 × 5 × 2,000  = 100,000 output tokens
```

**Cost per document:**
```
Cost = (Tokens_in / 1000) × $P_in + (Tokens_out / 1000) × $P_out
Cost = (1,000,000 / 1000) × $0.003 + (100,000 / 1000) × $0.015
Cost = $3.00 + $1.50 = $4.50 per document
```

### Cost Estimation Table

| Documents (D) | Chunks | API Calls | Input Tokens (M) | Output Tokens (M) | **Total Cost** |
|---------------|--------|-----------|------------------|-------------------|----------------|
| 1 | 10 | 50 | 1.0 | 0.1 | **$4.50** |
| 10 | 100 | 500 | 10.0 | 1.0 | **$45** |
| 50 | 500 | 2,500 | 50.0 | 5.0 | **$225** |
| 100 | 1,000 | 5,000 | 100.0 | 10.0 | **$450** |
| 350 (US full) | 3,500 | 17,500 | 350.0 | 35.0 | **$1,575** |

### Simplified Formula

For quick estimation:

```
Total Cost ≈ $4.50 × D
```

Where D = number of documents (assuming ~200 pages average).

### Cost Reduction Strategies

| Strategy | Savings | Trade-off |
|----------|---------|-----------|
| Reduce self-consistency (N=3) | 40% | Lower extraction reliability |
| Increase chunk size (W=50) | 50% | Lower extraction precision |
| Use Haiku for filtering | 60-70% | Two-stage pipeline complexity |
| Disable self-consistency (N=1) | 80% | No agreement rate, lower confidence |

**Recommended for budget-constrained deployment:**
```
N=3, W=25 → Cost ≈ $2.70 × D
```

### Phase 1 (Malaysia) Cost Estimate

Assuming:
- 150 documents (42 years × ~3-4 docs/year)
- 150 pages average (shorter than US docs)
- Standard settings (N=5, W=25)

```
Chunks = ceil((150 - 25) / 20) + 1 = 8 chunks/document
Cost = (8 × 5 × 20,000 / 1000 × $0.003) + (8 × 5 × 2,000 / 1000 × $0.015)
     = $2.40 + $1.20 = $3.60 per document

Total Malaysia = 150 × $3.60 = $540
```

### Time Estimation

With rate limiting (2s between calls):
```
Time = API_calls × 2 seconds
Time = D × 50 × 2 = 100 × D seconds = 1.67 × D minutes
```

| Documents | API Calls | Time (minutes) | Time (hours) |
|-----------|-----------|----------------|--------------|
| 10 | 500 | 17 | 0.3 |
| 50 | 2,500 | 83 | 1.4 |
| 100 | 5,000 | 167 | 2.8 |
| 350 | 17,500 | 583 | 9.7 |

**Note:** These are sequential estimates. Parallel processing can reduce wall-clock time but not API cost.

---

## 6. Files Implemented

| File | Purpose |
|------|---------|
| `R/model_a_extract_passages.R` | Core extraction functions |
| `prompts/model_a_extract_system.txt` | System prompt for extraction task |
| `prompts/model_a_extract_examples.json` | Few-shot examples (regenerated by pipeline) |
| `R/group_passages.R` | Post-extraction grouping and deduplication |
| `R/generate_few_shot_examples.R` | Added `generate_model_a_extraction_examples()` |
| `_targets.R` | Added production pipeline targets |

---

## 7. Open Questions and Future Work

### 7.1 Multi-Document Act References

Some acts are described across multiple documents (e.g., ERP + Budget + Treasury Report for the same year). Current design groups within document but not across documents.

**Potential enhancement:** Cross-document deduplication in `group_passages.R`.

### 7.2 Table Extraction

Current approach extracts text but doesn't specifically handle tables showing act provisions or magnitudes.

**Potential enhancement:** Add table detection and structured extraction for Model C integration.

### 7.3 Non-English Documents

Malaysia Phase 1 may include Malay-language documents. The prompt is English-only.

**Potential enhancement:** Multilingual prompt or translation preprocessing.

---

## 8. Summary

The Model A redesign from classifier to extractor solves the production deployment gap. Key design decisions:

1. **Same criteria, different task:** Preserve validated classification criteria for extraction
2. **Contemporaneous focus:** Heavy emphasis on filtering retrospective references
3. **Smaller chunks:** 25 pages for extraction precision (vs. 50 for classification context)
4. **Self-consistency:** 5 samples with majority voting for reliability
5. **Fuzzy grouping:** Handle act name variations with Jaro-Winkler matching
6. **Staged transition:** Keep classifier for validation during rollout

The extractor enables the full end-to-end pipeline for new countries without pre-existing labeled passages.
