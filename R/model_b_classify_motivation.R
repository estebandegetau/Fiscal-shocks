# Model B: Motivation Classification
# Multi-class classifier to determine fiscal act motivation category and exogenous flag

#' Classify fiscal act motivation using Claude API
#'
#' @param act_name Character string with act name
#' @param passages_text Character string with concatenated passages describing the act
#' @param year Integer year of act
#' @param model Character string for Claude model ID
#' @param examples List of few-shot examples (optional, loaded from JSON if NULL)
#' @param system_prompt Character string for system prompt (optional, loaded from file if NULL)
#' @param use_self_consistency Logical, use self-consistency sampling (default TRUE)
#' @param n_samples Integer number of samples for self-consistency (default 5)
#' @param temperature Numeric sampling temperature (default 0.7 for self-consistency)
#'
#' @return List with classification results (motivation, exogenous, confidence, evidence, reasoning)
#'   When using self-consistency, also includes agreement_rate and all_predictions
#' @export
model_b_classify_motivation <- function(act_name,
                                        passages_text,
                                        year,
                                        model = "claude-sonnet-4-20250514",
                                        examples = NULL,
                                        system_prompt = NULL,
                                        use_self_consistency = TRUE,
                                        n_samples = 5,
                                        temperature = 0.7) {

  # Load system prompt if not provided
  if (is.null(system_prompt)) {
    system_prompt_file <- here::here("prompts", "model_b_system.txt")
    if (!file.exists(system_prompt_file)) {
      stop("System prompt file not found: ", system_prompt_file)
    }
    system_prompt <- readr::read_file(system_prompt_file)
  }

  # Load examples if not provided
  if (is.null(examples)) {
    examples_file <- here::here("prompts", "model_b_examples.json")
    if (file.exists(examples_file)) {
      examples <- jsonlite::fromJSON(examples_file, simplifyVector = FALSE)
    } else {
      warning("No few-shot examples found at: ", examples_file)
      examples <- NULL
    }
  }

  # Format input with act context
  user_input <- glue::glue("
ACT: {act_name}
YEAR: {year}

PASSAGES FROM ORIGINAL SOURCES:
{passages_text}

Classify this act's PRIMARY motivation.
  ")

  # Use self-consistency if enabled

  if (use_self_consistency) {
    # Use self-consistency wrapper
    return(model_b_with_self_consistency(
      act_name = act_name,
      passages_text = passages_text,
      year = year,
      model = model,
      n_samples = n_samples,
      temperature = temperature,
      examples = examples,
      system_prompt = system_prompt
    ))
  }

  # Standard single-shot classification (temperature = 0)
  # Format prompt with few-shot examples
  full_prompt <- format_few_shot_prompt(
    system = system_prompt,
    examples = examples,
    user_input = user_input
  )

  # Call Claude API
  response <- call_claude_api(
    messages = list(list(role = "user", content = full_prompt)),
    model = model,
    max_tokens = 1000,  # Longer for reasoning
    temperature = 0.0  # Deterministic for classification
  )

  # Parse JSON response
  result <- parse_json_response(
    response$content[[1]]$text,
    required_fields = c("motivation", "exogenous", "confidence", "reasoning")
  )

  result
}


#' Run Model B classification on multiple acts
#'
#' @param act_names Character vector of act names
#' @param passages_texts Character vector of concatenated passages
#' @param years Integer vector of years
#' @param model Character string for Claude model ID
#' @param show_progress Logical, show progress bar (default TRUE)
#' @param use_self_consistency Logical, use self-consistency sampling (default TRUE)
#' @param n_samples Integer number of samples for self-consistency (default 5)
#' @param temperature Numeric sampling temperature (default 0.7 for self-consistency)
#'
#' @return Tibble with results for each act
#' @export
model_b_classify_motivation_batch <- function(act_names,
                                              passages_texts,
                                              years,
                                              model = "claude-sonnet-4-20250514",
                                              show_progress = TRUE,
                                              use_self_consistency = TRUE,
                                              n_samples = 5,
                                              temperature = 0.7) {

  # Validate inputs
  if (length(act_names) != length(passages_texts) || length(act_names) != length(years)) {
    stop("act_names, passages_texts, and years must have the same length")
  }

  # Load examples and system prompt once
  system_prompt_file <- here::here("prompts", "model_b_system.txt")
  system_prompt <- readr::read_file(system_prompt_file)

  examples_file <- here::here("prompts", "model_b_examples.json")
  if (file.exists(examples_file)) {
    examples <- jsonlite::fromJSON(examples_file, simplifyVector = FALSE)
  } else {
    examples <- NULL
  }

  # Process each act
  if (show_progress) {
    pb <- progress::progress_bar$new(
      format = "  Processing [:bar] :percent eta: :eta",
      total = length(act_names)
    )
  }

  results <- purrr::pmap(
    list(act_names, passages_texts, years),
    function(act_name, passages_text, year) {
      if (show_progress) pb$tick()

      result <- model_b_classify_motivation(
        act_name = act_name,
        passages_text = passages_text,
        year = year,
        model = model,
        examples = examples,
        system_prompt = system_prompt,
        use_self_consistency = use_self_consistency,
        n_samples = n_samples,
        temperature = temperature
      )

      # Return as tibble row
      # Include agreement_rate if using self-consistency
      tibble::tibble(
        motivation = if (!is.null(result$motivation)) result$motivation else NA_character_,
        exogenous = if (!is.null(result$exogenous)) result$exogenous else NA,
        confidence = if (!is.null(result$confidence)) result$confidence else NA_real_,
        agreement_rate = if (!is.null(result$agreement_rate)) result$agreement_rate else NA_real_,
        reasoning = if (!is.null(result$reasoning)) result$reasoning else NA_character_,
        evidence = if (!is.null(result$evidence)) list(result$evidence) else list(NULL)
      )
    }
  )

  dplyr::bind_rows(results)
}


#' Evaluate Model B predictions against ground truth
#'
#' @param predictions Tibble with predicted motivation and exogenous flag (columns: pred_motivation, pred_exogenous)
#' @param true_motivation Character vector of true motivation labels
#' @param true_exogenous Logical vector of true exogenous flags
#' @param motivation_levels Character vector of valid motivation categories
#'
#' @return List with evaluation metrics (accuracy, per-class F1, confusion matrix)
#' @export
evaluate_model_b <- function(predictions,
                             true_motivation,
                             true_exogenous,
                             motivation_levels = c("Spending-driven", "Countercyclical",
                                                   "Deficit-driven", "Long-run")) {

  # Ensure factor levels are consistent
  pred_motivation <- factor(predictions$pred_motivation, levels = motivation_levels)
  true_motivation <- factor(true_motivation, levels = motivation_levels)

  # Confusion matrix for motivation
  cm <- table(
    Predicted = pred_motivation,
    True = true_motivation
  )

  # Overall accuracy
  accuracy <- sum(diag(cm)) / sum(cm)

  # Per-class metrics
  per_class_metrics <- purrr::map_dfr(motivation_levels, function(class) {
    tp <- cm[class, class]
    fp <- sum(cm[class, ]) - tp
    fn <- sum(cm[, class]) - tp
    tn <- sum(cm) - tp - fp - fn

    precision <- ifelse(tp + fp > 0, tp / (tp + fp), NA_real_)
    recall <- ifelse(tp + fn > 0, tp / (tp + fn), NA_real_)
    f1 <- ifelse(!is.na(precision) && !is.na(recall) && precision + recall > 0,
                 2 * (precision * recall) / (precision + recall),
                 NA_real_)

    tibble::tibble(
      class = class,
      precision = precision,
      recall = recall,
      f1_score = f1,
      support = tp + fn
    )
  })

  # Macro-averaged F1
  macro_f1 <- mean(per_class_metrics$f1_score, na.rm = TRUE)

  # Exogenous flag accuracy
  exogenous_accuracy <- mean(predictions$pred_exogenous == true_exogenous, na.rm = TRUE)

  # Confidence calibration
  calibration <- predictions |>
    dplyr::mutate(
      true_motivation = true_motivation,
      predicted = pred_motivation,
      correct = (predicted == true_motivation)
    ) |>
    dplyr::group_by(confidence_bin = cut(pred_confidence, breaks = seq(0, 1, 0.1))) |>
    dplyr::summarize(
      n = dplyr::n(),
      accuracy = mean(correct, na.rm = TRUE),
      .groups = "drop"
    )

  list(
    confusion_matrix = cm,
    accuracy = accuracy,
    macro_f1 = macro_f1,
    per_class_metrics = per_class_metrics,
    exogenous_accuracy = exogenous_accuracy,
    calibration = calibration,
    n_total = length(true_motivation)
  )
}


#' Create confusion matrix plot for Model B
#'
#' @param evaluation_results List from evaluate_model_b()
#'
#' @return ggplot object
#' @export
plot_model_b_confusion_matrix <- function(evaluation_results) {

  cm_df <- as.data.frame(evaluation_results$confusion_matrix)

  # Abbreviate long category names for better display
  cm_df <- cm_df |>
    dplyr::mutate(
      Predicted = dplyr::recode(Predicted,
        "Spending-driven" = "Spending",
        "Countercyclical" = "Counter",
        "Deficit-driven" = "Deficit",
        "Long-run" = "Long-run"
      ),
      True = dplyr::recode(True,
        "Spending-driven" = "Spending",
        "Countercyclical" = "Counter",
        "Deficit-driven" = "Deficit",
        "Long-run" = "Long-run"
      )
    )

  ggplot2::ggplot(cm_df, ggplot2::aes(x = Predicted, y = True, fill = Freq)) +
    ggplot2::geom_tile(color = "white", size = 1) +
    ggplot2::geom_text(ggplot2::aes(label = Freq), color = "white", size = 6) +
    ggplot2::scale_fill_gradient(low = "#2c7bb6", high = "#d7191c") +
    ggplot2::labs(
      title = "Model B: Motivation Classification Confusion Matrix",
      subtitle = sprintf(
        "Accuracy = %.3f | Macro F1 = %.3f | Exogenous Acc = %.3f",
        evaluation_results$accuracy,
        evaluation_results$macro_f1,
        evaluation_results$exogenous_accuracy
      ),
      x = "Predicted Motivation",
      y = "True Motivation",
      fill = "Count"
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      panel.grid = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )
}
