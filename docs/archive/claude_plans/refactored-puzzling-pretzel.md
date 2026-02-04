# Phase 0 Implementation Plan: US Benchmark Training for Fiscal Shocks LLM

## Executive Summary

**Goal:** Train an LLM system to read US government documents (1946-present) and output structured fiscal shock data matching Romer & Romer's gold-standard labels.

**Timeline:** 10 days (1-2 weeks for rapid validation)

**Approach:** API-based LLM (Claude 3.5 Sonnet) + Cloud PDF extraction (AWS Lambda)

**Success Criteria:**
1. **Model A (Act Detection)**: F1 > 0.85 against us_labels.csv
2. **Model B (Motivation)**: Accuracy > 0.75 against us_shocks.csv categories
3. **Model C (Information Extraction)**: MAPE < 30% for magnitudes, ±1 quarter for timing against us_shocks.csv

---

## Current State

### Training Data Available
- **us_shocks.csv** (126 fiscal shock events): Act name, date, magnitude, timing, motivation category, exogenous flag, detailed reasoning
- **us_labels.csv** (340 document passages): Text excerpts from original sources aligned to specific acts
- **Original PDFs** (245 documents): Economic Reports of the President, Treasury Annual Reports, Budget Documents

### Current Bottleneck
- **Docling extraction too slow**: Python subprocess overhead + table parsing = 12+ hours for 245 PDFs on laptop
- **Root causes**:
  - Each PDF spawns new Python process via `system2()` (lines 121-135 in R/pull_functions.R)
  - File I/O: temp PDF → temp JSON → parse (lines 83-108)
  - Table structure parsing enabled by default (line 45 in python/docling_extract.py)

### Three Models Required (from proposal.qmd)
1. **Model A (Act Detection)**: Identify passages containing fiscal acts vs. general economic commentary
2. **Model B (Motivation Classification)**: 4-way classification (Spending-driven, Countercyclical, Deficit-driven, Long-run) + exogenous flag
3. **Model C (Information Extraction)**: Extract quarters and magnitudes (billions USD) from narrative + tables

---

## Implementation Plan

### **Days 1-2: Cloud PDF Extraction**

#### Objective
Replace slow laptop-based Docling with parallel cloud processing

#### Solution: AWS Lambda + S3

**Architecture:**
```
245 PDF URLs → Trigger Lambda functions (parallel) → Docling extraction → S3 JSON outputs → R reads results
```

**Key Files to Create:**
- `python/lambda_handler.py`: AWS Lambda entry point
- `lambda_deploy.sh`: Deployment script (zip Docling + dependencies → upload to AWS)
- `R/pull_text_lambda.R`: R wrapper to trigger Lambda + poll S3 results

**Lambda Configuration:**
- **Runtime**: Python 3.11
- **Memory**: 3GB (Docling needs ~2GB for PyTorch CPU)
- **Timeout**: 5 minutes per PDF (most complete <2 min)
- **Concurrency**: 245 (one per PDF)
- **Trigger**: Direct invocation via `boto3` (paws R package)

**Implementation Steps:**
1. Package Docling + dependencies in Lambda Layer (~2GB zip)
2. Write Lambda handler that:
   - Downloads PDF from URL
   - Calls `_extract_pages_with_docling()` (reuse existing python/docling_extract.py logic)
   - Uploads JSON to S3 bucket `s3://fiscal-shocks-pdfs/extracted/{year}/{source}/{filename}.json`
3. R function `pull_text_lambda()`:
   - Invokes Lambda async for all 245 PDFs
   - Polls S3 every 30 seconds until all JSONs appear
   - Parses JSON into same tibble structure as `pull_text_docling()` (text, n_pages, extracted_at)

**Table Preservation:**
- Keep `do_table_structure = True` (critical for budget revenue tables)
- Structured tables stored in JSON `"tables"` key (Docling dict export format)

**Integration with Targets:**
```r
# _targets.R - Replace us_text target
tar_target(
  us_text,
  pull_text_lambda(us_urls_vector, bucket = "fiscal-shocks-pdfs"),
  pattern = map(us_urls_vector),
  iteration = "vector"
)
```

**Estimated Time:**
- Development: 6 hours
- Deployment: 2 hours
- Full extraction: 5-10 minutes (vs. 12+ hours)

**Cost:** ~$0.50 (245 invocations × 2 min × $0.0000166667/GB-second × 3GB)

---

### **Days 2-3: Training Data Preparation**

#### Objective
Align us_labels.csv passages with us_shocks.csv labels; create train/val/test splits

#### Challenges
- **Many-to-one mapping**: Some acts have 1 passage, others have 10 (median ~3)
- **Fuzzy matching needed**: Act names vary ("Tax Reform Act of 1986" vs "Tax Reform Act 1986")
- **Negative examples needed**: Model A requires non-act passages for binary classification

#### Key Files to Create
- `R/prepare_training_data.R`: Alignment + splitting functions
- `data/processed/training_splits.rds`: Cached train/val/test data

#### Functions to Implement

**1. `align_labels_shocks(us_labels, us_shocks)`**
- Fuzzy join by act_name using `stringdist::stringsim()` (threshold 0.9)
- Group us_labels by act_name, concatenate text passages (preserve Text id for provenance)
- Left join with us_shocks to get motivation labels
- Output: tibble with columns: `act_name`, `passages_text`, `motivation_category`, `exogenous_flag`, `change_quarters`, `magnitude_billions`, `reasoning`

**2. `create_train_val_test_splits(aligned_data, ratios = c(0.6, 0.2, 0.2))`**
- **Model A**: 76 train / 25 val / 25 test acts
- **Model B**: Stratified split by motivation category (ensure balanced classes)
  - Spending-driven: 25/8/8
  - Countercyclical: 17/6/6
  - Deficit-driven: 17/6/5
  - Long-run: 17/5/6
- **Model C**: Only acts with complete timing + magnitude (80/23/23)
- Set seed for reproducibility: `set.seed(20251206)`

**3. `generate_negative_examples(relevant_paragraphs, n = 200)`**
- Sample paragraphs from `tar_read(relevant_paragraphs)` that do NOT contain act names
- Detection heuristic: `!str_detect(paragraph, regex("\\b(act|bill|law|amendment)\\s+(of\\s+)?\\d{4}\\b", ignore_case = TRUE))`
- Use as negative class for Model A (binary: is_fiscal_act = 0)

#### Output Data Structure
```r
# training_data_a.rds
tibble(
  text = "The Revenue Act of 1964 reduced marginal rates...",
  is_fiscal_act = 1,  # or 0 for negatives
  act_name = "Revenue Act of 1964",  # NA for negatives
  split = "train"  # or "val", "test"
)

# training_data_b.rds
tibble(
  act_name = "Revenue Act of 1964",
  passages_text = "Passage 1...\n\nPassage 2...",  # concatenated
  motivation = "Long-run",
  exogenous = TRUE,
  split = "train"
)

# training_data_c.rds
tibble(
  act_name = "Revenue Act of 1964",
  passages_text = "...",
  change_quarter = "1964-02",
  magnitude_billions = -8.4,
  present_value_quarter = "1964-01",
  present_value_billions = -12.72,
  split = "train"
)
```

---

### **Days 3-4: Model A - Act Detection**

#### Objective
Binary classifier: Does this passage describe a specific fiscal act?

#### Approach
Few-shot prompting with Claude 3.5 Sonnet (API)

#### Key Files to Create
- `R/functions_llm.R`: Shared LLM utilities (API calls, retry logic, JSON parsing)
- `R/model_a_detect_acts.R`: Act detection logic
- `prompts/model_a_system.txt`: System prompt with criteria
- `prompts/model_a_examples.json`: Few-shot examples

#### System Prompt Design

Store in `prompts/model_a_system.txt`:
```
You are an expert economic historian identifying fiscal policy acts from government documents.

TASK: Determine if the given passage describes a specific fiscal act (tax or spending legislation).

CRITERIA FOR FISCAL ACT (must meet ALL):
1. Names specific legislation (e.g., "Revenue Act of 1948", "Tax Reform Act of 1986")
2. Describes actual policy change (not proposals or general commentary)
3. Involves federal taxes or spending (not state/local)

NOT FISCAL ACTS:
- Economic forecasts or analysis
- General policy discussions without specific legislation
- Mentions of existing policy (without changes)

OUTPUT FORMAT (JSON):
{
  "contains_act": true/false,
  "act_name": "Official name" or null,
  "confidence": 0.0-1.0,
  "reasoning": "Brief explanation"
}
```

#### Few-Shot Examples

Store 20 examples in `prompts/model_a_examples.json`:
- **10 positive**: Clear act mentions (e.g., "The Economic Recovery Tax Act of 1981...")
- **10 negative**: Economic commentary (e.g., "The economy is growing but unemployment remains high...")

Source positive examples from us_labels.csv; source negative examples from relevant_paragraphs

#### R Implementation: `model_a_detect_acts()`

```r
model_a_detect_acts <- function(text, model = "claude-3-5-sonnet-20241022") {
  # Load system prompt + few-shot examples
  system_prompt <- readLines("prompts/model_a_system.txt") |> paste(collapse = "\n")
  examples <- jsonlite::fromJSON("prompts/model_a_examples.json")

  # Format full prompt
  full_prompt <- format_few_shot_prompt(
    system = system_prompt,
    examples = examples,
    user_input = text
  )

  # Call Claude API with retry logic
  response <- call_claude_api(
    messages = list(list(role = "user", content = full_prompt)),
    model = model,
    max_tokens = 500,
    temperature = 0.0  # Deterministic for classification
  )

  # Parse JSON response
  parse_json_response(response$content[[1]]$text)
}
```

#### Shared LLM Utilities: `R/functions_llm.R`

**1. `call_claude_api()` - Core API wrapper**
- Uses `httr2` package for HTTP requests
- Reads API key from `.env` file: `ANTHROPIC_API_KEY=sk-ant-...`
- Implements exponential backoff retry (3 attempts)
- Handles rate limits (50 RPM for Tier 1)
- Error logging to `logs/api_errors.log`

**2. `format_few_shot_prompt()` - Prompt builder**
- Concatenates system prompt + few-shot examples + user input
- Example format:
  ```
  [System prompt]

  Example 1:
  Input: "..."
  Output: {...}

  Example 2:
  ...

  Now analyze this passage:
  Input: "[user text]"
  Output:
  ```

**3. `parse_json_response()` - Robust JSON extraction**
- Extracts JSON from markdown code blocks (```json...```)
- Validates required fields (contains_act, act_name, confidence, reasoning)
- Returns tibble row

#### Evaluation Metrics

Run on validation set (25 acts + 40 negatives):
- **Precision**: TP / (TP + FP) - target > 0.80
- **Recall**: TP / (TP + FN) - target > 0.90 (don't miss real acts)
- **F1 Score**: target > 0.85
- **Confidence calibration**: Plot confidence vs. accuracy

If metrics below target → add more few-shot examples or switch to GPT-4o

#### Integration with Targets

```r
tar_target(
  model_a_predictions,
  training_data_a |>
    mutate(prediction = map(text, model_a_detect_acts)),
  packages = c("tidyverse", "httr2", "jsonlite")
)

tar_target(
  model_a_evaluation,
  evaluate_binary_classifier(
    true_labels = model_a_predictions$is_fiscal_act,
    pred_probs = map_dbl(model_a_predictions$prediction, "confidence"),
    threshold = 0.5
  )
)
```

**Estimated Cost:** ~$0.73 (101 passages × 1000 tokens × 2 × $0.003/1K + 500 output tokens × $0.015/1K)

---

### **Days 4-6: Model B - Motivation Classification**

#### Objective
Classify fiscal acts into 4 motivation categories + exogenous flag

#### Key Files to Create
- `R/model_b_classify_motivation.R`
- `prompts/model_b_system.txt`: Classification criteria (Romer & Romer framework)
- `prompts/model_b_examples.json`: 20 few-shot examples (5 per class)

#### System Prompt: Embed Romer & Romer Criteria

Store in `prompts/model_b_system.txt`:
```
You are classifying US fiscal acts by their PRIMARY motivation using the Romer & Romer (2010) framework.

MOTIVATION CATEGORIES:

1. SPENDING-DRIVEN (Endogenous)
   - Tax change enacted to finance concurrent or planned spending increase
   - Timing: Tax and spending changes occur within 2 quarters
   - Evidence: "to pay for [program]", "finance the defense effort", "accompany spending increases"
   - Example: Korean War tax increases (1950-51)

2. COUNTERCYCLICAL (Endogenous)
   - Tax change to offset current recession OR prevent overheating
   - Timing: Motivated by contemporaneous output gap or inflation
   - Evidence: "stimulate recovery", "prevent overheating", "restore full employment", "cool demand"
   - Example: Tax Reduction Act of 1975 (recession response)

3. DEFICIT-DRIVEN (Exogenous)
   - Tax change to restore fiscal balance or system solvency
   - Timing: Enacted during normal growth (not recession)
   - Evidence: "restore solvency", "reduce deficit", "fiscal sustainability", "trust fund depletion"
   - Example: Social Security Amendments of 1977

4. LONG-RUN (Exogenous)
   - Tax reform for efficiency, fairness, or long-term growth
   - NOT motivated by current cycle position
   - Evidence: "simplify tax code", "improve efficiency", "raise potential GDP", "fairness", "structural reform"
   - Example: Tax Reform Act of 1986

EXOGENOUS vs ENDOGENOUS:
- Exogenous: NOT responding to current cycle (categories 3, 4)
- Endogenous: Responding to current cycle (categories 1, 2)
- Exception: Delayed tax changes (>4 quarters) may be exogenous even if initially spending-driven

OUTPUT FORMAT (JSON):
{
  "motivation": "Long-run" | "Spending-driven" | "Countercyclical" | "Deficit-driven",
  "exogenous": true/false,
  "confidence": 0.0-1.0,
  "evidence": [
    {"passage_excerpt": "quote from text", "supports": "motivation category"}
  ],
  "reasoning": "2-3 sentence justification citing specific language"
}
```

#### Few-Shot Examples

Source from us_shocks.csv reasoning field + us_labels.csv text. Select diverse examples:
- **Spending-driven**: Revenue Act of 1950 (Korean War), Social Security Amendments of 1965 (Medicare)
- **Countercyclical**: Tax Reduction Act of 1975 (recession), Revenue and Expenditure Control Act of 1968 (overheating)
- **Deficit-driven**: Social Security Amendments of 1977 (trust fund solvency), OBRA 1990 (deficit reduction)
- **Long-run**: Tax Reform Act of 1986 (efficiency), Revenue Act of 1964 (growth)
- **Borderline cases**: Include 2-3 ambiguous examples with explicit reasoning

#### Class Distribution (from us_shocks.csv)
- Spending-driven: 41 acts
- Countercyclical: 29 acts
- Deficit-driven: 28 acts
- Long-run: 28 acts

Relatively balanced → stratified sampling sufficient (no need for class weights)

#### R Implementation: `model_b_classify_motivation()`

```r
model_b_classify_motivation <- function(act_name, passages_text, year, model = "claude-3-5-sonnet-20241022") {
  # Load system prompt + examples
  system_prompt <- readLines("prompts/model_b_system.txt") |> paste(collapse = "\n")
  examples <- jsonlite::fromJSON("prompts/model_b_examples.json")

  # Format input with act name, year context, and passages
  user_input <- glue::glue("
    ACT: {act_name}
    YEAR: {year}

    PASSAGES FROM ORIGINAL SOURCES:
    {passages_text}

    Classify this act's PRIMARY motivation.
  ")

  full_prompt <- format_few_shot_prompt(system_prompt, examples, user_input)

  response <- call_claude_api(
    messages = list(list(role = "user", content = full_prompt)),
    model = model,
    max_tokens = 1000,  # Longer for reasoning
    temperature = 0.0
  )

  parse_json_response(response$content[[1]]$text)
}
```

**Why Claude 3.5 Sonnet:**
- **200K context window**: Handles 5-10 concatenated passages per act (avg ~5K tokens)
- **Superior reasoning**: Better at borderline cases (e.g., Tax Reform Act of 1969 - mixed motivations)
- **JSON mode**: Native structured outputs

#### Evaluation Metrics

Compute on validation set (18 acts stratified by class):
- **Macro-averaged accuracy**: target > 0.75
- **Per-class F1**: target > 0.70 for each category
- **Confusion matrix**: Identify common misclassifications
  - Expected errors: Countercyclical ↔ Spending-driven (both endogenous)
  - Acceptable: Minor errors on borderline cases
  - Unacceptable: Long-run ↔ Countercyclical (opposite cycle motivations)
- **Exogenous flag accuracy**: target > 0.85 (critical for downstream multiplier estimation)

**Error Analysis:**
- Flag low confidence predictions (<0.7) for manual review
- Check if errors correlate with number of passages (1 passage vs. 10)

#### Integration with Targets

```r
tar_target(
  model_b_predictions,
  training_data_b |>
    mutate(
      prediction = pmap(
        list(act_name, passages_text, year),
        model_b_classify_motivation
      )
    )
)

tar_target(
  model_b_evaluation,
  evaluate_multiclass_classifier(
    true_labels = model_b_predictions$motivation,
    predictions = map_chr(model_b_predictions$prediction, "motivation"),
    classes = c("Spending-driven", "Countercyclical", "Deficit-driven", "Long-run")
  )
)
```

**Estimated Cost:** ~$4.54 (126 acts × 5K tokens avg × $0.003/1K input + 1K output × $0.015/1K)

---

### **Days 6-7: Model C - Information Extraction**

#### Objective
Extract timing (quarters) and magnitude (billions USD) from narrative text + budget tables

#### Key Files to Create
- `R/model_c_extract_info.R`
- `prompts/model_c_system.txt`: Extraction rules + table interpretation guidelines

#### Challenges
- **Multiple quarters**: Some acts phase in over years (e.g., ERTA 1981: 1981Q3, 1982Q1, 1983Q1, 1984Q1)
- **Table extraction**: Revenue effects often in budget tables, not narrative text
- **Units**: Millions vs. billions, fiscal year vs. calendar quarter
- **Signs**: Tax increases = positive, tax cuts = negative (Romer & Romer convention)
- **Retroactive dates**: "Effective January 1, 1975 but signed March 1975" → timing = 1975-01

#### System Prompt Design

Store in `prompts/model_c_system.txt`:
```
You are extracting fiscal shock timing and magnitude from government documents.

TASK: Identify when tax changes take effect and their revenue impact in billions of USD.

TIMING RULES:
1. Use EFFECTIVE date, not signing date
   - "Effective January 1, 1975" → 1975-01
   - "Beginning fiscal year 1982" → 1981-10 (FY starts Oct 1)
2. Format: YYYY-MM (e.g., 1964-02 for February 1964)
3. Multiple phases: List all distinct implementation quarters
4. Quarter ambiguity: Q1 = -01, Q2 = -04, Q3 = -07, Q4 = -10

MAGNITUDE RULES:
1. Sign convention:
   - Tax INCREASE = POSITIVE (e.g., +10.5 billion)
   - Tax CUT = NEGATIVE (e.g., -8.4 billion)
2. Units: Convert to billions
   - "5.0 billion" → 5.0
   - "500 million" → 0.5
3. Prefer budget tables over narrative estimates
4. If phased: Report INCREMENTAL change per quarter (not cumulative)
5. Present value: Long-run fiscal impact discounted to baseline quarter

TABLE INTERPRETATION:
- Look for "Revenue Effects of Legislation" sections
- Column headers: Fiscal Year, Calendar Year, Change in Receipts
- Rows by tax type: Individual income, Corporate, Payroll, Excise

OUTPUT FORMAT (JSON):
{
  "changes": [
    {
      "timing_quarter": "1964-02",
      "magnitude_billions": -8.4,
      "present_value_quarter": "1964-01",
      "present_value_billions": -12.72,
      "confidence": 0.0-1.0,
      "source": "Budget 1965, Table 3, p. 45" or "ERP 1965, p. 12 narrative"
    }
  ],
  "reasoning": "Explanation of how values were extracted"
}
```

#### Enhanced Input: Include Table Screenshots

For acts with critical table data (e.g., ERTA 1981, OBRA 1993), use Claude's vision API:
- Extract table pages from Docling output (tables list-column)
- Convert to images or include Docling's structured table JSON
- Pass as additional context: `"Here is Table 3 showing revenue effects: [table data]"`

#### R Implementation: `model_c_extract_info()`

```r
model_c_extract_info <- function(act_name, passages_text, date_signed, tables = NULL) {
  system_prompt <- readLines("prompts/model_c_system.txt") |> paste(collapse = "\n")

  # Build context with act metadata
  user_input <- glue::glue("
    ACT: {act_name}
    DATE SIGNED: {date_signed}

    PASSAGES:
    {passages_text}
  ")

  # Append table data if available
  if (!is.null(tables) && length(tables) > 0) {
    table_text <- tables |>
      map_chr(~ jsonlite::toJSON(.x, auto_unbox = TRUE)) |>
      paste(collapse = "\n\n")
    user_input <- paste0(user_input, "\n\nTABLES:\n", table_text)
  }

  full_prompt <- format_few_shot_prompt(system_prompt, examples = NULL, user_input)

  response <- call_claude_api(
    messages = list(list(role = "user", content = full_prompt)),
    model = "claude-3-5-sonnet-20241022",
    max_tokens = 1500,
    temperature = 0.0
  )

  parse_json_response(response$content[[1]]$text)
}
```

#### Evaluation Metrics

- **Timing accuracy**:
  - Exact quarter match: target > 60%
  - ±1 quarter tolerance: target > 85%
  - Median absolute error: < 1 quarter
- **Magnitude accuracy**:
  - Mean Absolute Percentage Error (MAPE): target < 30%
  - Sign accuracy: > 95% (critical!)
  - Correlation with true values: r > 0.90
- **Present value extraction**: Same metrics as magnitude

**Error Analysis:**
- Check if errors correlate with:
  - Multi-quarter acts (harder to extract all phases)
  - Acts with only narrative estimates (no tables)
  - Very small magnitudes (<$1B)

#### Integration with Targets

```r
tar_target(
  model_c_predictions,
  training_data_c |>
    mutate(
      prediction = pmap(
        list(act_name, passages_text, date_signed, tables),
        model_c_extract_info
      )
    )
)

tar_target(
  model_c_evaluation,
  evaluate_info_extraction(
    true_timing = model_c_predictions$change_quarter,
    pred_timing = map_chr(model_c_predictions$prediction, c("changes", 1, "timing_quarter")),
    true_magnitude = model_c_predictions$magnitude_billions,
    pred_magnitude = map_dbl(model_c_predictions$prediction, c("changes", 1, "magnitude_billions"))
  )
)
```

**Estimated Cost:** ~$6.18 (126 acts × 6K tokens avg with tables × $0.003/1K + 1.5K output × $0.015/1K)

---

### **Day 8: Pipeline Integration**

#### Objective
Integrate all models into end-to-end targets pipeline

#### New Targets to Add (in `_targets.R`)

```r
# Training data preparation
tar_target(aligned_data, align_labels_shocks(us_labels, us_shocks)),
tar_target(training_data_a, prepare_model_a_data(aligned_data, relevant_paragraphs)),
tar_target(training_data_b, prepare_model_b_data(aligned_data)),
tar_target(training_data_c, prepare_model_c_data(aligned_data)),

# Model A: Act Detection
tar_target(model_a_predictions, run_model_a(training_data_a)),
tar_target(model_a_eval, evaluate_model_a(model_a_predictions)),

# Model B: Motivation Classification
tar_target(model_b_predictions, run_model_b(training_data_b)),
tar_target(model_b_eval, evaluate_model_b(model_b_predictions)),

# Model C: Information Extraction
tar_target(model_c_predictions, run_model_c(training_data_c)),
tar_target(model_c_eval, evaluate_model_c(model_c_predictions)),

# Aggregate predictions into shock dataset
tar_target(
  shocks_llm,
  combine_predictions(model_b_predictions, model_c_predictions)
)
```

#### API Key Management

Create `.env` file (gitignored):
```
ANTHROPIC_API_KEY=sk-ant-api03-xxx...
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=xxx...
AWS_DEFAULT_REGION=us-east-1
```

Load in R with `dotenv::load_dot_env()` at start of `_targets.R`

#### Rate Limiting

Claude API Tier 1: 50 requests/minute
- Total API calls: ~126 acts × 3 models = 378 calls
- With 50 RPM limit: ~8 minutes minimum
- Implement in `call_claude_api()`:
  ```r
  Sys.sleep(1.2)  # 60s / 50 requests = 1.2s between calls
  ```

#### Error Handling & Retry Logic

In `R/functions_llm.R`:
```r
call_claude_api <- function(..., max_retries = 3) {
  for (attempt in seq_len(max_retries)) {
    tryCatch({
      response <- httr2::request("https://api.anthropic.com/v1/messages") |>
        httr2::req_headers(
          "x-api-key" = Sys.getenv("ANTHROPIC_API_KEY"),
          "anthropic-version" = "2023-06-01",
          "content-type" = "application/json"
        ) |>
        httr2::req_body_json(...) |>
        httr2::req_perform()

      return(httr2::resp_body_json(response))

    }, error = function(e) {
      if (attempt == max_retries) stop("API call failed after ", max_retries, " attempts: ", e$message)

      wait_time <- 2^attempt  # Exponential backoff: 2s, 4s, 8s
      message("API error (attempt ", attempt, "/", max_retries, "), retrying in ", wait_time, "s...")
      Sys.sleep(wait_time)
    })
  }
}
```

#### Logging

All API calls logged to `logs/api_calls.csv`:
```r
log_api_call <- function(model, input_tokens, output_tokens, cost, timestamp) {
  log_entry <- tibble(
    timestamp = timestamp,
    model = model,
    input_tokens = input_tokens,
    output_tokens = output_tokens,
    cost_usd = cost
  )

  # Append to CSV
  write_csv(log_entry, "logs/api_calls.csv", append = file.exists("logs/api_calls.csv"))
}
```

---

### **Day 9: Model Evaluation & Error Analysis**

#### Objective
Comprehensive evaluation of all three models against ground truth labels

#### Key Files to Create
- `R/evaluate_models.R`: Unified evaluation functions
- `notebooks/phase0_evaluation.qmd`: Full validation report with plots

#### Model A Evaluation

**Metrics:**
- **Precision**: TP / (TP + FP) - target > 0.80
- **Recall**: TP / (TP + FN) - target > 0.90
- **F1 Score**: target > 0.85
- **Confidence calibration**: Plot predicted probability vs. actual accuracy

**Analysis:**
- Which acts were missed (false negatives)?
- Which paragraphs were incorrectly flagged (false positives)?
- Does performance vary by document source (ERP vs Budget vs Treasury)?

#### Model B Evaluation

**Metrics:**
- **Overall accuracy**: target > 0.75
- **Per-class F1 scores**: target > 0.70 for each category
- **Confusion matrix**: Identify systematic misclassification patterns
- **Exogenous flag accuracy**: target > 0.85

**Analysis:**
- Common confusions: Spending-driven ↔ Countercyclical (both endogenous)?
- Do errors cluster by time period (e.g., pre-1960 worse)?
- Correlation between confidence scores and accuracy

#### Model C Evaluation

**Timing Metrics:**
- **Exact quarter match**: target > 60%
- **±1 quarter tolerance**: target > 85%
- **Median absolute error**: < 1 quarter

**Magnitude Metrics:**
- **Mean Absolute Percentage Error (MAPE)**: target < 30%
- **Sign accuracy**: > 95%
- **Correlation with true values**: r > 0.90
- **Scatter plot**: LLM predicted vs. true magnitudes

**Analysis:**
- Which acts have largest errors?
- Do multi-quarter acts have higher error rates?
- Are errors correlated with table availability?

#### Diagnostic Visualizations

```r
# 1. Confusion matrix (Model B)
plot_confusion_matrix <- function(true, pred) {
  conf_mat <- table(True = true, Predicted = pred)
  conf_df <- as.data.frame(conf_mat)

  ggplot(conf_df, aes(x = Predicted, y = True, fill = Freq)) +
    geom_tile(color = "white") +
    geom_text(aes(label = Freq), color = "white", size = 6) +
    scale_fill_gradient(low = "steelblue", high = "coral") +
    labs(title = "Model B: Motivation Classification Confusion Matrix") +
    theme_minimal()
}

# 2. Magnitude scatter (Model C)
plot_magnitude_comparison <- function(true, pred) {
  tibble(true = true, pred = pred) |>
    ggplot(aes(x = true, y = pred)) +
    geom_point(alpha = 0.6, size = 3) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "coral") +
    labs(
      title = "Model C: Magnitude Prediction vs. True Values",
      x = "True magnitude (billions USD)",
      y = "Predicted magnitude (billions USD)",
      caption = "Dashed line = perfect prediction"
    ) +
    theme_minimal()
}

# 3. Timing error distribution (Model C)
plot_timing_errors <- function(true_quarters, pred_quarters) {
  tibble(
    error_quarters = interval(true_quarters, pred_quarters) / months(3)
  ) |>
    ggplot(aes(x = error_quarters)) +
    geom_histogram(binwidth = 1, fill = "steelblue", alpha = 0.7) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "coral") +
    labs(
      title = "Model C: Timing Prediction Errors",
      x = "Error (quarters, negative = too early)",
      y = "Count"
    ) +
    theme_minimal()
}
```

#### Evaluation Report Structure: `notebooks/phase0_evaluation.qmd`

**Section 1: Executive Summary**
- Overall pass/fail against success criteria
- Key findings (1 paragraph per model)
- Recommended next steps

**Section 2: Model A (Act Detection)**
- Precision/Recall/F1 table
- False negative examples (missed acts)
- False positive examples (incorrectly flagged paragraphs)
- Performance by document source

**Section 3: Model B (Motivation Classification)**
- Confusion matrix visualization
- Per-class F1 scores table
- Error analysis: Which specific acts were misclassified?
- Confidence score distribution by correctness

**Section 4: Model C (Information Extraction)**
- Magnitude scatter plot
- Timing error histogram
- MAPE and correlation statistics
- Worst 10 predictions with explanations

**Section 5: Overall Assessment**
- Combined dataset: `shocks_llm.csv` vs. `us_shocks.csv` comparison
- Recovery rate: How many of 126 acts successfully extracted?
- Error patterns: Do errors cluster (e.g., pre-1960, small magnitude acts)?

**Section 6: Recommendations**
- If all models pass: Green light for Phase 1 (Malaysia)
- If models fail: Which model needs improvement? Specific fixes?

---

### **Day 10: Documentation & Wrap-Up**

#### Deliverables

**1. Technical Report** (`docs/phase0_report.qmd`)
- Executive summary (1 page)
- Methodology (3 pages): PDF extraction, model architectures, evaluation
- Results (5 pages): Performance metrics, IRF comparison, error analysis
- Appendices: Full prompts, few-shot examples, API call logs
- Render to PDF and HTML

**2. Reproducible Code**
- All functions documented with roxygen2
- Targets pipeline runs end-to-end: `tar_make()`
- Docker image rebuilds successfully
- README with setup instructions

**3. Data Artifacts**
- Cache training splits (avoid re-running API): `data/processed/training_splits.rds`
- Save all model predictions: `data/processed/model_{a,b,c}_predictions.rds`
- Final LLM shock dataset: `data/processed/shocks_llm.csv`

**4. Cost Analysis** (`docs/cost_breakdown.xlsx`)

| Component | Estimated | Actual |
|-----------|-----------|--------|
| AWS Lambda (245 PDFs) | $0.50 | - |
| S3 storage (1 month) | $0.10 | - |
| Model A API | $0.73 | - |
| Model B API | $4.54 | - |
| Model C API | $6.18 | - |
| Iteration/debugging | $20.00 | - |
| **Total** | **~$32** | - |

#### GitHub Repository Structure

```
Fiscal-shocks/
├── _targets.R
├── renv.lock
├── .env.example  # Template for API keys
├── R/
│   ├── pull_text_lambda.R
│   ├── prepare_training_data.R
│   ├── functions_llm.R
│   ├── model_a_detect_acts.R
│   ├── model_b_classify_motivation.R
│   ├── model_c_extract_info.R
│   ├── estimate_multipliers.R
│   └── fetch_fred_data.R
├── python/
│   ├── docling_extract.py
│   └── lambda_handler.py
├── prompts/
│   ├── model_a_system.txt
│   ├── model_a_examples.json
│   ├── model_b_system.txt
│   ├── model_b_examples.json
│   ├── model_c_system.txt
│   └── model_c_examples.json
├── notebooks/
│   ├── phase0_evaluation.qmd
│   └── explore_predictions.qmd
├── docs/
│   ├── phase0_report.qmd
│   └── cost_breakdown.xlsx
├── data/
│   ├── raw/
│   │   ├── us_shocks.csv
│   │   └── us_labels.csv
│   └── processed/
│       ├── training_splits.rds
│       ├── model_a_predictions.rds
│       ├── model_b_predictions.rds
│       ├── model_c_predictions.rds
│       └── shocks_llm.csv
└── logs/
    ├── api_calls.csv
    └── api_errors.log
```

---

## Timeline Summary

| Days | Phase | Key Deliverables |
|------|-------|------------------|
| 1-2 | Cloud PDF Extraction | Lambda deployed, 245 PDFs extracted in <10 min |
| 2-3 | Training Data Prep | aligned_data.rds, train/val/test splits cached |
| 3-4 | Model A (Act Detection) | F1 > 0.85, prompts finalized |
| 4-6 | Model B (Motivation) | Accuracy > 0.75, confusion matrix analyzed |
| 6-7 | Model C (Info Extraction) | MAPE < 30%, timing within ±1 quarter |
| 8 | Pipeline Integration | End-to-end targets pipeline functional |
| 9 | **Model Evaluation** | **All success criteria met** ✅ |
| 10 | Documentation | Technical report, cost analysis, GitHub cleanup |

**Critical Path:** Day 9 (model evaluation) determines project success.

---

## Success Criteria Checklist

### Model Performance (PRIMARY SUCCESS CRITERIA)
- [ ] **Model A (Act Detection)**: F1 > 0.85 on test set
- [ ] **Model B (Motivation)**: Accuracy > 0.75, all classes F1 > 0.70 on test set
- [ ] **Model C (Information Extraction)**:
  - [ ] Magnitude MAPE < 30%
  - [ ] Sign accuracy > 95%
  - [ ] Timing: ±1 quarter tolerance > 85%

### Operational
- [ ] PDF extraction < 15 minutes for 245 documents
- [ ] End-to-end pipeline runtime < 6 hours
- [ ] Total cost < $50

---

## Risk Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Lambda timeout (>15 min) | Low | Medium | Test on 10 PDFs first; fallback to AWS Batch |
| Model B accuracy < 0.75 | Medium | High | Add 10 more few-shot examples; try GPT-4o backup |
| Tables not extracted properly | Medium | High | Use Vision API for critical PDFs; manual for top 10 |
| Model C magnitude errors high | Medium | High | Focus prompts on table extraction; add more examples |
| API costs exceed $50 | Low | Low | Monitor daily; validate on small subset first |
| Rate limits hit (50 RPM) | Low | Low | Already accounted for with `Sys.sleep(1.2)` |

---

## Critical Files to Implement

### High Priority (Days 1-7)
1. `python/lambda_handler.py` - Cloud extraction (solves speed bottleneck)
2. `R/pull_text_lambda.R` - R wrapper for Lambda
3. `R/prepare_training_data.R` - Alignment logic (foundation for all models)
4. `R/functions_llm.R` - Shared API utilities (used by all 3 models)
5. `R/model_a_detect_acts.R` - Act detection
6. `R/model_b_classify_motivation.R` - Motivation classification
7. `R/model_c_extract_info.R` - Information extraction
8. `prompts/*.txt` - System prompts for all 3 models

### Medium Priority (Days 8-9)
9. `R/evaluate_models.R` - Unified evaluation functions
10. `notebooks/phase0_evaluation.qmd` - Evaluation report with plots

### Lower Priority (Day 10)
11. `docs/phase0_report.qmd` - Technical documentation
12. Lambda deployment scripts (`lambda_deploy.sh`)

---

## Verification Plan

After completing implementation:

1. **End-to-End Test**
   ```r
   # Clean slate
   tar_destroy()

   # Run full pipeline
   tar_make()

   # Check critical outputs
   tar_read(model_a_eval)  # Should show F1 > 0.85
   tar_read(model_b_eval)  # Should show accuracy > 0.75
   tar_read(model_c_eval)  # Should show MAPE < 30%, timing ±1 quarter > 85%
   ```

2. **Generate Evaluation Report**
   ```r
   quarto::quarto_render("notebooks/phase0_evaluation.qmd")
   # Review: confusion matrices, error distributions, scatter plots
   ```

3. **Cost Verification**
   ```r
   total_cost <- read_csv("logs/api_calls.csv") |>
     summarise(total = sum(cost_usd))
   # Should be < $40
   ```

4. **Spot Check Predictions**
   ```r
   # Manually review 5 random acts per model
   model_b_predictions |>
     slice_sample(n = 5) |>
     select(act_name, true_motivation = motivation, predicted = prediction) |>
     View()
   # Do classifications make intuitive sense?
   ```

5. **Compare Final Dataset**
   ```r
   # Load LLM-generated shocks
   shocks_llm <- tar_read(shocks_llm)

   # Compare with ground truth
   comparison <- us_shocks |>
     left_join(shocks_llm, by = "act_name", suffix = c("_true", "_llm"))

   # How many acts successfully extracted?
   coverage <- sum(!is.na(comparison$motivation_llm)) / nrow(us_shocks)
   print(paste0("Coverage: ", scales::percent(coverage)))  # Target > 90%
   ```

---

## Next Steps After Phase 0

**If successful** (all model criteria met):
- **Phase 1 (Malaysia)**: Adapt pipeline to Malaysian documents
- **Fine-tuning**: Train Mistral 7B on US examples for local deployment
- **Scale**: Process 5 SEA countries in parallel
- **Optional**: Run fiscal multiplier regressions to validate economic consistency

**If failed** (models below threshold):
- **Root cause analysis**: Which model(s) underperformed?
- **Pivot options**:
  - Add more few-shot examples (if close to threshold)
  - Fine-tune instead of few-shot (if accuracy way below)
  - Hybrid: Human + LLM workflow (LLM proposes, human reviews borderline cases)
  - Focus on subset: Modern era only (1980-present, better PDF quality)

---

**END OF PLAN**
