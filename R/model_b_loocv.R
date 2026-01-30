# Model B Leave-One-Out Cross-Validation (LOOCV)
# Replaces fragile train/val/test split with robust evaluation over all 44 acts
#
# Rationale: With only 44 acts, fixed splits cause high variance.
# LOOCV gives all 44 acts as test points, providing more reliable estimates.

#' Run Leave-One-Out Cross-Validation for Model B
#'
#' For each act i in the dataset:
#' 1. Generate few-shot examples from all OTHER acts (excluding act i)
#' 2. Classify act i using those examples
#' 3. Record prediction vs true label
#'
#' @param aligned_data Tibble with all labeled acts (must have act_name, passages_text,
#'   year, motivation, exogenous columns)
#' @param model Character string for Claude model ID (default "claude-sonnet-4-20250514")
#' @param n_per_class Integer number of examples per motivation category (default 5)
#' @param seed Integer for reproducibility (default 20251206)
#' @param use_self_consistency Logical, use self-consistency sampling (default TRUE)
#' @param n_samples Integer number of samples for self-consistency (default 5)
#' @param temperature Numeric sampling temperature (default 0.7)
#' @param show_progress Logical, show progress bar (default TRUE)
#'
#' @return Tibble with columns:
#'   - act_name: Name of the held-out act
#'   - year: Year of the act
#'   - true_motivation: Ground truth motivation
#'   - true_exogenous: Ground truth exogenous flag
#'   - pred_motivation: Model prediction
#'   - pred_exogenous: Model's exogenous prediction
#'   - pred_confidence: Model confidence
#'   - pred_agreement_rate: Self-consistency agreement rate
#'   - correct: Whether prediction matched ground truth
#'   - exogenous_correct: Whether exogenous flag matched
#' @export
model_b_loocv <- function(aligned_data,
                          model = "claude-sonnet-4-20250514",
                          n_per_class = 5,
                          seed = 20251206,
                          use_self_consistency = TRUE,
                          n_samples = 5,
                          temperature = 0.7,
                          show_progress = TRUE) {

  # Validate input
  required_cols <- c("act_name", "passages_text", "year", "motivation", "exogenous")
  missing_cols <- setdiff(required_cols, names(aligned_data))
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  n_acts <- nrow(aligned_data)
  message(sprintf("Running LOOCV on %d acts...", n_acts))

  # Load system prompt once
  system_prompt_file <- here::here("prompts", "model_b_system.txt")
  if (!file.exists(system_prompt_file)) {
    stop("System prompt file not found: ", system_prompt_file)
  }
  system_prompt <- readr::read_file(system_prompt_file)

  # Initialize progress bar
 if (show_progress) {
    pb <- progress::progress_bar$new(
      format = "  LOOCV [:bar] :current/:total (:percent) eta: :eta",
      total = n_acts,
      clear = FALSE
    )
  }

  # Run LOOCV
  results <- purrr::map(seq_len(n_acts), function(i) {
    if (show_progress) pb$tick()

    # Set seed for reproducible example selection (varies by fold)
    set.seed(seed + i)

    # Held-out act
    test_act <- aligned_data[i, ]

    # Training data: all acts except the held-out one
    train_data <- aligned_data[-i, ]

    # Generate few-shot examples from training data
    # We need to sample n_per_class from each motivation category
    examples <- generate_loocv_examples(
      train_data = train_data,
      n_per_class = n_per_class
    )

    # Classify the held-out act
    prediction <- tryCatch({
      model_b_classify_motivation(
        act_name = test_act$act_name,
        passages_text = test_act$passages_text,
        year = test_act$year,
        model = model,
        examples = examples,
        system_prompt = system_prompt,
        use_self_consistency = use_self_consistency,
        n_samples = n_samples,
        temperature = temperature,
        economic_context = NULL
      )
    }, error = function(e) {
      warning(sprintf("Error classifying act %s: %s", test_act$act_name, e$message))
      list(
        motivation = NA_character_,
        exogenous = NA,
        confidence = NA_real_,
        agreement_rate = NA_real_,
        reasoning = e$message
      )
    })

    # Return results row
    tibble::tibble(
      act_name = test_act$act_name,
      year = test_act$year,
      true_motivation = test_act$motivation,
      true_exogenous = test_act$exogenous,
      pred_motivation = prediction$motivation %||% NA_character_,
      pred_exogenous = prediction$exogenous %||% NA,
      pred_confidence = prediction$confidence %||% NA_real_,
      pred_agreement_rate = prediction$agreement_rate %||% NA_real_,
      pred_reasoning = prediction$reasoning %||% NA_character_,
      correct = (prediction$motivation == test_act$motivation) %||% FALSE,
      exogenous_correct = (prediction$exogenous == test_act$exogenous) %||% FALSE
    )
  })

  dplyr::bind_rows(results)
}


#' Generate few-shot examples for a LOOCV fold
#'
#' Internal helper that samples n_per_class examples from each motivation
#' category in the training data.
#'
#' @param train_data Tibble with training acts (all acts except held-out)
#' @param n_per_class Integer number of examples per class
#'
#' @return List of examples in the format expected by model_b_classify_motivation
#' @keywords internal
generate_loocv_examples <- function(train_data, n_per_class = 5) {

  all_motivations <- c("Spending-driven", "Countercyclical", "Deficit-driven", "Long-run")

  examples_list <- list()

  for (motiv in all_motivations) {
    pool <- train_data |>
      dplyr::filter(motivation == motiv)

    # Sample up to n_per_class
    n_available <- nrow(pool)
    n_to_sample <- min(n_per_class, n_available)

    if (n_to_sample > 0) {
      sampled <- pool |>
        dplyr::slice_sample(n = n_to_sample)

      for (j in seq_len(nrow(sampled))) {
        row <- sampled[j, ]

        example <- list(
          input = glue::glue("
ACT: {row$act_name}
YEAR: {row$year}

PASSAGES FROM ORIGINAL SOURCES:
{row$passages_text}

Classify this act's PRIMARY motivation.
          "),
          output = list(
            motivation = row$motivation,
            exogenous = row$exogenous,
            confidence = 0.95,
            evidence = list(
              list(
                passage_excerpt = stringr::str_sub(row$passages_text, 1, 150),
                supports = row$motivation
              )
            ),
            reasoning = glue::glue(
              "This act is classified as {row$motivation} based on the legislative context and timing."
            )
          )
        )

        examples_list <- append(examples_list, list(example))
      }
    }
  }

  examples_list
}


#' Evaluate Model B LOOCV results with bootstrap confidence intervals
#'
#' Computes overall accuracy, per-class F1 scores, and exogenous accuracy
#' with bootstrap confidence intervals.
#'
#' @param loocv_results Tibble from model_b_loocv()
#' @param n_bootstrap Integer number of bootstrap samples for CIs (default 1000)
#' @param ci_level Numeric confidence level (default 0.95)
#' @param motivation_levels Character vector of valid motivation categories
#'
#' @return List with:
#'   - accuracy: Overall accuracy with CI
#'   - exogenous_accuracy: Exogenous flag accuracy with CI
#'   - macro_f1: Macro-averaged F1 with CI
#'   - per_class_metrics: Tibble with precision, recall, F1 per class
#'   - confusion_matrix: Full confusion matrix
#'   - error_analysis: Tibble of misclassified acts for review
#' @export
evaluate_model_b_loocv <- function(loocv_results,
                                   n_bootstrap = 1000,
                                   ci_level = 0.95,
                                   motivation_levels = c("Spending-driven", "Countercyclical",
                                                         "Deficit-driven", "Long-run")) {

  # Filter out rows with NA predictions
  valid_results <- loocv_results |>
    dplyr::filter(!is.na(pred_motivation))

  n_total <- nrow(loocv_results)
  n_valid <- nrow(valid_results)

  if (n_valid < n_total) {
    warning(sprintf("%d/%d acts had NA predictions and were excluded from evaluation",
                    n_total - n_valid, n_total))
  }

  # Compute point estimates
  accuracy <- mean(valid_results$correct, na.rm = TRUE)
  exogenous_accuracy <- mean(valid_results$exogenous_correct, na.rm = TRUE)

  # Confusion matrix
  pred_motivation <- factor(valid_results$pred_motivation, levels = motivation_levels)
  true_motivation <- factor(valid_results$true_motivation, levels = motivation_levels)

  cm <- table(
    Predicted = pred_motivation,
    True = true_motivation
  )

  # Per-class metrics
  per_class_metrics <- compute_per_class_metrics(cm, motivation_levels)
  macro_f1 <- mean(per_class_metrics$f1_score, na.rm = TRUE)

  # Bootstrap confidence intervals
  set.seed(42)  # For reproducible CIs

  boot_stats <- replicate(n_bootstrap, {
    # Resample with replacement
    boot_idx <- sample(seq_len(n_valid), n_valid, replace = TRUE)
    boot_data <- valid_results[boot_idx, ]

    boot_acc <- mean(boot_data$correct, na.rm = TRUE)
    boot_exog_acc <- mean(boot_data$exogenous_correct, na.rm = TRUE)

    # Compute per-class F1 for macro average
    boot_cm <- table(
      Predicted = factor(boot_data$pred_motivation, levels = motivation_levels),
      True = factor(boot_data$true_motivation, levels = motivation_levels)
    )
    boot_class <- compute_per_class_metrics(boot_cm, motivation_levels)
    boot_macro_f1 <- mean(boot_class$f1_score, na.rm = TRUE)

    c(accuracy = boot_acc, exogenous_accuracy = boot_exog_acc, macro_f1 = boot_macro_f1)
  })

  # Compute CIs
  alpha <- 1 - ci_level
  ci_lower <- apply(boot_stats, 1, quantile, probs = alpha / 2)
  ci_upper <- apply(boot_stats, 1, quantile, probs = 1 - alpha / 2)

  # Error analysis: which acts were misclassified?
  error_analysis <- valid_results |>
    dplyr::filter(!correct) |>
    dplyr::select(act_name, year, true_motivation, pred_motivation,
                  pred_confidence, pred_agreement_rate) |>
    dplyr::arrange(true_motivation, act_name)

  # Exogenous precision (for Phase 1 Malaysia: we want high precision on exogenous)
  exog_pred <- valid_results$pred_exogenous
  exog_true <- valid_results$true_exogenous

  exog_tp <- sum(exog_pred & exog_true, na.rm = TRUE)
  exog_fp <- sum(exog_pred & !exog_true, na.rm = TRUE)
  exog_fn <- sum(!exog_pred & exog_true, na.rm = TRUE)

  exogenous_precision <- if (exog_tp + exog_fp > 0) exog_tp / (exog_tp + exog_fp) else NA_real_
  exogenous_recall <- if (exog_tp + exog_fn > 0) exog_tp / (exog_tp + exog_fn) else NA_real_

  list(
    accuracy = accuracy,
    accuracy_ci = c(lower = ci_lower["accuracy"], upper = ci_upper["accuracy"]),
    exogenous_accuracy = exogenous_accuracy,
    exogenous_accuracy_ci = c(lower = ci_lower["exogenous_accuracy"],
                               upper = ci_upper["exogenous_accuracy"]),
    exogenous_precision = exogenous_precision,
    exogenous_recall = exogenous_recall,
    macro_f1 = macro_f1,
    macro_f1_ci = c(lower = ci_lower["macro_f1"], upper = ci_upper["macro_f1"]),
    per_class_metrics = per_class_metrics,
    confusion_matrix = cm,
    error_analysis = error_analysis,
    n_total = n_total,
    n_valid = n_valid,
    ci_level = ci_level,
    n_bootstrap = n_bootstrap
  )
}


#' Compute per-class precision, recall, F1
#'
#' Internal helper for computing metrics from confusion matrix.
#'
#' @param cm Confusion matrix (table)
#' @param motivation_levels Character vector of class labels
#'
#' @return Tibble with per-class metrics
#' @keywords internal
compute_per_class_metrics <- function(cm, motivation_levels) {
  purrr::map_dfr(motivation_levels, function(class) {
    tp <- cm[class, class]
    fp <- sum(cm[class, ]) - tp
    fn <- sum(cm[, class]) - tp

    precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
    recall <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
    f1 <- if (!is.na(precision) && !is.na(recall) && precision + recall > 0) {
      2 * (precision * recall) / (precision + recall)
    } else {
      NA_real_
    }

    tibble::tibble(
      class = class,
      precision = precision,
      recall = recall,
      f1_score = f1,
      support = tp + fn
    )
  })
}


#' Print summary of LOOCV evaluation
#'
#' @param eval_results List from evaluate_model_b_loocv()
#' @export
print_loocv_summary <- function(eval_results) {
  cat("=" %>% rep(60) %>% paste(collapse = ""), "\n")
  cat("Model B LOOCV Evaluation Summary\n")
  cat("=" %>% rep(60) %>% paste(collapse = ""), "\n\n")

  cat(sprintf("N acts evaluated: %d/%d\n\n", eval_results$n_valid, eval_results$n_total))

  cat("Overall Metrics (%.0f%% CI):\n", eval_results$ci_level * 100)
  cat(sprintf("  Accuracy:          %.1f%% [%.1f%%, %.1f%%]\n",
              eval_results$accuracy * 100,
              eval_results$accuracy_ci["lower"] * 100,
              eval_results$accuracy_ci["upper"] * 100))
  cat(sprintf("  Macro F1:          %.1f%% [%.1f%%, %.1f%%]\n",
              eval_results$macro_f1 * 100,
              eval_results$macro_f1_ci["lower"] * 100,
              eval_results$macro_f1_ci["upper"] * 100))
  cat(sprintf("  Exogenous Acc:     %.1f%% [%.1f%%, %.1f%%]\n",
              eval_results$exogenous_accuracy * 100,
              eval_results$exogenous_accuracy_ci["lower"] * 100,
              eval_results$exogenous_accuracy_ci["upper"] * 100))
  cat(sprintf("  Exogenous Prec:    %.1f%%\n",
              eval_results$exogenous_precision * 100))
  cat(sprintf("  Exogenous Recall:  %.1f%%\n\n",
              eval_results$exogenous_recall * 100))

  cat("Per-Class Metrics:\n")
  print(eval_results$per_class_metrics, n = 10)

  cat("\n\nConfusion Matrix:\n")
  print(eval_results$confusion_matrix)

  if (nrow(eval_results$error_analysis) > 0) {
    cat("\n\nMisclassified Acts:\n")
    print(eval_results$error_analysis, n = 20)
  }

  invisible(eval_results)
}


# Null coalescing operator (if not already defined)
if (!exists("%||%", mode = "function", envir = environment())) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
