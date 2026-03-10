---
name: manual-analysis
description: Human-AI collaborative manual error analysis using H&K 6-category framework (A-F). Pre-screens baseline predictions, presents chunks for human judgment, records results incrementally to iteration log.
user-invocable: true
---

# Manual Analysis Skill

Perform H&K manual error analysis on baseline S3 predictions for a codebook. Claude pre-screens each chunk into a suggested category with rationale; the human reviews, discusses, and makes the final judgment. Results are written incrementally to the iteration log.

## When to Use

Invoke `/manual-analysis` after S3 baseline results are available (with `baseline_details` containing model reasoning). This is H&K's recommended step before concluding S3 — it produces bias-corrected error distributions and documents where the codebook vs. gold standard vs. model are each at fault.

## H&K Error Categories

| Code | Category | Description |
|------|----------|-------------|
| **A** | LLM correct | Parsed label and reasoning are both correct |
| **B** | Incorrect gold standard | After inspection, we disagree with the gold-standard label |
| **C** | Document error | Something wrong with the text (OCR, truncation, missing context) |
| **D** | LLM non-compliance | Model did not comply with output format (hallucinated label, multiple labels) |
| **E** | LLM semantics/reasoning | Compliant output but incorrect label due to reasoning, semantics, or world knowledge error |
| **F** | Other | Codebook ambiguity, parsing error, text ambiguity, label precedence issue |

## Critical Rules

1. **Human assigns the final category.** Claude suggests; the human decides.
2. **Every chunk gets a category** — including correct predictions (Category A). This enables bias-corrected metrics.
3. **Incremental writes.** Each judgment is written to file immediately after approval. If the session is interrupted, completed judgments are preserved.
4. **No API calls.** This skill reads cached results only. It never calls `tar_make()` or the LLM API.

## Procedure

### Step 1: Ask the user

Ask which codebook to analyze (default: `c1`). Confirm S3 results with `baseline_details` are available.

### Step 2: Load data

Run in R:

```r
library(targets); library(dplyr)
ts <- tar_read(c1_s3_test_set)
res <- tar_read(c1_s3_results)
bd <- res$baseline_details

combined <- ts %>%
  mutate(text_id = row_number()) %>%
  left_join(bd, by = "text_id")
```

Verify `combined` has columns: `chunk_id`, `doc_id`, `text`, `tier`, `act_name`, `year`, `true_label`, `text_type`, `label` (predicted), `reasoning`, `raw_response`, `measure_name`.

### Step 3: Pre-screen all 40 chunks

For each chunk, Claude assigns a **preliminary category** (A-F) with a short rationale, based on:

- `true_label` vs `label` (predicted): match or mismatch?
- `reasoning`: does the model's explanation make sense given the text?
- `text`: is the text substantive fiscal content, or an index/glossary/OCR artifact?
- `tier`: Tier 1 (high confidence), Tier 2 (name-matched), or NA (negative)
- `act_name`: which act was the chunk matched to (if any)?

**Pre-screening heuristics:**

- **Match + reasoning sound** → suggest A
- **Match but reasoning references wrong measure or flawed logic** → suggest F (codebook ambiguity) or flag for discussion
- **Mismatch + text is index/glossary/TOC** → suggest B (IKA heuristic noise — gold label wrong)
- **Mismatch + text has real fiscal content not in label set** → suggest B (gold label incomplete)
- **Mismatch + text has OCR issues or truncation** → suggest C
- **Mismatch + model output malformed** → suggest D
- **Mismatch + model reasoning incorrect but output compliant** → suggest E
- **Ambiguous** → suggest F with explanation, flag for discussion

### Step 4: Bucket and present

Split chunks into two groups:

**Confident bucket** — Claude's preliminary category seems clear-cut (typically A for correct predictions, B for obvious IKA noise). Present these in a summary table:

```
CONFIDENT BUCKET (N chunks)

| # | text_id | tier | gold | predicted | suggested | rationale (short) |
|---|---------|------|------|-----------|-----------|-------------------|
| 1 |       1 |    1 | FM   | FM        | A         | Correct, sound reasoning |
| 2 |      11 |    2 | FM   | NFM       | B         | Text is book index, no fiscal content |
...
```

Ask the human to review the table and either:
- **Approve all** — accept Claude's suggestions for the entire bucket
- **Flag specific rows** — identify rows they want to discuss individually

**Discussion bucket** — chunks where the category is ambiguous or the reasoning warrants scrutiny. Present these one at a time.

### Step 5: Discuss flagged chunks

For each chunk in the discussion bucket (and any flagged from the confident bucket), present:

```
--- Chunk [text_id] of 40 ---
Tier: [1/2/negative]    Act: [act_name or "N/A"]
Gold: [true_label]      Predicted: [label]

TEXT (first 500 chars):
[text excerpt]

MODEL REASONING:
[reasoning]

MODEL MEASURE NAME: [measure_name]

CLAUDE'S SUGGESTION: [category] — [rationale paragraph]

Your judgment? [A/B/C/D/E/F] + optional notes:
```

Wait for the human's response. Record their category and any notes.

If the human wants to discuss before deciding, engage in back-and-forth. Claude can:
- Point out specific phrases in the text
- Reference the codebook definition
- Note whether other chunks from the same act/document were classified differently
- Explain why a category was suggested

### Step 6: Write results incrementally

After each chunk judgment (or batch approval), append to a **manual analysis section** in the iteration log (`prompts/iterations/c1.yml`).

Create a new iteration entry with stage `s3_manual_analysis`:

```yaml
- iteration: [N]
  codebook_version: "[version]"
  date: "[YYYY-MM-DD]"
  git_commit: "[hash]"
  model: "[model from S3 results]"
  stage: "s3_manual_analysis"
  changes: >
    Manual error analysis of S3 baseline predictions using H&K 6-category
    framework (A-F). Inspected all [N] baseline chunks.
  results:
    n_inspected: 40
    category_distribution:
      - category: "A_llm_correct"
        count: [n]
        pct: [n/40 * 100]
      - category: "B_incorrect_gold"
        count: [n]
        pct: [n/40 * 100]
      - category: "C_document_error"
        count: [n]
        pct: [n/40 * 100]
      - category: "D_non_compliance"
        count: [n]
        pct: [n/40 * 100]
      - category: "E_semantics_reasoning"
        count: [n]
        pct: [n/40 * 100]
      - category: "F_other"
        count: [n]
        pct: [n/40 * 100]
    chunk_judgments:
      - text_id: 1
        chunk_id: "[chunk_id]"
        tier: [1/2/null]
        gold: "FISCAL_MEASURE"
        predicted: "FISCAL_MEASURE"
        category: "A"
        notes: ""
      # ... one entry per chunk
    bias_corrected_metrics:
      # Recomputed after excluding category B and C chunks from denominator
      effective_n: [40 - B - C]
      accuracy: [recomputed]
      precision: [recomputed]
      recall: [recomputed]
  interpretation: >
    [Human's interpretation — filled in Step 7]
  decision: >
    [Human's decision — filled in Step 7]
```

**Incremental write strategy:** Write the `chunk_judgments` list progressively. After each batch approval or individual judgment, update the file. The `category_distribution`, `bias_corrected_metrics`, `interpretation`, and `decision` fields are filled at the end.

### Step 7: Summarize and interpret

After all 40 chunks are judged, present:

1. **Category distribution** — table with counts and percentages
2. **Bias-corrected metrics** — accuracy/precision/recall excluding B and C chunks
3. **Key patterns** — what do the B, E, and F categories reveal about the codebook and gold standard?

Then ask the human for:
- **Interpretation**: What do these results mean for the codebook and gold standard quality?
- **Decision**: What to do next? (Proceed to C2? Revise codebook? Revise gold standard?)

Record these in the iteration log entry.

### Step 8: Final confirmation

```
Manual analysis complete. [N] chunks inspected.
Results logged to prompts/iterations/c1.yml (iteration [N]).

Category distribution:
  A (LLM correct):           [n] ([pct]%)
  B (Incorrect gold):        [n] ([pct]%)
  C (Document error):        [n] ([pct]%)
  D (Non-compliance):        [n] ([pct]%)
  E (Semantics/reasoning):   [n] ([pct]%)
  F (Other):                 [n] ([pct]%)

Bias-corrected accuracy: [value] (excluding [B+C] chunks)
```

## Error Handling

- **Missing `baseline_details`**: Tell user to re-run S3 with the updated `run_error_analysis()` that captures full model output. Do not proceed.
- **Iteration log doesn't exist**: Create it following the schema in `/log-iteration`.
- **Session interrupted**: Completed judgments are already written. On re-invocation, read existing `chunk_judgments` and resume from the first unjudged chunk.

## What This Skill Does NOT Do

- **Does not call the LLM API** — works entirely from cached S3 results
- **Does not modify the codebook** — that's a separate step after analysis
- **Does not override human judgment** — Claude suggests, human decides
- **Does not compute S2 metrics** — uses S3 baseline only (40-chunk test set)
