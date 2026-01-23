# Model C Evaluation: Multi-Quarter Information Extraction Metrics
# Evaluates timing, magnitude, and coverage across all quarters

#' Evaluate Model C multi-quarter predictions against ground truth
#'
#' @param predictions Tibble with predicted_quarters and ground_truth_quarters list-columns
#'
#' @return List with comprehensive evaluation metrics
#' @export
evaluate_model_c <- function(predictions) {

  # Ensure required columns exist
  required_cols <- c("act_name", "ground_truth_quarters", "predicted_quarters")
  missing_cols <- setdiff(required_cols, names(predictions))
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  # Expand predictions and ground truth to quarter level
  quarter_level_data <- predictions %>%
    dplyr::select(act_name, ground_truth_quarters, predicted_quarters) %>%
    dplyr::mutate(
      # Standardize ground truth column names
      ground_truth = purrr::map(ground_truth_quarters, ~ {
        tibble::tibble(
          quarter = .x$change_in_liabilities_quarter,
          magnitude = .x$change_in_liabilities_billion,
          pv_quarter = .x$present_value_quarter,
          pv_magnitude = .x$present_value_billion
        )
      }),
      # Standardize prediction column names
      predictions = purrr::map(predicted_quarters, ~ {
        if (nrow(.x) == 0) {
          return(tibble::tibble(
            quarter = character(0),
            magnitude = numeric(0),
            pv_quarter = character(0),
            pv_magnitude = numeric(0),
            confidence = numeric(0)
          ))
        }
        tibble::tibble(
          quarter = .x$timing_quarter,
          magnitude = .x$magnitude_billions,
          pv_quarter = .x$present_value_quarter,
          pv_magnitude = .x$present_value_billions,
          confidence = .x$confidence
        )
      })
    )

  # Match quarters for each act
  matched_data <- quarter_level_data %>%
    dplyr::mutate(
      matches = purrr::map2(ground_truth, predictions, match_quarters)
    )

  # Unnest matches for aggregate metrics
  all_matches <- matched_data %>%
    dplyr::select(act_name, matches) %>%
    tidyr::unnest(matches)

  # Calculate metrics
  metrics <- list(
    # TIMING METRICS
    timing_exact_match = mean(all_matches$quarter_exact_match, na.rm = TRUE),
    timing_1q_tolerance = mean(all_matches$quarter_within_1q, na.rm = TRUE),
    timing_median_error_quarters = median(abs(all_matches$quarter_error_q), na.rm = TRUE),
    timing_mean_error_quarters = mean(abs(all_matches$quarter_error_q), na.rm = TRUE),

    # MAGNITUDE METRICS (on matched quarters only)
    magnitude_mape = mean(abs(all_matches$magnitude_pct_error), na.rm = TRUE),
    magnitude_rmse = sqrt(mean((all_matches$true_magnitude - all_matches$pred_magnitude)^2, na.rm = TRUE)),
    magnitude_sign_accuracy = mean(all_matches$sign_correct, na.rm = TRUE),
    magnitude_correlation = stats::cor(
      all_matches$true_magnitude,
      all_matches$pred_magnitude,
      use = "complete.obs"
    ),

    # COVERAGE METRICS
    total_true_quarters = sum(purrr::map_int(quarter_level_data$ground_truth, nrow)),
    total_pred_quarters = sum(purrr::map_int(quarter_level_data$predictions, nrow)),
    matched_quarters = sum(all_matches$is_matched, na.rm = TRUE),
    recall_quarters = sum(all_matches$is_matched, na.rm = TRUE) /
                      sum(purrr::map_int(quarter_level_data$ground_truth, nrow)),
    precision_quarters = sum(all_matches$is_matched, na.rm = TRUE) /
                         sum(purrr::map_int(quarter_level_data$predictions, nrow)),

    # ACT-LEVEL METRICS
    n_acts = nrow(matched_data),
    acts_all_quarters_correct = mean(purrr::map_lgl(matched_data$matches, ~ {
      all(.x$quarter_exact_match, na.rm = TRUE)
    })),
    acts_50pct_quarters_correct = mean(purrr::map_lgl(matched_data$matches, ~ {
      mean(.x$quarter_exact_match, na.rm = TRUE) >= 0.5
    })),
    acts_mean_recall = mean(purrr::map_dbl(matched_data$matches, ~ {
      sum(.x$is_matched, na.rm = TRUE) / nrow(.x)
    }), na.rm = TRUE),

    # DETAILED RESULTS
    matched_data = matched_data,
    all_matches = all_matches
  )

  metrics
}


#' Match predicted quarters to ground truth quarters with fuzzy tolerance
#'
#' @param ground_truth Tibble with true quarters (quarter, magnitude, pv_quarter, pv_magnitude)
#' @param predictions Tibble with predicted quarters (quarter, magnitude, pv_quarter, pv_magnitude, confidence)
#' @param tolerance_quarters Integer, number of quarters tolerance for fuzzy matching (default 1)
#'
#' @return Tibble with one row per quarter (union of true and predicted) with match information
#' @export
match_quarters <- function(ground_truth, predictions, tolerance_quarters = 1) {

  # Handle empty cases
  if (nrow(ground_truth) == 0 && nrow(predictions) == 0) {
    return(tibble::tibble(
      true_quarter = character(0),
      pred_quarter = character(0),
      true_magnitude = numeric(0),
      pred_magnitude = numeric(0),
      quarter_exact_match = logical(0),
      quarter_within_1q = logical(0),
      quarter_error_q = numeric(0),
      magnitude_pct_error = numeric(0),
      sign_correct = logical(0),
      is_matched = logical(0)
    ))
  }

  if (nrow(ground_truth) == 0) {
    # Only predictions (false positives)
    return(tibble::tibble(
      true_quarter = NA_character_,
      pred_quarter = predictions$quarter,
      true_magnitude = NA_real_,
      pred_magnitude = predictions$magnitude,
      quarter_exact_match = FALSE,
      quarter_within_1q = FALSE,
      quarter_error_q = NA_real_,
      magnitude_pct_error = NA_real_,
      sign_correct = NA,
      is_matched = FALSE
    ))
  }

  if (nrow(predictions) == 0) {
    # Only ground truth (false negatives / misses)
    return(tibble::tibble(
      true_quarter = ground_truth$quarter,
      pred_quarter = NA_character_,
      true_magnitude = ground_truth$magnitude,
      pred_magnitude = NA_real_,
      quarter_exact_match = FALSE,
      quarter_within_1q = FALSE,
      quarter_error_q = NA_real_,
      magnitude_pct_error = NA_real_,
      sign_correct = NA,
      is_matched = FALSE
    ))
  }

  # Convert quarters to dates for distance calculation
  true_dates <- lubridate::yq(ground_truth$quarter)
  pred_dates <- lubridate::yq(predictions$quarter)

  # For each predicted quarter, find closest true quarter
  matched_rows <- purrr::map_dfr(seq_len(nrow(predictions)), function(i) {
    pred_date <- pred_dates[i]
    pred_quarter <- predictions$quarter[i]
    pred_magnitude <- predictions$magnitude[i]

    # Calculate quarter distance to all true quarters
    quarter_diffs <- as.numeric(difftime(pred_date, true_dates, units = "weeks")) / 13
    abs_quarter_diffs <- abs(quarter_diffs)
    closest_idx <- which.min(abs_quarter_diffs)
    min_distance <- abs_quarter_diffs[closest_idx]

    # Match if within tolerance
    is_match <- min_distance <= tolerance_quarters

    if (is_match) {
      true_quarter <- ground_truth$quarter[closest_idx]
      true_magnitude <- ground_truth$magnitude[closest_idx]
      quarter_error <- quarter_diffs[closest_idx]

      # Calculate magnitude metrics
      if (!is.na(true_magnitude) && !is.na(pred_magnitude) && abs(true_magnitude) > 0) {
        magnitude_pct_error <- abs(pred_magnitude - true_magnitude) / abs(true_magnitude)
      } else {
        magnitude_pct_error <- NA_real_
      }

      sign_correct <- if (!is.na(true_magnitude) && !is.na(pred_magnitude)) {
        sign(true_magnitude) == sign(pred_magnitude)
      } else {
        NA
      }

      tibble::tibble(
        true_quarter = true_quarter,
        pred_quarter = pred_quarter,
        true_magnitude = true_magnitude,
        pred_magnitude = pred_magnitude,
        quarter_exact_match = min_distance < 0.5,  # Essentially zero
        quarter_within_1q = min_distance <= 1,
        quarter_error_q = quarter_error,
        magnitude_pct_error = magnitude_pct_error,
        sign_correct = sign_correct,
        is_matched = TRUE
      )
    } else {
      # No match found (false positive)
      tibble::tibble(
        true_quarter = NA_character_,
        pred_quarter = pred_quarter,
        true_magnitude = NA_real_,
        pred_magnitude = pred_magnitude,
        quarter_exact_match = FALSE,
        quarter_within_1q = FALSE,
        quarter_error_q = NA_real_,
        magnitude_pct_error = NA_real_,
        sign_correct = NA,
        is_matched = FALSE
      )
    }
  })

  # Find unmatched true quarters (false negatives)
  matched_true_quarters <- matched_rows %>%
    dplyr::filter(is_matched) %>%
    dplyr::pull(true_quarter)

  unmatched_true <- ground_truth %>%
    dplyr::filter(!quarter %in% matched_true_quarters) %>%
    dplyr::mutate(
      true_quarter = quarter,
      pred_quarter = NA_character_,
      true_magnitude = magnitude,
      pred_magnitude = NA_real_,
      quarter_exact_match = FALSE,
      quarter_within_1q = FALSE,
      quarter_error_q = NA_real_,
      magnitude_pct_error = NA_real_,
      sign_correct = NA,
      is_matched = FALSE
    ) %>%
    dplyr::select(
      true_quarter, pred_quarter, true_magnitude, pred_magnitude,
      quarter_exact_match, quarter_within_1q, quarter_error_q,
      magnitude_pct_error, sign_correct, is_matched
    )

  # Combine matched and unmatched
  dplyr::bind_rows(matched_rows, unmatched_true)
}


#' Create summary table of Model C evaluation metrics
#'
#' @param eval_results List from evaluate_model_c()
#'
#' @return Tibble with formatted metrics
#' @export
summarize_model_c_metrics <- function(eval_results) {
  tibble::tibble(
    metric_category = c(
      "Timing", "Timing", "Timing",
      "Magnitude", "Magnitude", "Magnitude", "Magnitude",
      "Coverage", "Coverage", "Coverage",
      "Act-Level", "Act-Level"
    ),
    metric_name = c(
      "Exact Quarter Match", "Within ±1 Quarter", "Median Error (quarters)",
      "MAPE", "RMSE (billions)", "Sign Accuracy", "Correlation",
      "Recall", "Precision", "F1 Score",
      "≥50% Quarters Correct", "Mean Act Recall"
    ),
    value = c(
      eval_results$timing_exact_match,
      eval_results$timing_1q_tolerance,
      eval_results$timing_median_error_quarters,
      eval_results$magnitude_mape,
      eval_results$magnitude_rmse,
      eval_results$magnitude_sign_accuracy,
      eval_results$magnitude_correlation,
      eval_results$recall_quarters,
      eval_results$precision_quarters,
      2 * (eval_results$recall_quarters * eval_results$precision_quarters) /
        (eval_results$recall_quarters + eval_results$precision_quarters),
      eval_results$acts_50pct_quarters_correct,
      eval_results$acts_mean_recall
    )
  ) %>%
    dplyr::mutate(
      formatted_value = dplyr::case_when(
        metric_name %in% c("RMSE (billions)", "Median Error (quarters)") ~
          sprintf("%.2f", value),
        TRUE ~ sprintf("%.1f%%", value * 100)
      )
    )
}


#' Plot Model C magnitude predictions vs ground truth
#'
#' @param eval_results List from evaluate_model_c()
#'
#' @return ggplot object
#' @export
plot_model_c_magnitudes <- function(eval_results) {

  matched_data <- eval_results$all_matches %>%
    dplyr::filter(is_matched)

  ggplot2::ggplot(matched_data, ggplot2::aes(x = true_magnitude, y = pred_magnitude)) +
    ggplot2::geom_point(alpha = 0.6, size = 2) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "red") +
    ggplot2::labs(
      title = "Model C: Predicted vs True Magnitudes (Matched Quarters)",
      subtitle = sprintf(
        "MAPE = %.1f%% | Correlation = %.3f | Sign Accuracy = %.1f%%",
        eval_results$magnitude_mape * 100,
        eval_results$magnitude_correlation,
        eval_results$magnitude_sign_accuracy * 100
      ),
      x = "True Magnitude (Billions USD)",
      y = "Predicted Magnitude (Billions USD)"
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold")
    )
}


#' Plot Model C coverage metrics by act
#'
#' @param eval_results List from evaluate_model_c()
#'
#' @return ggplot object
#' @export
plot_model_c_coverage <- function(eval_results) {

  act_metrics <- eval_results$matched_data %>%
    dplyr::mutate(
      n_true = purrr::map_int(ground_truth, nrow),
      n_pred = purrr::map_int(predictions, nrow),
      n_matched = purrr::map_int(matches, ~ sum(.x$is_matched, na.rm = TRUE)),
      recall = n_matched / n_true,
      precision = dplyr::if_else(n_pred > 0, n_matched / n_pred, NA_real_)
    )

  ggplot2::ggplot(act_metrics, ggplot2::aes(x = recall, y = precision)) +
    ggplot2::geom_point(alpha = 0.6, size = 3) +
    ggplot2::geom_hline(yintercept = 0.85, linetype = "dashed", color = "red", alpha = 0.5) +
    ggplot2::geom_vline(xintercept = 0.80, linetype = "dashed", color = "red", alpha = 0.5) +
    ggplot2::xlim(0, 1) +
    ggplot2::ylim(0, 1) +
    ggplot2::labs(
      title = "Model C: Quarter Coverage by Act",
      subtitle = sprintf(
        "Overall Recall = %.1f%% | Overall Precision = %.1f%%",
        eval_results$recall_quarters * 100,
        eval_results$precision_quarters * 100
      ),
      x = "Recall (% of true quarters extracted)",
      y = "Precision (% of predictions that match truth)"
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold")
    ) +
    ggplot2::annotate(
      "text",
      x = 0.80, y = 0.95,
      label = "Target:\nRecall ≥80%\nPrecision ≥85%",
      hjust = 0, vjust = 1, size = 3, color = "red"
    )
}
