# Model A: Act Detection
# Binary classifier to determine if a passage describes a specific fiscal act

#' Detect fiscal acts in text passages using Claude API
#'
#' @param text Character string with passage text to classify
#' @param model Character string for Claude model ID
#' @param examples List of few-shot examples (optional, loaded from JSON if NULL)
#' @param system_prompt Character string for system prompt (optional, loaded from file if NULL)
#'
#' @return List with classification results (contains_act, act_name, confidence, reasoning)
#' @export
model_a_detect_acts <- function(text,
                                model = "claude-sonnet-4-20250514",
                                examples = NULL,
                                system_prompt = NULL) {

  # Load system prompt if not provided
  if (is.null(system_prompt)) {
    system_prompt_file <- here::here("prompts", "model_a_system.txt")
    if (!file.exists(system_prompt_file)) {
      stop("System prompt file not found: ", system_prompt_file)
    }
    system_prompt <- readr::read_file(system_prompt_file)
  }

  # Load examples if not provided
  if (is.null(examples)) {
    examples_file <- here::here("prompts", "model_a_examples.json")
    if (file.exists(examples_file)) {
      examples <- jsonlite::fromJSON(examples_file, simplifyVector = FALSE)
    } else {
      warning("No few-shot examples found at: ", examples_file)
      examples <- NULL
    }
  }

  # Format prompt with few-shot examples
  full_prompt <- format_few_shot_prompt(
    system = system_prompt,
    examples = examples,
    user_input = text
  )

  # Call Claude API
  response <- call_claude_api(
    messages = list(list(role = "user", content = full_prompt)),
    model = model,
    max_tokens = 500,
    temperature = 0.0  # Deterministic for classification
  )

  # Parse JSON response
  result <- parse_json_response(
    response$content[[1]]$text,
    required_fields = c("contains_act", "confidence", "reasoning")
  )

  result
}


#' Run Model A detection on multiple texts
#'
#' @param texts Character vector of passages to classify
#' @param model Character string for Claude model ID
#' @param show_progress Logical, show progress bar (default TRUE)
#'
#' @return Tibble with results for each text
#' @export
model_a_detect_acts_batch <- function(texts,
                                      model = "claude-sonnet-4-20250514",
                                      show_progress = TRUE) {

  # Load examples and system prompt once
  system_prompt_file <- here::here("prompts", "model_a_system.txt")
  system_prompt <- readr::read_file(system_prompt_file)

  examples_file <- here::here("prompts", "model_a_examples.json")
  if (file.exists(examples_file)) {
    examples <- jsonlite::fromJSON(examples_file, simplifyVector = FALSE)
  } else {
    examples <- NULL
  }

  # Process each text
  if (show_progress) {
    pb <- progress::progress_bar$new(
      format = "  Processing [:bar] :percent eta: :eta",
      total = length(texts)
    )
  }

  results <- purrr::map(texts, function(text) {
    if (show_progress) pb$tick()

    result <- model_a_detect_acts(
      text = text,
      model = model,
      examples = examples,
      system_prompt = system_prompt
    )

    # Return as tibble row
    # Use null-coalescing to handle missing fields
    # Normalize act_name to character (handle cases where LLM returns array)
    act_name_value <- result$act_name
    if (!is.null(act_name_value)) {
      if (is.list(act_name_value)) {
        # If LLM returned an array, take the first element
        act_name_value <- if (length(act_name_value) > 0) {
          as.character(act_name_value[[1]])
        } else {
          NA_character_
        }
      } else {
        act_name_value <- as.character(act_name_value)
      }
    } else {
      act_name_value <- NA_character_
    }

    tibble::tibble(
      contains_act = if (!is.null(result$contains_act)) result$contains_act else NA,
      act_name = act_name_value,
      confidence = if (!is.null(result$confidence)) result$confidence else NA_real_,
      reasoning = if (!is.null(result$reasoning)) result$reasoning else NA_character_
    )
  })

  dplyr::bind_rows(results)
}


#' Evaluate Model A predictions against ground truth
#'
#' @param predictions Tibble with predicted contains_act and confidence
#' @param true_labels Integer vector of true labels (1 = contains act, 0 = no act)
#' @param threshold Numeric threshold for binary classification (default 0.5)
#'
#' @return List with evaluation metrics (precision, recall, F1, confusion matrix)
#' @export
evaluate_model_a <- function(predictions, true_labels, threshold = 0.5) {

  # Convert predictions to binary (using confidence threshold)
  pred_binary <- ifelse(
    predictions$contains_act == TRUE & predictions$confidence >= threshold,
    1,
    0
  )

  # Confusion matrix
  cm <- table(
    Predicted = factor(pred_binary, levels = c(0, 1)),
    True = factor(true_labels, levels = c(0, 1))
  )

  # Calculate metrics
  tp <- cm[2, 2]  # True positives
  fp <- cm[2, 1]  # False positives
  fn <- cm[1, 2]  # False negatives
  tn <- cm[1, 1]  # True negatives

  precision <- tp / (tp + fp)
  recall <- tp / (tp + fn)
  f1 <- 2 * (precision * recall) / (precision + recall)
  accuracy <- (tp + tn) / sum(cm)

  # Confidence calibration
  calibration <- predictions |>
    dplyr::mutate(
      true_label = true_labels,
      predicted = pred_binary
    ) |>
    dplyr::group_by(confidence_bin = cut(confidence, breaks = seq(0, 1, 0.1))) |>
    dplyr::summarize(
      n = dplyr::n(),
      accuracy = mean(predicted == true_label),
      .groups = "drop"
    )

  list(
    confusion_matrix = cm,
    precision = precision,
    recall = recall,
    f1_score = f1,
    accuracy = accuracy,
    threshold = threshold,
    calibration = calibration,
    n_total = length(true_labels),
    n_positive = sum(true_labels == 1),
    n_negative = sum(true_labels == 0)
  )
}


#' Create confusion matrix plot for Model A
#'
#' @param evaluation_results List from evaluate_model_a()
#'
#' @return ggplot object
#' @export
plot_model_a_confusion_matrix <- function(evaluation_results) {

  cm_df <- as.data.frame(evaluation_results$confusion_matrix)

  ggplot2::ggplot(cm_df, ggplot2::aes(x = Predicted, y = True, fill = Freq)) +
    ggplot2::geom_tile(color = "white", size = 1) +
    ggplot2::geom_text(ggplot2::aes(label = Freq), color = "white", size = 8) +
    ggplot2::scale_fill_gradient(low = "#2c7bb6", high = "#d7191c") +
    ggplot2::labs(
      title = "Model A: Act Detection Confusion Matrix",
      subtitle = sprintf(
        "F1 = %.3f | Precision = %.3f | Recall = %.3f",
        evaluation_results$f1_score,
        evaluation_results$precision,
        evaluation_results$recall
      ),
      x = "Predicted",
      y = "True Label",
      fill = "Count"
    ) +
    ggplot2::theme_minimal(base_size = 14) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      panel.grid = ggplot2::element_blank()
    )
}
