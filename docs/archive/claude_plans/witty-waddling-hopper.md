# Phase 0 Implementation Plan: US Fiscal Shock Benchmarking

## Overview

Complete the US fiscal shock identification pipeline by adding model training (Stage 7), prediction (Stage 8), and validation (Stage 9) to reproduce Romer & Romer's narrative approach using LLMs. Focus on end-to-end pipeline infrastructure with full reproducibility.

## Current Status

**✅ COMPLETE (Stages 1-6):**
- Data acquisition: URLs for ERP, Budget, Treasury reports (1946-present)
- PDF text extraction: Docling + pdftools
- Text processing: 339 labeled passages, 125 fiscal shocks
- Training data preparation: 3 classification tasks with train/val/test splits
- Python training/prediction scripts
- R wrapper functions

**📝 UNCOMMITTED:**
- Stage 6 targets in `_targets.R` (training_data_*, splits_*)
- Updated `requirements.txt` with transformers stack
- Fixed `clean_us_labels()` function

**❌ MISSING:**
- Model training targets
- Prediction & evaluation targets
- Romer & Romer validation
- Baseline models for comparison
- Error analysis

## Three Classification Tasks

1. **Act Detection** (binary): Identify fiscal acts in text passages
2. **Motivation Classification** (4-class): spending_driven, countercyclical, deficit_driven, long_run
3. **Exogenous Classification** (binary): Exogenous vs endogenous shocks

## Implementation Stages

### Stage 7: Model Training

**Objective:** Train classifiers with conditional execution and hyperparameter management.

#### New Functions (`R/functions_model_training.R`)

Add these functions to the existing file:

```r
#' Check if Model Exists and is Valid
model_exists <- function(model_dir) {
  required_files <- c("config.json", "pytorch_model.bin", "training_metrics.json")
  all(file.exists(file.path(model_dir, required_files)))
}

#' Get Default Model Hyperparameters by Task
get_default_hyperparams <- function(task, model_name = "distilbert-base-uncased") {
  params <- list(
    model_name = model_name,
    num_epochs = 10,
    batch_size = if (str_detect(model_name, "distil")) 32 else 16,
    learning_rate = 2e-5,
    max_length = 512,
    warmup_steps = 500,
    weight_decay = 0.01,
    early_stopping_patience = 3,
    seed = 42
  )

  # Task-specific adjustments
  if (task == "motivation") {
    params$num_epochs <- 15
    params$learning_rate <- 3e-5
  }

  return(params)
}

#' Train Model with Conditional Execution
train_model_conditional <- function(task, splits, output_dir,
                                     force_retrain = FALSE, ...) {
  if (!force_retrain && model_exists(output_dir)) {
    message(sprintf("Model exists at %s, skipping training", output_dir))
    metrics <- jsonlite::read_json(file.path(output_dir, "training_metrics.json"))
    return(list(model_path = output_dir, metrics = metrics, skipped = TRUE))
  }

  message(sprintf("Training new model for task: %s", task))
  result <- train_classifier_python(
    task = task,
    train_data = splits$train,
    val_data = splits$val,
    output_dir = output_dir,
    ...
  )

  result$skipped <- FALSE
  return(result)
}
```

#### New Targets (`_targets.R`)

Add after Stage 6 (training data preparation):

```r
# Stage 7: Model Training
tar_target(
  model_config,
  list(
    default_model = "distilbert-base-uncased",  # CPU-friendly
    # Alternatives: "microsoft/deberta-v3-base" (best CPU), "roberta-base" (GPU)
    force_retrain = FALSE,
    output_base = here::here("models")
  )
),

tar_target(
  model_act_detection,
  train_model_conditional(
    task = "act_detection",
    splits = splits_act_detection,
    output_dir = file.path(model_config$output_base, "act_detection"),
    force_retrain = model_config$force_retrain,
    model_name = model_config$default_model,
    num_epochs = 10,
    batch_size = 32,
    learning_rate = 2e-5,
    max_length = 512,
    early_stopping_patience = 3
  ),
  format = "qs"
),

tar_target(
  model_motivation,
  train_model_conditional(
    task = "motivation",
    splits = splits_motivation,
    output_dir = file.path(model_config$output_base, "motivation"),
    force_retrain = model_config$force_retrain,
    model_name = model_config$default_model,
    num_epochs = 15,
    batch_size = 32,
    learning_rate = 3e-5
  ),
  format = "qs"
),

tar_target(
  model_exogenous,
  train_model_conditional(
    task = "exogenous",
    splits = splits_exogenous,
    output_dir = file.path(model_config$output_base, "exogenous"),
    force_retrain = model_config$force_retrain,
    model_name = model_config$default_model,
    num_epochs = 10,
    batch_size = 32
  ),
  format = "qs"
)
```

### Stage 8: Prediction

**Objective:** Generate predictions on test sets and full corpus.

#### New Functions (`R/functions_model_training.R`)

```r
#' Predict with Automatic Output Path
predict_with_auto_path <- function(model_result, input_data, task,
                                    output_dir = here::here("predictions")) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  output_path <- file.path(
    output_dir,
    sprintf("%s_%s.parquet", task, format(Sys.time(), "%Y%m%d_%H%M%S"))
  )

  predict_classifier_python(
    model_path = model_result$model_path,
    input_data = input_data,
    output_path = output_path,
    batch_size = 64,
    device = "auto"
  )
}
```

#### New Targets (`_targets.R`)

```r
# Stage 8: Prediction
# Test set predictions
tar_target(
  predictions_test_act_detection,
  predict_with_auto_path(
    model_result = model_act_detection,
    input_data = splits_act_detection$test,
    task = "act_detection_test"
  ),
  format = "parquet"
),

tar_target(
  predictions_test_motivation,
  predict_with_auto_path(
    model_result = model_motivation,
    input_data = splits_motivation$test,
    task = "motivation_test"
  ),
  format = "parquet"
),

tar_target(
  predictions_test_exogenous,
  predict_with_auto_path(
    model_result = model_exogenous,
    input_data = splits_exogenous$test,
    task = "exogenous_test"
  ),
  format = "parquet"
),

# Full corpus predictions (cascading pipeline)
tar_target(
  predictions_corpus_act_detection,
  {
    corpus_data <- relevant_paragraphs %>%
      select(text = paragraph, year, source, body, pdf_url) %>%
      filter(str_length(text) > 50)

    predict_with_auto_path(
      model_result = model_act_detection,
      input_data = corpus_data,
      task = "act_detection_corpus"
    )
  },
  format = "parquet"
),

tar_target(
  predictions_corpus_motivation,
  {
    detected_acts <- predictions_corpus_act_detection %>%
      filter(pred_class == 1, pred_prob >= 0.5)

    predict_with_auto_path(
      model_result = model_motivation,
      input_data = detected_acts,
      task = "motivation_corpus"
    )
  },
  format = "parquet"
),

tar_target(
  predictions_corpus_exogenous,
  {
    motivated_acts <- predictions_corpus_motivation %>%
      mutate(
        text = paste0(text, " [SEP] ",
                     case_when(
                       pred_class == 0 ~ "spending_driven",
                       pred_class == 1 ~ "countercyclical",
                       pred_class == 2 ~ "deficit_driven",
                       pred_class == 3 ~ "long_run"
                     ))
      )

    predict_with_auto_path(
      model_result = model_exogenous,
      input_data = motivated_acts,
      task = "exogenous_corpus"
    )
  },
  format = "parquet"
)
```

### Stage 9: Evaluation and Validation

**Objective:** Validate against Romer & Romer, compute metrics, analyze errors.

#### New File: `R/functions_evaluation.R`

Create this new file with the following functions:

```r
library(dplyr)
library(tidyr)
library(yardstick)
library(ggplot2)

#' Validate Against Romer & Romer Ground Truth
validate_against_romer_romer <- function(predictions_act,
                                          predictions_motivation,
                                          predictions_exogenous,
                                          us_shocks,
                                          us_labels) {

  ground_truth_acts <- us_shocks %>%
    select(act_name, date_signed, motivation = change_in_liabilities_category,
           exogenous = change_in_liabilities_exo) %>%
    distinct(act_name, .keep_all = TRUE) %>%
    mutate(
      year = lubridate::year(date_signed),
      motivation = str_to_lower(str_replace_all(motivation, "-", "_"))
    )

  predicted_acts <- predictions_act %>%
    filter(pred_class == 1, pred_prob >= 0.5) %>%
    count(year, source, name = "n_predicted_acts")

  predicted_with_motivation <- predictions_motivation %>%
    filter(pred_prob >= 0.3) %>%
    mutate(
      pred_motivation = case_when(
        pred_class == 0 ~ "spending_driven",
        pred_class == 1 ~ "countercyclical",
        pred_class == 2 ~ "deficit_driven",
        pred_class == 3 ~ "long_run"
      )
    ) %>%
    left_join(predictions_exogenous, by = c("text", "year", "source")) %>%
    mutate(
      pred_exogenous = if_else(pred_class.y == 1, "Exogenous", "Endogenous")
    )

  comparison_by_year <- ground_truth_acts %>%
    count(year, motivation, exogenous, name = "n_ground_truth") %>%
    full_join(
      predicted_with_motivation %>%
        count(year, pred_motivation, pred_exogenous, name = "n_predicted"),
      by = c("year", "motivation" = "pred_motivation",
             "exogenous" = "pred_exogenous")
    ) %>%
    replace_na(list(n_ground_truth = 0, n_predicted = 0))

  recall <- comparison_by_year %>%
    summarize(
      total_ground_truth = sum(n_ground_truth),
      total_found = sum(pmin(n_predicted, n_ground_truth)),
      recall = total_found / total_ground_truth
    )

  return(list(
    comparison_by_year = comparison_by_year,
    recall = recall,
    ground_truth_acts = ground_truth_acts,
    predicted_acts = predicted_with_motivation
  ))
}

#' Create Baseline Keyword Model
baseline_keyword_classifier <- function(data, task = "act_detection") {

  if (task == "act_detection") {
    act_keywords <- c(
      "revenue act", "tax act", "reform act", "appropriation",
      "social security amendment", "budget act", "tariff act"
    )

    data %>%
      mutate(
        pred_class = as.integer(
          str_detect(str_to_lower(text),
                    paste(act_keywords, collapse = "|"))
        ),
        pred_prob = if_else(pred_class == 1, 0.8, 0.2),
        model = "baseline_keyword"
      )

  } else if (task == "motivation") {
    data %>%
      mutate(
        spending_score = str_count(str_to_lower(text), "spending|expenditure"),
        countercyclical_score = str_count(str_to_lower(text), "recession|unemployment|stimulus"),
        deficit_score = str_count(str_to_lower(text), "deficit|debt|fiscal"),
        long_run_score = str_count(str_to_lower(text), "growth|efficiency|reform"),

        pred_class = case_when(
          spending_score == max(c_across(ends_with("_score"))) ~ 0L,
          countercyclical_score == max(c_across(ends_with("_score"))) ~ 1L,
          deficit_score == max(c_across(ends_with("_score"))) ~ 2L,
          TRUE ~ 3L
        ),
        pred_prob = 0.5,
        model = "baseline_keyword"
      ) %>%
      select(-ends_with("_score"))
  }
}

#' Compute Per-Class Metrics
compute_per_class_metrics <- function(predictions, true_labels, task) {

  eval_df <- tibble(
    truth = factor(true_labels),
    estimate = factor(predictions$pred_class)
  )

  overall <- eval_df %>%
    yardstick::metrics(truth = truth, estimate = estimate)

  cm <- yardstick::conf_mat(eval_df, truth = truth, estimate = estimate)

  return(list(
    overall = overall,
    confusion_matrix = cm
  ))
}

#' Analyze Prediction Errors
analyze_errors <- function(predictions, true_labels, data, task) {

  errors <- data %>%
    mutate(
      pred_class = predictions$pred_class,
      pred_prob = predictions$pred_prob,
      true_label = true_labels,
      is_error = pred_class != true_label
    ) %>%
    filter(is_error)

  error_summary <- errors %>%
    count(true_label, pred_class, name = "n_errors") %>%
    arrange(desc(n_errors))

  confidence_analysis <- errors %>%
    mutate(
      confidence_bucket = cut(pred_prob,
                              breaks = c(0, 0.3, 0.5, 0.7, 0.9, 1.0),
                              labels = c("very_low", "low", "medium",
                                        "high", "very_high"))
    ) %>%
    count(confidence_bucket)

  return(list(
    errors = errors,
    error_summary = error_summary,
    confidence_analysis = confidence_analysis,
    total_errors = nrow(errors),
    error_rate = nrow(errors) / nrow(data)
  ))
}

#' Create Evaluation Report
create_evaluation_report <- function(predictions_llm,
                                      predictions_baseline,
                                      true_labels,
                                      data,
                                      task) {

  llm_metrics <- compute_per_class_metrics(predictions_llm, true_labels, task)
  baseline_metrics <- compute_per_class_metrics(predictions_baseline, true_labels, task)
  llm_errors <- analyze_errors(predictions_llm, true_labels, data, task)

  comparison_plot <- bind_rows(
    llm_metrics$overall %>% mutate(model = "LLM"),
    baseline_metrics$overall %>% mutate(model = "Baseline")
  ) %>%
    ggplot(aes(x = .metric, y = .estimate, fill = model)) +
    geom_col(position = "dodge") +
    labs(title = sprintf("Model Comparison: %s", task),
         y = "Score", x = "Metric") +
    theme_minimal()

  return(list(
    llm_metrics = llm_metrics,
    baseline_metrics = baseline_metrics,
    llm_errors = llm_errors,
    comparison_plot = comparison_plot,
    task = task
  ))
}
```

#### New Targets (`_targets.R`)

```r
# Stage 9: Evaluation and Validation

# Baseline models
tar_target(
  baseline_act_detection,
  baseline_keyword_classifier(splits_act_detection$test, task = "act_detection"),
  format = "parquet"
),

tar_target(
  baseline_motivation,
  baseline_keyword_classifier(splits_motivation$test, task = "motivation"),
  format = "parquet"
),

# Evaluation reports
tar_target(
  eval_act_detection,
  create_evaluation_report(
    predictions_llm = predictions_test_act_detection,
    predictions_baseline = baseline_act_detection,
    true_labels = splits_act_detection$test$label,
    data = splits_act_detection$test,
    task = "act_detection"
  ),
  format = "qs"
),

tar_target(
  eval_motivation,
  create_evaluation_report(
    predictions_llm = predictions_test_motivation,
    predictions_baseline = baseline_motivation,
    true_labels = splits_motivation$test$motivation,
    data = splits_motivation$test,
    task = "motivation"
  ),
  format = "qs"
),

tar_target(
  eval_exogenous,
  {
    baseline <- splits_exogenous$test %>%
      mutate(
        pred_class = as.integer(motivation %in% c("long_run", "deficit_driven")),
        pred_prob = 0.7,
        model = "baseline_rule"
      )

    create_evaluation_report(
      predictions_llm = predictions_test_exogenous,
      predictions_baseline = baseline,
      true_labels = splits_exogenous$test$exogenous,
      data = splits_exogenous$test,
      task = "exogenous"
    )
  },
  format = "qs"
),

# Romer & Romer validation
tar_target(
  validation_romer_romer,
  validate_against_romer_romer(
    predictions_act = predictions_corpus_act_detection,
    predictions_motivation = predictions_corpus_motivation,
    predictions_exogenous = predictions_corpus_exogenous,
    us_shocks = us_shocks,
    us_labels = us_labels
  ),
  format = "qs"
),

# Summary metrics
tar_target(
  metrics_summary,
  {
    bind_rows(
      eval_act_detection$llm_metrics$overall %>%
        mutate(task = "act_detection", model = "LLM"),
      eval_act_detection$baseline_metrics$overall %>%
        mutate(task = "act_detection", model = "Baseline"),
      eval_motivation$llm_metrics$overall %>%
        mutate(task = "motivation", model = "LLM"),
      eval_motivation$baseline_metrics$overall %>%
        mutate(task = "motivation", model = "Baseline"),
      eval_exogenous$llm_metrics$overall %>%
        mutate(task = "exogenous", model = "LLM"),
      eval_exogenous$baseline_metrics$overall %>%
        mutate(task = "exogenous", model = "Baseline")
    )
  },
  format = "parquet"
),

# Validation report
tar_target(
  validation_report,
  {
    rr_val <- validation_romer_romer

    list(
      act_recall = rr_val$recall,
      temporal_coverage = rr_val$comparison_by_year %>%
        summarize(
          years_with_ground_truth = n_distinct(year[n_ground_truth > 0]),
          years_with_predictions = n_distinct(year[n_predicted > 0]),
          coverage_pct = years_with_predictions / years_with_ground_truth
        ),
      motivation_accuracy = rr_val$comparison_by_year %>%
        filter(n_ground_truth > 0, n_predicted > 0) %>%
        summarize(
          correct = sum(pmin(n_predicted, n_ground_truth)),
          total = sum(n_ground_truth),
          accuracy = correct / total
        ),
      comparison_table = rr_val$comparison_by_year
    )
  },
  format = "qs"
)
```

## Model Selection Guidance

### Default: CPU-Friendly
```r
model_config = list(
  default_model = "distilbert-base-uncased"  # 66M params, 2x faster than BERT
)
```

**Expected Training Time (CPU):**
- Total: ~50-70 minutes for all 3 models
- Memory: ~4GB RAM
- **Recommended**: 8GB+ RAM

### Alternative: Best CPU Performance
```r
model_config = list(
  default_model = "microsoft/deberta-v3-base"  # State-of-the-art small model
)
```

### GPU (if available):
```r
model_config = list(
  default_model = "roberta-base"  # Better on long documents
)
```

**Expected Training Time (GPU):**
- Total: ~15-30 minutes
- VRAM: ~6-8GB

## Success Criteria

### Minimum Targets

**Model Performance (Test Set):**
- Act Detection F1: ≥ 0.70 (vs baseline ~0.50)
- Motivation F1: ≥ 0.50 (vs baseline ~0.30)
- Exogenous F1: ≥ 0.65 (vs baseline ~0.55)

**Romer & Romer Validation:**
- Act Recall: ≥ 0.60 (finding 60%+ of known acts)
- Temporal Coverage: ≥ 0.80 (predictions in 80%+ of years)
- Motivation Accuracy: ≥ 0.50 (correct for 50%+ of found acts)

**Pipeline:**
- All targets build without errors
- Training completes in <2 hours (CPU)
- All predictions generated
- Validation report completes

## Critical Files to Modify

1. **`R/functions_evaluation.R`** (NEW) - All validation and evaluation functions
2. **`_targets.R`** (MODIFY) - Add Stages 7, 8, 9 targets
3. **`R/functions_model_training.R`** (MODIFY) - Add helper functions
4. **`notebooks/phase0_results.qmd`** (NEW) - Results analysis notebook
5. **`tests/test_phase0.R`** (NEW) - Test suite

## Verification Steps

### After Implementation

```r
# 1. Run full pipeline
targets::tar_make()

# 2. Check training results
targets::tar_read(model_act_detection)
targets::tar_read(model_motivation)
targets::tar_read(model_exogenous)

# 3. View metrics summary
targets::tar_read(metrics_summary) %>% View()

# 4. Check Romer & Romer validation
targets::tar_read(validation_report)

# 5. Visualize pipeline
targets::tar_visnetwork()

# 6. Check for errors
targets::tar_read(eval_act_detection)$llm_errors
```

### Expected Outputs

```
models/
├── act_detection/
│   ├── config.json
│   ├── pytorch_model.bin
│   └── training_metrics.json
├── motivation/
└── exogenous/

predictions/
├── act_detection_test_*.parquet
├── motivation_test_*.parquet
├── exogenous_test_*.parquet
├── act_detection_corpus_*.parquet
├── motivation_corpus_*.parquet
└── exogenous_corpus_*.parquet
```

## Implementation Sequence

1. **Week 1: Training & Prediction**
   - Add functions to `R/functions_model_training.R`
   - Add Stage 7 & 8 targets to `_targets.R`
   - Test training pipeline
   - Verify predictions

2. **Week 2: Evaluation**
   - Create `R/functions_evaluation.R`
   - Add Stage 9 targets
   - Test baselines and validation
   - Create results notebook

3. **Week 3: Refinement**
   - Hyperparameter tuning
   - Error analysis
   - Try alternative models
   - Final documentation
