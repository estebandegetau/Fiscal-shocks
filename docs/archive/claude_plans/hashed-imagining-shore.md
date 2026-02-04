# Training Plan: LLM-Based Fiscal Shock Identification Models

## Executive Summary

Build a supervised fine-tuning pipeline to train three sequential models on Romer & Romer labeled data:
1. **Model A**: Act Detection (binary classifier)
2. **Model B**: Motivation Classification (4-way: spending/countercyclical/deficit/long-run)
3. **Model D**: Exogenous vs Endogenous Classification (binary within motivation)

**Approach**: Fine-tune open-source transformer models (BERT/RoBERTa family) using multi-instance learning from us_labels.csv passages.

**Target Architecture**: Cascade pipeline (A → B → D) where each model filters/enriches outputs for the next stage.

---

## Phase 0: Data Preparation & Training Infrastructure Setup

### 0.1 Create Training Datasets from us_labels.csv

**New R functions** (`R/functions_training_data.R`):

```r
prepare_act_detection_data(us_labels, us_shocks, documents)
# Returns: tibble with columns (text, label [0/1], act_name, source, year)
# Positive examples: All text passages from us_labels (label=1)
# Negative examples: Random paragraphs from documents NOT in us_labels acts (label=0)
# Balance: 1:2 ratio (1 positive : 2 negatives) to reflect real-world distribution

prepare_motivation_classification_data(us_labels, us_shocks)
# Returns: tibble with columns (text, motivation [spending/counter/deficit/long],
#                                act_name, exogenous_flag, year)
# Multi-instance: Each text passage inherits act-level motivation from us_shocks
# Filter: Remove acts without clear motivation labels
# Balance: Stratified sampling to ensure all 4 categories well-represented

prepare_exogenous_classification_data(us_labels, us_shocks)
# Returns: tibble with columns (text, exogenous [0/1], motivation, act_name, year)
# Multi-instance: Each passage inherits exogenous flag from us_shocks
# Group by motivation: Create separate binary classifiers per motivation category
# Note: Some motivations are always exogenous (deficit, long-run) - may skip

create_train_val_test_splits(data, split_ratio = c(0.7, 0.15, 0.15),
                              stratify_by = "label")
# Returns: list(train, val, test) with stratified splits
# Stratification: Ensure label distribution preserved in splits
# Random seed: Set for reproducibility
```

**New targets** (`_targets.R` Stage 6):

```r
# Stage 6: Training Data Preparation
tar_target(
  training_data_act_detection,
  prepare_act_detection_data(us_labels, us_shocks, documents),
  format = "parquet"
),

tar_target(
  training_data_motivation,
  prepare_motivation_classification_data(us_labels, us_shocks),
  format = "parquet"
),

tar_target(
  training_data_exogenous,
  prepare_exogenous_classification_data(us_labels, us_shocks),
  format = "parquet"
),

tar_target(
  splits_act_detection,
  create_train_val_test_splits(
    training_data_act_detection,
    stratify_by = "label"
  ),
  format = "qs"
),

tar_target(
  splits_motivation,
  create_train_val_test_splits(
    training_data_motivation,
    stratify_by = "motivation"
  ),
  format = "qs"
),

tar_target(
  splits_exogenous,
  create_train_val_test_splits(
    training_data_exogenous,
    stratify_by = c("motivation", "exogenous")
  ),
  format = "qs"
)
```

**Critical files**:
- `/workspaces/Fiscal-shocks/R/functions_training_data.R` (new)
- `/workspaces/Fiscal-shocks/_targets.R` (modify - add Stage 6)

---

### 0.2 Python Training Infrastructure

**Update requirements.txt**:
```txt
# Existing
sentence-transformers
torch

# NEW: Training & Evaluation
transformers>=4.35.0
datasets>=2.14.0
accelerate>=0.24.0
scikit-learn>=1.3.0
pandas>=2.0.0
numpy>=1.24.0
tqdm>=4.66.0
tensorboard>=2.14.0         # For experiment tracking (local)
```

**New Python training script** (`python/train_classifier.py`):

```python
"""
Fine-tune transformer models for fiscal shock classification.

Usage:
  python python/train_classifier.py \
    --task {act_detection|motivation|exogenous} \
    --train_data data/processed/train.parquet \
    --val_data data/processed/val.parquet \
    --model_name bert-base-uncased \
    --output_dir models/act_detection_v1 \
    --num_epochs 10 \
    --batch_size 16 \
    --learning_rate 2e-5
"""

# Key components:
# 1. Load data from parquet (via pandas)
# 2. Tokenize text using AutoTokenizer
# 3. Create PyTorch DataLoaders
# 4. Load pre-trained model (AutoModelForSequenceClassification)
# 5. Fine-tune with Trainer API (HuggingFace)
# 6. Evaluate on validation set (accuracy, F1, precision, recall)
# 7. Save best checkpoint and tokenizer
# 8. Export training metrics to JSON
# 9. Log metrics to TensorBoard (local runs/directory)

# Architecture choices:
# - Act Detection: bert-base-uncased (110M params) - binary classification
# - Motivation: roberta-base (125M params) - 4-class classification
# - Exogenous: distilbert-base-uncased (66M params) - binary per motivation

# Hyperparameters (defaults - iterate manually based on validation):
# - Learning rate: 2e-5 (standard for BERT fine-tuning)
# - Batch size: 16 (adjust based on GPU memory - reduce if OOM)
# - Epochs: 10-15 with early stopping (patience=3 on validation loss)
# - Warmup steps: 500
# - Weight decay: 0.01
# - Max sequence length: 512 tokens
```

**New Python inference script** (`python/predict_classifier.py`):

```python
"""
Run inference with trained fiscal shock classifiers.

Usage:
  python python/predict_classifier.py \
    --model_path models/act_detection_v1 \
    --input_data data/processed/test.parquet \
    --output_path predictions/act_detection_test.parquet \
    --batch_size 32
"""

# Key components:
# 1. Load trained model and tokenizer from checkpoint
# 2. Load input data (text column)
# 3. Tokenize and batch
# 4. Run inference (no gradient computation)
# 5. Extract predictions and confidence scores
# 6. Save to parquet with original text + predictions
```

**R wrapper for Python training** (`R/functions_model_training.R`):

```r
train_classifier_python <- function(task, train_data, val_data,
                                     model_name, output_dir,
                                     num_epochs = 10, batch_size = 16,
                                     learning_rate = 2e-5) {
  # 1. Write train/val data to temp parquet files
  train_path <- tempfile(fileext = ".parquet")
  val_path <- tempfile(fileext = ".parquet")
  arrow::write_parquet(train_data, train_path)
  arrow::write_parquet(val_data, val_path)

  # 2. Call Python training script via system2
  python_exe <- Sys.getenv("DOCLING_PYTHON", "python")
  script_path <- here::here("python/train_classifier.py")

  args <- c(
    "--task", task,
    "--train_data", train_path,
    "--val_data", val_path,
    "--model_name", model_name,
    "--output_dir", output_dir,
    "--num_epochs", num_epochs,
    "--batch_size", batch_size,
    "--learning_rate", learning_rate
  )

  # 3. Execute with error handling
  result <- system2(python_exe, args = c(script_path, args),
                    stdout = TRUE, stderr = TRUE)

  # 4. Parse training metrics JSON
  metrics_path <- file.path(output_dir, "training_metrics.json")
  metrics <- jsonlite::read_json(metrics_path)

  # 5. Return output directory path and metrics
  list(
    model_path = output_dir,
    metrics = metrics,
    stdout = result
  )
}

predict_classifier_python <- function(model_path, input_data,
                                       output_path, batch_size = 32) {
  # Similar structure to train_classifier_python
  # Calls predict_classifier.py
  # Returns tibble with predictions
}
```

**Critical files**:
- `/workspaces/Fiscal-shocks/python/train_classifier.py` (new)
- `/workspaces/Fiscal-shocks/python/predict_classifier.py` (new)
- `/workspaces/Fiscal-shocks/R/functions_model_training.R` (new)
- `/workspaces/Fiscal-shocks/requirements.txt` (modify)

---

## Phase 1: Model A - Act Detection Training

### 1.1 Train Binary Classifier

**Model**: `bert-base-uncased` (110M parameters)
- **Why**: Best trade-off between performance and speed for binary classification
- **Input**: Text passages (max 512 tokens)
- **Output**: Binary probability (act mention: yes/no)
- **Metrics**: Precision, Recall, F1 (optimize for high recall - don't miss acts)

**New targets** (`_targets.R` Stage 7):

```r
# Stage 7: Model A - Act Detection
tar_target(
  model_a_trained,
  train_classifier_python(
    task = "act_detection",
    train_data = splits_act_detection$train,
    val_data = splits_act_detection$val,
    model_name = "bert-base-uncased",
    output_dir = here::here("models/act_detection_v1"),
    num_epochs = 10,
    batch_size = 16,
    learning_rate = 2e-5
  ),
  format = "qs"
),

tar_target(
  model_a_predictions_test,
  predict_classifier_python(
    model_path = model_a_trained$model_path,
    input_data = splits_act_detection$test,
    output_path = here::here("predictions/act_detection_test.parquet"),
    batch_size = 32
  ),
  format = "parquet"
),

tar_target(
  model_a_evaluation,
  evaluate_classifier(
    predictions = model_a_predictions_test,
    true_labels = splits_act_detection$test$label,
    task = "binary"
  ),
  format = "qs"
)
```

**New R evaluation function** (`R/functions_model_training.R`):

```r
evaluate_classifier <- function(predictions, true_labels, task = "binary") {
  # Use yardstick package for metrics
  library(yardstick)

  if (task == "binary") {
    metrics <- metric_set(accuracy, precision, recall, f_meas, roc_auc)
  } else if (task == "multiclass") {
    metrics <- metric_set(accuracy, precision, recall, f_meas)
  }

  # Create confusion matrix
  cm <- conf_mat(predictions, truth = true_labels, estimate = pred_class)

  # Calculate metrics
  results <- predictions %>%
    metrics(truth = true_labels, estimate = pred_class,
            pred_prob, event_level = "second")

  list(
    metrics = results,
    confusion_matrix = cm,
    predictions = predictions
  )
}
```

---

### 1.2 Validate on Full Document Corpus

**Goal**: Apply Model A to all `relevant_paragraphs` to identify candidate fiscal acts.

**New targets**:

```r
tar_target(
  candidate_acts,
  predict_classifier_python(
    model_path = model_a_trained$model_path,
    input_data = relevant_paragraphs %>% select(text, year, source, body),
    output_path = here::here("predictions/candidate_acts.parquet"),
    batch_size = 64
  ),
  format = "parquet"
),

tar_target(
  filtered_candidate_acts,
  candidate_acts %>%
    filter(pred_prob > 0.75) %>%  # High-confidence threshold
    arrange(desc(pred_prob)),
  format = "parquet"
)
```

---

## Phase 2: Model B - Motivation Classification Training

### 2.1 Train 4-Way Classifier

**Model**: `roberta-base` (125M parameters)
- **Why**: RoBERTa shows better performance on nuanced text classification
- **Input**: Text passages detected as acts by Model A
- **Output**: 4-class probability distribution (spending/countercyclical/deficit/long-run)
- **Metrics**: Macro F1 (equal weight to all classes), per-class precision/recall

**New targets** (`_targets.R` Stage 8):

```r
# Stage 8: Model B - Motivation Classification
tar_target(
  model_b_trained,
  train_classifier_python(
    task = "motivation",
    train_data = splits_motivation$train,
    val_data = splits_motivation$val,
    model_name = "roberta-base",
    output_dir = here::here("models/motivation_v1"),
    num_epochs = 15,
    batch_size = 12,
    learning_rate = 1e-5
  ),
  format = "qs"
),

tar_target(
  model_b_predictions_test,
  predict_classifier_python(
    model_path = model_b_trained$model_path,
    input_data = splits_motivation$test,
    output_path = here::here("predictions/motivation_test.parquet"),
    batch_size = 32
  ),
  format = "parquet"
),

tar_target(
  model_b_evaluation,
  evaluate_classifier(
    predictions = model_b_predictions_test,
    true_labels = splits_motivation$test$motivation,
    task = "multiclass"
  ),
  format = "qs"
)
```

---

### 2.2 Apply to Candidate Acts

**Goal**: Classify all high-confidence acts from Model A into motivation categories.

**New targets**:

```r
tar_target(
  classified_acts,
  predict_classifier_python(
    model_path = model_b_trained$model_path,
    input_data = filtered_candidate_acts,
    output_path = here::here("predictions/classified_acts.parquet"),
    batch_size = 32
  ),
  format = "parquet"
)
```

---

## Phase 3: Model D - Exogenous vs Endogenous Classification

### 3.1 Train Binary Classifiers (Per Motivation)

**Model**: `distilbert-base-uncased` (66M parameters) - separate model per motivation
- **Why**: DistilBERT is faster while maintaining accuracy for binary tasks
- **Input**: Acts with known motivation from Model B
- **Output**: Binary probability (exogenous vs endogenous)
- **Metrics**: Balanced accuracy (classes may be imbalanced)

**Strategy**: Train 4 separate models (one per motivation category) OR train single model with motivation as auxiliary input.

**Recommended**: Single model with concatenated input `[text] [SEP] [motivation_token]`

**New targets** (`_targets.R` Stage 9):

```r
# Stage 9: Model D - Exogenous Classification
tar_target(
  model_d_trained,
  train_classifier_python(
    task = "exogenous",
    train_data = splits_exogenous$train,
    val_data = splits_exogenous$val,
    model_name = "distilbert-base-uncased",
    output_dir = here::here("models/exogenous_v1"),
    num_epochs = 12,
    batch_size = 16,
    learning_rate = 2e-5
  ),
  format = "qs"
),

tar_target(
  model_d_predictions_test,
  predict_classifier_python(
    model_path = model_d_trained$model_path,
    input_data = splits_exogenous$test,
    output_path = here::here("predictions/exogenous_test.parquet"),
    batch_size = 32
  ),
  format = "parquet"
),

tar_target(
  model_d_evaluation,
  evaluate_classifier(
    predictions = model_d_predictions_test,
    true_labels = splits_exogenous$test$exogenous,
    task = "binary"
  ),
  format = "qs"
)
```

---

### 3.2 Final Pipeline: Cascade All Models

**Goal**: Apply A → B → D sequentially to create fully structured dataset.

**New target** (`_targets.R` Stage 10):

```r
# Stage 10: Full Pipeline Output
tar_target(
  final_structured_shocks,
  {
    # Step 1: Model A - Detect acts
    acts <- predict_classifier_python(
      model_path = model_a_trained$model_path,
      input_data = relevant_paragraphs,
      batch_size = 64
    ) %>% filter(pred_prob > 0.75)

    # Step 2: Model B - Classify motivation
    motivated <- predict_classifier_python(
      model_path = model_b_trained$model_path,
      input_data = acts,
      batch_size = 32
    )

    # Step 3: Model D - Classify exogenous
    final <- predict_classifier_python(
      model_path = model_d_trained$model_path,
      input_data = motivated,
      batch_size = 32
    )

    # Output structured dataset matching us_shocks.csv format
    final %>%
      select(
        text,
        year,
        source,
        body,
        act_detected = pred_class_a,
        act_confidence = pred_prob_a,
        motivation = pred_class_b,
        motivation_confidence = pred_prob_b,
        exogenous = pred_class_d,
        exogenous_confidence = pred_prob_d
      )
  },
  format = "parquet"
)
```

---

## Phase 4: Evaluation & US Benchmark Validation

### 4.1 Compare Against Romer & Romer Ground Truth

**Goal**: Quantify how well the pipeline reproduces the original US shock series.

**New evaluation function** (`R/functions_evaluation.R`):

```r
validate_against_romer <- function(final_structured_shocks, us_shocks, us_labels) {
  # 1. Match predicted acts to known Romer acts by year/text similarity
  # 2. Calculate detection rate: % of Romer acts detected by Model A
  # 3. Calculate motivation accuracy: % correct motivation classification
  # 4. Calculate exogenous accuracy: % correct exogenous classification
  # 5. Analyze false positives: predicted acts not in Romer dataset
  # 6. Analyze false negatives: Romer acts missed by pipeline

  list(
    detection_metrics = ...,
    motivation_metrics = ...,
    exogenous_metrics = ...,
    false_positives = ...,
    false_negatives = ...
  )
}
```

**New target**:

```r
tar_target(
  us_benchmark_validation,
  validate_against_romer(final_structured_shocks, us_shocks, us_labels),
  format = "qs"
)
```

---

### 4.2 Generate US Benchmark Report

**New Quarto notebook** (`notebooks/05_us_benchmark.qmd`):

```markdown
# US Benchmark Validation Report

## Model A: Act Detection
- Confusion matrix vs Romer & Romer labeled acts
- Precision/Recall/F1 scores
- Example false positives and false negatives

## Model B: Motivation Classification
- 4x4 confusion matrix (predicted vs true motivation)
- Per-class metrics
- Misclassification error analysis

## Model D: Exogenous Classification
- Accuracy by motivation category
- Examples of borderline cases

## Full Pipeline Performance
- End-to-end accuracy: % of Romer acts correctly detected + classified
- Comparison to baseline: keyword matching, rule-based systems
- Qualitative examples: side-by-side original text + predictions
```

---

## Phase 5: Model Serving & Production Inference

### 5.1 Batch Prediction API

**Goal**: Create reusable inference pipeline for new documents.

**New R function** (`R/functions_inference.R`):

```r
predict_fiscal_shocks <- function(input_documents,
                                   model_a_path,
                                   model_b_path,
                                   model_d_path,
                                   confidence_threshold = 0.75) {
  # Full cascade pipeline
  # Returns: tibble matching final_structured_shocks format
}
```

---

### 5.2 Model Versioning & Artifact Management

**Directory structure**:

```
models/
  act_detection_v1/
    pytorch_model.bin
    config.json
    tokenizer_config.json
    training_metrics.json
  motivation_v1/
    ...
  exogenous_v1/
    ...

predictions/
  act_detection_test.parquet
  motivation_test.parquet
  ...

data/processed/
  train_act_detection.parquet
  val_act_detection.parquet
  test_act_detection.parquet
  ...
```

**Add to .gitignore**:
```
models/
predictions/
data/processed/
*.parquet
```

**Track metadata only**: Store training configs, metrics, model cards in version control, but not model weights (too large).

---

## Phase 6: Extension to Southeast Asia (Future)

**Once US benchmark validated**, apply same pipeline to Malaysia/Indonesia/etc.:

1. Adapt `prepare_*_data()` functions for multilingual input
2. Add translation layer (use multilingual BERT or translate-then-classify)
3. Fine-tune on small labeled Malaysia dataset (transfer learning from US models)
4. Repeat validation process

---

## Critical Files Summary

### New Files to Create:

**R Functions**:
- `/workspaces/Fiscal-shocks/R/functions_training_data.R` - Data preparation
- `/workspaces/Fiscal-shocks/R/functions_model_training.R` - Training/prediction wrappers
- `/workspaces/Fiscal-shocks/R/functions_evaluation.R` - Evaluation metrics
- `/workspaces/Fiscal-shocks/R/functions_inference.R` - Production inference

**Python Scripts**:
- `/workspaces/Fiscal-shocks/python/train_classifier.py` - Fine-tuning script
- `/workspaces/Fiscal-shocks/python/predict_classifier.py` - Inference script

**Notebooks**:
- `/workspaces/Fiscal-shocks/notebooks/05_us_benchmark.qmd` - Validation report

**Data**:
- `data/processed/` directory for train/val/test splits (parquet)
- `models/` directory for saved model checkpoints
- `predictions/` directory for inference outputs

### Files to Modify:

- `/workspaces/Fiscal-shocks/_targets.R` - Add Stages 6-10
- `/workspaces/Fiscal-shocks/requirements.txt` - Add training dependencies
- `/workspaces/Fiscal-shocks/.gitignore` - Ignore large artifacts

---

## Execution Workflow

### Initial Setup (Once):
```bash
# 1. Update Python dependencies
pip install -r requirements.txt

# 2. Verify GPU availability (optional but recommended)
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
```

### Training Workflow (Iterative):
```r
# 1. Prepare training data
tar_make(training_data_act_detection)
tar_make(splits_act_detection)

# 2. Train Model A
tar_make(model_a_trained)
tar_make(model_a_evaluation)

# 3. Inspect results
tar_read(model_a_evaluation)

# 4. If satisfied, move to Model B
tar_make(model_b_trained)
tar_make(model_b_evaluation)

# 5. Continue cascade...
tar_make(model_d_trained)
tar_make(final_structured_shocks)

# 6. Validate against Romer
tar_make(us_benchmark_validation)

# 7. Generate report
quarto render notebooks/05_us_benchmark.qmd
```

---

## Success Criteria

### Model A (Act Detection):
- **Recall > 90%** on Romer acts (don't miss known shocks)
- **Precision > 70%** (acceptable false positive rate)

### Model B (Motivation Classification):
- **Macro F1 > 75%** (balanced across all 4 categories)
- **Per-class Recall > 65%** (no category totally fails)

### Model D (Exogenous Classification):
- **Balanced Accuracy > 80%**
- **Agreement with Romer > 85%** on known acts

### End-to-End Pipeline:
- **Reproduce > 80% of Romer shock series** (detected + correctly classified)
- **Qualitative validation**: Economists review sample outputs and confirm plausibility

---

## Next Steps After Plan Approval

1. **Implement Phase 0**: Create training data preparation functions
2. **Set up Python training infrastructure**: Write `train_classifier.py` and `predict_classifier.py`
3. **Train Model A**: First end-to-end training run with act detection
4. **Validate & iterate**: Review errors, adjust hyperparameters, retrain
5. **Cascade to Models B and D**: Sequential training once A is validated
6. **Generate benchmark report**: Full Quarto document with results
7. **Package for production**: Inference API and documentation

---

## Risk Mitigation

**Risk**: Insufficient training data (us_labels.csv may have < 500 examples)
- **Mitigation**: Use data augmentation (paraphrasing via GPT-4), semi-supervised learning on unlabeled documents

**Risk**: Multi-instance learning introduces noise (passages may not all describe motivation)
- **Mitigation**: Add confidence-based weighting, manually review high-error examples, consider attention-based MIL models

**Risk**: Class imbalance (some motivations rare)
- **Mitigation**: Use weighted loss functions, oversample minority classes, try focal loss

**Risk**: Model overfits to US language/institutions (won't transfer to SEA)
- **Mitigation**: Start with multilingual pre-trained models (mBERT, XLM-R), include domain adaptation techniques

**Risk**: Computational requirements too high
- **Mitigation**: Start with smaller models (DistilBERT), use mixed precision training (fp16), leverage cloud GPUs (Colab, Paperspace)

---

## Estimated Timeline

- **Phase 0 (Setup)**: 2-3 days
- **Phase 1 (Model A)**: 3-5 days (including iterations)
- **Phase 2 (Model B)**: 3-5 days
- **Phase 3 (Model D)**: 2-3 days
- **Phase 4 (Validation)**: 2-3 days
- **Phase 5 (Production)**: 2-3 days

**Total**: 2-3 weeks for full US benchmark pipeline

---

## Implementation Decisions (Based on User Preferences)

✅ **Model C (Magnitude Extraction)**: Defer to Phase 2 after classification models validated
✅ **Experiment Tracking**: TensorBoard (local logging only, no external services)
✅ **Hyperparameter Tuning**: Start with defaults, iterate manually based on validation performance
✅ **Training Strategy**: Early stopping with patience=3 on validation loss

## Viewing Training Progress

During training, launch TensorBoard to monitor metrics:
```bash
tensorboard --logdir=runs/
# Open browser to http://localhost:6006
```

## Additional Notes

- **GPU Usage**: Training will auto-detect CUDA if available, otherwise fall back to CPU
- **Checkpointing**: Best model saved based on validation loss (not final epoch)
- **Reproducibility**: Set random seeds in training script for consistent results
- **Model Size**: Total disk space ~1-2GB for all 3 trained models
