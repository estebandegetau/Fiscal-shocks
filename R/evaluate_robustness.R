# Track 2 Robustness Evaluation for Model B
# Evaluates Model B performance on Model A extracted passages vs human-curated passages
#
# Purpose: Measure the "robustness gap" between validation performance on clean
# human-curated passages (Track 1) and production performance on Model A extracted
# passages (Track 2). This gap informs deployment readiness for Phase 1.

#' Evaluate Model B robustness on extracted passages
#'
#' Matches extracted acts to ground truth, runs Model B, compares to labels.
#' This measures Model B performance under production conditions where it receives
#' passages from Model A extraction rather than human-curated passages.
#'
#' @param grouped_acts Tibble from group_extracted_passages() with columns:
#'   act_name, year, passages_text, page_numbers, source_docs, n_chunks,
#'   avg_confidence, avg_agreement_rate
#' @param aligned_data Tibble with ground truth (motivation, exogenous) from
#'   align_labels_shocks()
#' @param model Claude model ID (default "claude-sonnet-4-20250514")
#' @param match_threshold Fuzzy match threshold (default 0.85)
#' @param use_self_consistency Logical, use self-consistency sampling (default TRUE)
#' @param n_samples Integer number of samples for self-consistency (default 5)
#' @param temperature Numeric sampling temperature (default 0.7)
#' @param show_progress Logical, show progress bar (default TRUE)
#'
#' @return List with:
#'   - matched_acts: Tibble of acts successfully matched to ground truth
#'   - unmatched_acts: Tibble of extracted acts without ground truth
#'   - predictions: Model B predictions on matched acts
#'   - evaluation: evaluate_model_b() style results
#'   - robustness_summary: Comparison metrics and recommendations
#' @export
evaluate_model_b_robustness <- function(
    grouped_acts,
    aligned_data,
    model = "claude-sonnet-4-20250514",
    match_threshold = 0.85,
    use_self_consistency = TRUE,
    n_samples = 5,
    temperature = 0.7,
    show_progress = TRUE
) {

  message("=" |> rep(60) |> paste(collapse = ""))
  message("Track 2 Robustness Evaluation: Model B on Extracted Passages")
  message("=" |> rep(60) |> paste(collapse = ""))


  # Step 1: Match extracted acts to known acts with ground truth
  message("\nStep 1: Matching extracted acts to ground truth...")

  known_acts <- aligned_data |>
    dplyr::select(act_name, year, motivation = motivation_category, exogenous) |>
    dplyr::distinct()

  matches <- match_act_names(
    grouped_acts = grouped_acts,
    known_acts = known_acts,
    match_threshold = match_threshold
  )

  # Split into matched and unmatched
  matched_acts <- matches |>
    dplyr::filter(match_type != "unmatched") |>
    dplyr::left_join(
      grouped_acts,
      by = c("extracted_name" = "act_name", "extracted_year" = "year")
    ) |>
    dplyr::left_join(
      known_acts,
      by = c("known_name" = "act_name", "known_year" = "year")
    )

  unmatched_acts <- matches |>
    dplyr::filter(match_type == "unmatched") |>
    dplyr::left_join(
      grouped_acts,
      by = c("extracted_name" = "act_name", "extracted_year" = "year")
    )

  n_matched <- nrow(matched_acts)
  n_unmatched <- nrow(unmatched_acts)
  n_known <- nrow(known_acts)

  message(sprintf("  Matched: %d/%d extracted acts (%.1f%%)",
                  n_matched, n_matched + n_unmatched,
                  100 * n_matched / (n_matched + n_unmatched)))
  message(sprintf("  Coverage of known acts: %d/%d (%.1f%%)",
                  n_matched, n_known, 100 * n_matched / n_known))

  if (n_matched == 0) {
    warning("No extracted acts matched to ground truth. Cannot evaluate robustness.")
    return(list(
      matched_acts = matched_acts,
      unmatched_acts = unmatched_acts,
      predictions = NULL,
      evaluation = NULL,
      robustness_summary = tibble::tibble(
        metric = "match_rate",
        value = 0,
        note = "No matches found"
      )
    ))
  }

  # Step 2: Run Model B classification on matched extracted passages
  message("\nStep 2: Running Model B on extracted passages...")

  predictions_raw <- model_b_classify_motivation_batch(
    act_names = matched_acts$extracted_name,
    passages_texts = matched_acts$passages_text,
    years = matched_acts$extracted_year,
    model = model,
    show_progress = show_progress,
    use_self_consistency = use_self_consistency,
    n_samples = n_samples,
    temperature = temperature
  )

  # Combine predictions with ground truth
  predictions <- matched_acts |>
    dplyr::bind_cols(
      predictions_raw |>
        dplyr::rename(
          pred_motivation = motivation,
          pred_exogenous = exogenous,
          pred_confidence = confidence,
          pred_agreement_rate = agreement_rate,
          pred_reasoning = reasoning,
          pred_evidence = evidence
        )
    ) |>
    dplyr::mutate(
      true_motivation = motivation,
      true_exogenous = exogenous,
      correct = (pred_motivation == true_motivation),
      exogenous_correct = (pred_exogenous == true_exogenous)
    )

  # Step 3: Compute evaluation metrics
  message("\nStep 3: Computing evaluation metrics...")

  evaluation <- evaluate_model_b(
    predictions = predictions |>
      dplyr::select(pred_motivation, pred_exogenous, pred_confidence),
    true_motivation = predictions$true_motivation,
    true_exogenous = predictions$true_exogenous
  )

  # Step 4: Build robustness summary
  message("\nStep 4: Building robustness summary...")

  robustness_summary <- tibble::tibble(
    metric = c(
      "n_extracted_acts",
      "n_matched_acts",
      "n_unmatched_acts",
      "match_rate",
      "coverage_rate",
      "track2_accuracy",
      "track2_macro_f1",
      "track2_exogenous_accuracy"
    ),
    value = c(
      nrow(grouped_acts),
      n_matched,
      n_unmatched,
      n_matched / (n_matched + n_unmatched),
      n_matched / n_known,
      evaluation$accuracy,
      evaluation$macro_f1,
      evaluation$exogenous_accuracy
    )
  )

  message("\n" |> paste0(rep("=", 60) |> paste(collapse = "")))
  message("Track 2 Results:")
  message(sprintf("  Accuracy:          %.1f%%", evaluation$accuracy * 100))
  message(sprintf("  Macro F1:          %.3f", evaluation$macro_f1))
  message(sprintf("  Exogenous Acc:     %.1f%%", evaluation$exogenous_accuracy * 100))
  message(rep("=", 60) |> paste(collapse = ""))

  list(
    matched_acts = matched_acts,
    unmatched_acts = unmatched_acts,
    predictions = predictions,
    evaluation = evaluation,
    robustness_summary = robustness_summary
  )
}


#' Compare Track 1 and Track 2 evaluation results
#'
#' Computes the robustness gap between evaluation on human-curated passages
#' (Track 1) and evaluation on Model A extracted passages (Track 2).
#'
#' @param track1_eval Results from model_b_loocv_eval or evaluate_model_b()
#'   Must have: accuracy, macro_f1, exogenous_accuracy, per_class_metrics
#' @param track2_eval Results from evaluate_model_b_robustness()
#'   Uses the $evaluation component
#'
#' @return List with:
#'   - comparison: Tibble with side-by-side metrics
#'   - gaps: Tibble with absolute and percentage gaps
#'   - per_class_comparison: Per-class F1 degradation
#'   - recommendation: Character string (proceed/investigate/block)
#'   - recommendation_reason: Explanation of recommendation
#' @export
compare_evaluation_tracks <- function(track1_eval, track2_eval) {

  # Extract Track 2 evaluation (it's nested in the robustness results)
  track2 <- if ("evaluation" %in% names(track2_eval)) {
    track2_eval$evaluation
  } else {
    track2_eval
  }

  # Handle LOOCV vs standard evaluation format differences
  track1_accuracy <- track1_eval$accuracy
  track1_macro_f1 <- track1_eval$macro_f1
  track1_exog_acc <- track1_eval$exogenous_accuracy

  track2_accuracy <- track2$accuracy
  track2_macro_f1 <- track2$macro_f1
  track2_exog_acc <- track2$exogenous_accuracy

  # Build comparison table
  comparison <- tibble::tibble(
    metric = c("Accuracy", "Macro F1", "Exogenous Accuracy"),
    track1 = c(track1_accuracy, track1_macro_f1, track1_exog_acc),
    track2 = c(track2_accuracy, track2_macro_f1, track2_exog_acc),
    gap_absolute = track2 - track1,
    gap_percent = 100 * (track2 - track1) / track1
  )

  # Per-class F1 comparison
  track1_classes <- track1_eval$per_class_metrics
  track2_classes <- track2$per_class_metrics

  per_class_comparison <- track1_classes |>
    dplyr::select(class, track1_f1 = f1_score) |>
    dplyr::left_join(
      track2_classes |> dplyr::select(class, track2_f1 = f1_score),
      by = "class"
    ) |>
    dplyr::mutate(
      gap_absolute = track2_f1 - track1_f1,
      gap_percent = 100 * (track2_f1 - track1_f1) / track1_f1
    )

  # Compute overall robustness gap (average of accuracy and macro-F1 gaps)
  accuracy_gap <- track2_accuracy - track1_accuracy
  macro_f1_gap <- track2_macro_f1 - track1_macro_f1

  # Determine recommendation based on gap thresholds
  # Gap <= 5%: Proceed
  # Gap 5-10%: Investigate
  # Gap > 10%: Block
  worst_gap <- min(accuracy_gap, macro_f1_gap)  # Most negative gap


  if (worst_gap >= -0.05) {
    recommendation <- "PROCEED"
    recommendation_reason <- sprintf(
      "Robustness gap (%.1f%% accuracy, %.1f%% F1) is within acceptable threshold (<=5%%). Model B is ready for Phase 1 deployment.",
      accuracy_gap * 100, macro_f1_gap * 100
    )
  } else if (worst_gap >= -0.10) {
    recommendation <- "INVESTIGATE"
    recommendation_reason <- sprintf(
      "Robustness gap (%.1f%% accuracy, %.1f%% F1) exceeds 5%% threshold. Review error patterns before Phase 1 deployment. Check which act types or extraction issues cause degradation.",
      accuracy_gap * 100, macro_f1_gap * 100
    )
  } else {
    recommendation <- "BLOCK"
    recommendation_reason <- sprintf(
      "Robustness gap (%.1f%% accuracy, %.1f%% F1) exceeds 10%% threshold. Model A extraction quality may be insufficient. Improve Model A before Phase 1 deployment.",
      accuracy_gap * 100, macro_f1_gap * 100
    )
  }

  # Include match coverage in recommendation if available
  if ("robustness_summary" %in% names(track2_eval)) {
    summary <- track2_eval$robustness_summary
    coverage <- summary$value[summary$metric == "coverage_rate"]
    if (length(coverage) > 0 && coverage < 0.80) {
      recommendation_reason <- paste0(
        recommendation_reason,
        sprintf("\n\nWARNING: Model A coverage is only %.1f%% of known acts. Consider improving extraction recall.",
                coverage * 100)
      )
    }
  }

  list(
    comparison = comparison,
    gaps = tibble::tibble(
      accuracy_gap = accuracy_gap,
      macro_f1_gap = macro_f1_gap,
      worst_gap = worst_gap
    ),
    per_class_comparison = per_class_comparison,
    recommendation = recommendation,
    recommendation_reason = recommendation_reason
  )
}


#' Print robustness comparison report
#'
#' Formats and prints the comparison between Track 1 and Track 2 evaluations.
#'
#' @param comparison Results from compare_evaluation_tracks()
#' @param track2_eval Full results from evaluate_model_b_robustness() (optional,
#'   for additional context like unmatched acts)
#' @export
print_robustness_report <- function(comparison, track2_eval = NULL) {

  cat(rep("=", 70), "\n", sep = "")
  cat("Model B Robustness Report: Track 1 vs Track 2\n")
  cat(rep("=", 70), "\n\n", sep = "")

  cat("Overall Metrics Comparison:\n")
  cat(rep("-", 50), "\n", sep = "")
  cat(sprintf("%-20s %10s %10s %10s\n",
              "Metric", "Track 1", "Track 2", "Gap"))
  cat(rep("-", 50), "\n", sep = "")

  for (i in seq_len(nrow(comparison$comparison))) {
    row <- comparison$comparison[i, ]
    cat(sprintf("%-20s %9.1f%% %9.1f%% %+9.1f%%\n",
                row$metric,
                row$track1 * 100,
                row$track2 * 100,
                row$gap_absolute * 100))
  }
  cat(rep("-", 50), "\n\n", sep = "")

  cat("Per-Class F1 Degradation:\n")
  cat(rep("-", 50), "\n", sep = "")
  cat(sprintf("%-20s %10s %10s %10s\n",
              "Class", "Track 1", "Track 2", "Gap"))
  cat(rep("-", 50), "\n", sep = "")

  for (i in seq_len(nrow(comparison$per_class_comparison))) {
    row <- comparison$per_class_comparison[i, ]
    t1 <- if (is.na(row$track1_f1)) "N/A" else sprintf("%.2f", row$track1_f1)
    t2 <- if (is.na(row$track2_f1)) "N/A" else sprintf("%.2f", row$track2_f1)
    gap <- if (is.na(row$gap_absolute)) "N/A" else sprintf("%+.2f", row$gap_absolute)
    cat(sprintf("%-20s %10s %10s %10s\n", row$class, t1, t2, gap))
  }
  cat(rep("-", 50), "\n\n", sep = "")

  # Match statistics if available
  if (!is.null(track2_eval) && "robustness_summary" %in% names(track2_eval)) {
    summary <- track2_eval$robustness_summary
    n_extracted <- summary$value[summary$metric == "n_extracted_acts"]
    n_matched <- summary$value[summary$metric == "n_matched_acts"]
    n_unmatched <- summary$value[summary$metric == "n_unmatched_acts"]
    coverage <- summary$value[summary$metric == "coverage_rate"]

    cat("Match Statistics:\n")
    cat(sprintf("  Extracted acts:    %d\n", n_extracted))
    cat(sprintf("  Matched to truth:  %d (%.1f%%)\n",
                n_matched, 100 * n_matched / n_extracted))
    cat(sprintf("  Unmatched:         %d\n", n_unmatched))
    cat(sprintf("  Coverage of known: %.1f%%\n\n", coverage * 100))
  }

  cat(rep("=", 70), "\n", sep = "")
  cat(sprintf("RECOMMENDATION: %s\n", comparison$recommendation))
  cat(rep("=", 70), "\n", sep = "")
  cat(comparison$recommendation_reason, "\n")

  invisible(comparison)
}
