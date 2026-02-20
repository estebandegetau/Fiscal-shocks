# Codebook Stage 3: Error Analysis
# Generic functions reusable for C1-C4
#
# Runs H&K Tests V-VII, ablation studies, and error categorization
# using the H&K taxonomy (A-F).

#' Run S3 error analysis for a codebook
#'
#' Orchestrates Tests V-VII, ablation study, and error categorization.
#' Requires S2 LOOCV results as input.
#'
#' @param codebook A validated codebook object
#' @param s2_results Tibble from run_loocv() (S2 results)
#' @param aligned_data Tibble with aligned labels
#' @param c1_chunk_data List from prepare_c1_chunk_data() with tier1, tier2, negatives
#' @param model Character model ID (default: "claude-haiku-4-5-20251001")
#' @param n_ablation_texts Integer texts for ablation study (default 40)
#' @param seed Integer random seed (default 20251206)
#' @return List with test results, ablation, and error categorization
#' @export
run_error_analysis <- function(codebook,
                               s2_results,
                               aligned_data,
                               c1_chunk_data,
                               model = "claude-haiku-4-5-20251001",
                               n_ablation_texts = 40,
                               seed = 20251206) {
  set.seed(seed)

  message("Running S3 error analysis...")

  # Build balanced test set from chunk tier data
  # Use Tier 1+2 chunks as positives, negative chunks as negatives
  pos_pool <- dplyr::bind_rows(c1_chunk_data$tier1, c1_chunk_data$tier2)
  neg_pool <- c1_chunk_data$negatives

  pos_texts <- pos_pool |>
    dplyr::slice_sample(n = min(n_ablation_texts / 2, nrow(pos_pool)))

  neg_texts <- neg_pool |>
    dplyr::slice_sample(n = min(n_ablation_texts / 2, nrow(neg_pool)))

  ablation_texts <- c(pos_texts$text, neg_texts$text)
  valid_labels <- get_valid_labels(codebook)
  ablation_labels <- c(
    rep(valid_labels[1], nrow(pos_texts)),
    rep(valid_labels[length(valid_labels)], nrow(neg_texts))
  )

  # Test V: Exclusion Criteria
  message("  Test V: Exclusion Criteria...")
  test_v <- test_exclusion_criteria(
    codebook, ablation_texts, ablation_labels, model
  )
  message(sprintf("    Baseline accuracy: %.1f%%", test_v$baseline_accuracy * 100))
  for (i in seq_len(nrow(test_v$results))) {
    r <- test_v$results[i, ]
    message(sprintf("    Remove %s.%s: %.1f%% -> %.1f%% (drop: %.1f%%)",
                    r$class, r$component,
                    r$baseline_accuracy * 100,
                    r$ablated_accuracy * 100,
                    r$accuracy_drop * 100))
  }

  # Test VI: Generic Labels
  message("  Test VI: Generic Labels...")
  test_vi <- test_generic_labels(
    codebook, ablation_texts, ablation_labels, model
  )
  message(sprintf("    Original accuracy: %.1f%%, Generic accuracy: %.1f%%",
                  test_vi$original_accuracy * 100,
                  test_vi$generic_accuracy * 100))
  message(sprintf("    Change rate: %.1f%%", test_vi$change_rate * 100))

  # Test VII: Swapped Labels
  message("  Test VII: Swapped Labels...")
  test_vii <- test_swapped_labels(
    codebook, ablation_texts, ablation_labels, model
  )
  message(sprintf("    Follows definitions: %.1f%%, Follows names: %.1f%%",
                  test_vii$follows_definitions_rate * 100,
                  test_vii$follows_names_rate * 100))
  message(sprintf("    %s", test_vii$interpretation))

  # Ablation Study
  message("  Running ablation study...")
  ablation <- run_ablation_study(
    codebook, ablation_texts, ablation_labels, model
  )

  # Error Categorization (H&K taxonomy)
  message("  Categorizing errors...")
  error_categories <- categorize_errors_hk(s2_results)

  message("\nS3 error analysis complete.")

  list(
    test_v = test_v,
    test_vi = test_vi,
    test_vii = test_vii,
    ablation = ablation,
    error_categories = error_categories,
    model = model,
    n_ablation_texts = length(ablation_texts),
    seed = seed,
    timestamp = Sys.time()
  )
}


#' Run ablation study on codebook components
#'
#' Removes each clarification and negative_clarification one at a time,
#' re-classifies test texts, and measures accuracy change.
#'
#' @param codebook A validated codebook object
#' @param test_texts Character vector of test passages
#' @param true_labels Character vector of true labels
#' @param model Character model ID
#' @return Tibble with component, baseline_accuracy, ablated_accuracy, accuracy_drop
#' @export
run_ablation_study <- function(codebook,
                               test_texts,
                               true_labels,
                               model = "claude-haiku-4-5-20251001") {
  # Baseline
  baseline_preds <- classify_batch_for_test(codebook, test_texts, model)
  baseline_acc <- mean(baseline_preds == true_labels, na.rm = TRUE)

  results <- list()

  for (cls in codebook$classes) {
    # Ablate each clarification
    for (j in seq_along(cls$clarification)) {
      exclude <- stats::setNames(
        list(paste0("clarification_", j)),
        cls$label
      )
      ablated_prompt <- construct_codebook_prompt(
        codebook, exclude_components = exclude
      )
      ablated_preds <- classify_batch_for_test(
        codebook, test_texts, model, system_prompt = ablated_prompt
      )
      ablated_acc <- mean(ablated_preds == true_labels, na.rm = TRUE)

      results[[length(results) + 1]] <- tibble::tibble(
        class = cls$label,
        component_type = "clarification",
        component_idx = j,
        component_text = cls$clarification[[j]],
        baseline_accuracy = baseline_acc,
        ablated_accuracy = ablated_acc,
        accuracy_drop = baseline_acc - ablated_acc
      )
    }

    # Ablate each negative_clarification
    for (j in seq_along(cls$negative_clarification)) {
      exclude <- stats::setNames(
        list(paste0("negative_clarification_", j)),
        cls$label
      )
      ablated_prompt <- construct_codebook_prompt(
        codebook, exclude_components = exclude
      )
      ablated_preds <- classify_batch_for_test(
        codebook, test_texts, model, system_prompt = ablated_prompt
      )
      ablated_acc <- mean(ablated_preds == true_labels, na.rm = TRUE)

      results[[length(results) + 1]] <- tibble::tibble(
        class = cls$label,
        component_type = "negative_clarification",
        component_idx = j,
        component_text = cls$negative_clarification[[j]],
        baseline_accuracy = baseline_acc,
        ablated_accuracy = ablated_acc,
        accuracy_drop = baseline_acc - ablated_acc
      )
    }
  }

  ablation_results <- dplyr::bind_rows(results) |>
    dplyr::arrange(dplyr::desc(accuracy_drop))

  message(sprintf("  Ablation: %d components tested. Max drop: %.1f%%",
                  nrow(ablation_results),
                  max(ablation_results$accuracy_drop, na.rm = TRUE) * 100))

  ablation_results
}


#' Categorize errors using H&K taxonomy
#'
#' Classifies each error from S2 LOOCV into H&K error categories:
#' - A: Correct (agreement)
#' - B: Incorrect ground truth (label error in training data)
#' - C: Document error (extraction/OCR artifact)
#' - D: Non-compliance (invalid output format)
#' - E: Semantics/reasoning error (model misunderstanding)
#' - F: Ambiguous (genuinely debatable case)
#'
#' Uses heuristics for automatic categorization; manual review recommended.
#'
#' @param s2_results Tibble from run_loocv()
#' @return Tibble with error categorization
#' @export
categorize_errors_hk <- function(s2_results) {
  errors <- s2_results |>
    dplyr::filter(!correct)

  if (nrow(errors) == 0) {
    message("No errors to categorize.")
    return(tibble::tibble(
      fold = integer(), act_name = character(), text_type = character(),
      true_label = character(), pred_label = character(),
      error_category = character(), category_reasoning = character()
    ))
  }

  categorized <- errors |>
    dplyr::mutate(
      error_category = dplyr::case_when(
        # D: Non-compliance — NA predictions (parsing failures)
        is.na(pred_label) ~ "D_non_compliance",

        # C: Document error — NA reasoning or very short with no confidence
        is.na(reasoning) | (nchar(reasoning) < 10 & is.na(confidence)) ~ "C_document_error",

        # E: Semantics/reasoning — model returned valid but wrong label
        # This is the default for well-formed but incorrect predictions
        !is.na(pred_label) & pred_label != true_label ~ "E_semantics_reasoning",

        # Fallback
        TRUE ~ "F_ambiguous"
      ),
      category_reasoning = dplyr::case_when(
        error_category == "D_non_compliance" ~
          "Model failed to return valid JSON or valid label",
        error_category == "C_document_error" ~
          "Possible extraction artifact or insufficient text",
        error_category == "E_semantics_reasoning" ~
          "Model returned valid label but misclassified the passage",
        error_category == "F_ambiguous" ~
          "Requires manual review to determine error source",
        TRUE ~ NA_character_
      )
    )

  # Summary
  cat_summary <- categorized |>
    dplyr::count(error_category) |>
    dplyr::mutate(pct = round(n / sum(n) * 100, 1))

  message("Error category distribution:")
  for (i in seq_len(nrow(cat_summary))) {
    message(sprintf("  %s: %d (%.1f%%)",
                    cat_summary$error_category[i],
                    cat_summary$n[i],
                    cat_summary$pct[i]))
  }

  categorized |>
    dplyr::select(
      fold, act_name, year, text_type,
      true_label, pred_label, confidence, reasoning,
      error_category, category_reasoning
    )
}
