# Phase 0 Data Flow Architecture

## Overview

This document clarifies which data sources are used for model training vs. production inference.

---

## Training Data Flow (Used by Models A, B, C)

```
┌─────────────────────────────────────────────────────────────┐
│ GROUND TRUTH DATA (Romer & Romer manual labels)            │
└─────────────────────────────────────────────────────────────┘
           │
           ├─ us_labels.csv (340 labeled passages)
           │  └─ Pre-identified text excerpts containing fiscal acts
           │
           └─ us_shocks.csv (126 fiscal shock events)
              └─ Ground truth: act name, motivation, magnitude, timing
           │
           ↓
┌─────────────────────────────────────────────────────────────┐
│ ALIGNMENT STEP                                              │
│ align_labels_shocks(us_labels, us_shocks)                  │
│ → Fuzzy match act names, concatenate passages per act      │
└─────────────────────────────────────────────────────────────┘
           │
           ↓
    aligned_data (44 acts with passages + labels)
           │
           ↓
┌─────────────────────────────────────────────────────────────┐
│ STRATIFIED SPLITTING                                        │
│ create_train_val_test_splits()                             │
│ → 64% train / 23% val / 14% test (28/10/6 acts)            │
└─────────────────────────────────────────────────────────────┘
           │
           ↓
    aligned_data_split
           │
           ├─────────────────┬─────────────────┐
           ↓                 ↓                 ↓
    training_data_a   training_data_b   training_data_c
    (Act Detection)   (Motivation)      (Info Extraction)
    244 examples      44 acts           41 acts
    (+ negatives)
           │
           ↓
    model_a_predictions_val/test
    model_b_predictions_val/test
    model_c_predictions_val/test
```

**Key Insight:** Training uses **pre-labeled passages** from us_labels.csv, NOT raw PDF chunks.

---

## Production Inference Flow (Future Use - NOT Training)

```
┌─────────────────────────────────────────────────────────────┐
│ RAW GOVERNMENT DOCUMENTS                                    │
└─────────────────────────────────────────────────────────────┘
           │
           ↓
    us_urls (350 PDF URLs)
           │
           ↓
┌─────────────────────────────────────────────────────────────┐
│ PDF EXTRACTION                                              │
│ pull_text_local() or pull_text_lambda()                    │
│ → Extract text from PDFs using PyMuPDF or Docling          │
└─────────────────────────────────────────────────────────────┘
           │
           ↓
    us_text (extracted text per PDF)
           │
           ↓
    us_body (PDF metadata + text)
           │
           ├─────────────────────────────────────┐
           ↓                                     ↓
┌──────────────────────────────┐    ┌─────────────────────────┐
│ CHUNKING (for LLM inference)│    │ NEGATIVE SAMPLING       │
│ make_chunks()                │    │ (for training data)     │
│ → 50-page windows, 10 overlap│    │ generate_negative_      │
│ → Target 40K tokens/chunk    │    │ examples()              │
└──────────────────────────────┘    └─────────────────────────┘
           │                                     │
           ↓                                     ↓
       chunks                            negative_examples
    (UNUSED in training!)              (used in training_data_a)
    (For production inference
     on new documents)
```

**Key Insight:** Chunks are created but NOT consumed by training. They're for future production inference.

---

## Why This Design?

### Training: Use Pre-Labeled Passages

**Advantages:**
1. **Ground truth**: We know exactly which passages contain which acts (Romer & Romer's manual work)
2. **Targeted examples**: Only relevant text is included, no noise
3. **Aligned labels**: Each passage is linked to shock metadata (motivation, magnitude, timing)
4. **Efficient**: 340 passages vs. thousands of chunks

**Source:** `us_labels.csv` contains passages like:
```
act_name: "Revenue Act of 1964"
motivation: "The tax cut was enacted to promote long-term economic growth..."
source: "ERP 1965, p. 12"
```

### Production: Use Chunks

**Purpose:** When processing new, unlabeled documents (e.g., Malaysian budget reports):
1. **Long documents**: Budget reports are 200-500 pages
2. **Context window limits**: LLM max 200K tokens
3. **Sliding windows**: 50-page chunks with 10-page overlap ensure no acts are missed at chunk boundaries

**Example use case:**
```r
# Future production code (not implemented yet)
new_doc_chunks <- make_chunks(malaysia_budget_2023)

for (chunk in new_doc_chunks) {
  detected_acts <- model_a_detect_acts(chunk$text)
  # Process detected acts...
}
```

---

## Dependency Verification

### ✅ Correct (No Dependency)

```r
tar_target(
  model_a_predictions_test,
  {
    # Does NOT reference chunks
    test_data <- training_data_a |> filter(split == "test")
    predictions <- model_a_detect_acts_batch(texts = test_data$text, ...)
    test_data |> bind_cols(predictions)
  }
)
```

**Why correct:** Training data comes from `training_data_a`, which traces back to `us_labels.csv`, not chunks.

### ❌ If Chunks Were Used (Would Need Dependency)

```r
# Hypothetical production inference target (not in current pipeline)
tar_target(
  production_predictions,
  {
    chunks_file <- chunks  # ← Would need explicit dependency!

    predictions <- chunks |>
      mutate(detected_acts = map(text, model_a_detect_acts))
    predictions
  }
)
```

---

## Current Status

| Target | Status | Purpose |
|--------|--------|---------|
| `us_labels` | ✅ Used | Training data source |
| `us_shocks` | ✅ Used | Training labels |
| `aligned_data` | ✅ Used | Training foundation |
| `training_data_a/b/c` | ✅ Used | Model training |
| `chunks` | ⚠️ Created but unused | Reserved for production |
| `chunks_summary` | ⚠️ Created but unused | Reserved for production |

**Recommendation:** Keep `chunks` target for future use, but document that it's not part of training pipeline.

---

## Verification Added

New Test Suite 6 in `notebooks/review_training_data.qmd`:

- **Test 6.1:** Chunks created successfully (95% coverage)
- **Test 6.2:** Chunk size within bounds (median <50K tokens, max <200K)
- **Test 6.3:** Window overlap implemented (~10 pages)
- **Test 6.4:** No missing chunks (complete page coverage)

These tests ensure chunks are production-ready when needed.

---

## Summary

✅ **Training pipeline is correct:**
- Model training uses `us_labels.csv` passages (pre-labeled ground truth)
- No dependency on `chunks` required
- Explicit dependencies properly tracked via `model_a_examples_file`

✅ **Chunks are correctly orphaned:**
- Created for future production use
- Not consumed in current training pipeline
- Verified to be production-ready via Test Suite 6

✅ **Design is sound:**
- Training: Supervised learning from expert labels
- Production: Chunked inference on new documents
- Clear separation of concerns
