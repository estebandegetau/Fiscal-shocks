# Codebook Stage 3: Error Analysis
# Generic functions reusable for C1-C4
#
# Runs H&K Tests V-VII, ablation studies, and error categorization
# using the H&K taxonomy (A-F).

#' Assemble S3 test set for error analysis
#'
#' Samples chunks for S3 behavioral tests (V-VII) and ablation study.
#' Follows the same pattern as assemble_zero_shot_test_set() for S2.
#'
#' @param c1_chunk_data List from assemble_c1_chunk_data() with tier1, tier2, negatives
#' @param n_tier1 Integer Tier 1 chunks to sample (default 10)
#' @param n_tier2 Integer Tier 2 chunks to sample (default 10)
#' @param n_negatives Integer negative chunks to sample (default 20)
#' @param seed Integer random seed (default 20251206)
#' @return Tibble with columns chunk_id, doc_id, text, tier, act_name, year,
#'   true_label, text_type — same schema as c1_s2_test_set
#' @export
assemble_s3_test_set <- function(c1_chunk_data,
                                 n_tier1 = 10,
                                 n_tier2 = 10,
                                 n_negatives = 20,
                                 seed = 20251206) {
  positive_label <- "FISCAL_MEASURE"
  negative_label <- "NOT_FISCAL_MEASURE"

  set.seed(seed)

  # Sample Tier 1
  tier1_n <- min(n_tier1, nrow(c1_chunk_data$tier1))
  tier1_set <- c1_chunk_data$tier1 |>
    dplyr::slice_sample(n = tier1_n) |>
    dplyr::select(chunk_id, doc_id, text, act_name, year) |>
    dplyr::mutate(tier = 1L, true_label = positive_label, text_type = "positive")

  # Sample Tier 2
  tier2_n <- min(n_tier2, nrow(c1_chunk_data$tier2))
  tier2_set <- c1_chunk_data$tier2 |>
    dplyr::slice_sample(n = tier2_n) |>
    dplyr::select(chunk_id, doc_id, text, act_name, year) |>
    dplyr::mutate(tier = 2L, true_label = positive_label, text_type = "positive")

  # Sample negatives
  neg_n <- min(n_negatives, nrow(c1_chunk_data$negatives))
  neg_set <- c1_chunk_data$negatives |>
    dplyr::slice_sample(n = neg_n) |>
    dplyr::select(chunk_id, doc_id, text, year) |>
    dplyr::mutate(
      act_name = NA_character_,
      tier = NA_integer_,
      true_label = negative_label,
      text_type = "negative"
    )

  test_set <- dplyr::bind_rows(tier1_set, tier2_set, neg_set) |>
    dplyr::select(chunk_id, doc_id, text, tier, act_name, year,
                  true_label, text_type)

  message(sprintf(
    "S3 test set assembled: %d Tier 1, %d Tier 2, %d negative (%d total)",
    nrow(tier1_set), nrow(tier2_set), nrow(neg_set), nrow(test_set)
  ))

  test_set
}


#' Run S3 error analysis for a codebook
#'
#' Orchestrates Tests V-VII, ablation study, and error categorization.
#' Requires S2 results and a pre-assembled S3 test set as input.
#'
#' @param codebook A validated codebook object
#' @param s2_results Tibble from run_zero_shot() (S2 results)
#' @param s3_test_set Tibble from assemble_s3_test_set()
#' @param model Character model ID (default: "claude-haiku-4-5-20251001")
#' @return List with test results, ablation, and error categorization
#' @export
run_error_analysis <- function(codebook,
                               s2_results,
                               s3_test_set,
                               model = "claude-haiku-4-5-20251001",
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL) {

  message("Running S3 error analysis...")

  # Extract texts and labels from pre-assembled test set
  test_texts <- s3_test_set$text
  true_labels <- s3_test_set$true_label

  # Test V: Exclusion Criteria Consistency (H&K 4-combo design)
  message("  Test V: Exclusion Criteria Consistency...")
  test_v <- test_exclusion_criteria(
    codebook, test_texts, true_labels, model,
    provider = provider, base_url = base_url, api_key = api_key
  )
  for (i in seq_len(nrow(test_v$combos))) {
    r <- test_v$combos[i, ]
    message(sprintf("    %s: %d/%d (%.1f%%)",
                    r$combo, r$n_correct, r$n_total, r$accuracy * 100))
  }
  message(sprintf("    Overall consistency: %.1f%%",
                  test_v$overall_consistency * 100))

  # Test VI: Generic Labels
  message("  Test VI: Generic Labels...")
  test_vi <- test_generic_labels(
    codebook, test_texts, true_labels, model,
    provider = provider, base_url = base_url, api_key = api_key
  )
  message(sprintf("    Original accuracy: %.1f%%, Generic accuracy: %.1f%%",
                  test_vi$original_accuracy * 100,
                  test_vi$generic_accuracy * 100))
  message(sprintf("    Change rate: %.1f%%", test_vi$change_rate * 100))

  # Test VII: Swapped Labels
  message("  Test VII: Swapped Labels...")
  test_vii <- test_swapped_labels(
    codebook, test_texts, true_labels, model,
    provider = provider, base_url = base_url, api_key = api_key
  )
  message(sprintf("    Follows definitions: %.1f%%, Follows names: %.1f%%",
                  test_vii$follows_definitions_rate * 100,
                  test_vii$follows_names_rate * 100))
  message(sprintf("    %s", test_vii$interpretation))

  # Ablation Study
  message("  Running ablation study...")
  ablation <- run_ablation_study(
    codebook, test_texts, true_labels, model,
    provider = provider, base_url = base_url, api_key = api_key
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
    n_test_texts = length(test_texts),
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
                               model = "claude-haiku-4-5-20251001",
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL) {
  # Baseline
  baseline_preds <- classify_batch_for_test(codebook, test_texts, model,
                                            provider = provider,
                                            base_url = base_url,
                                            api_key = api_key)
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
        codebook, test_texts, model, system_prompt = ablated_prompt,
        provider = provider, base_url = base_url, api_key = api_key
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
        codebook, test_texts, model, system_prompt = ablated_prompt,
        provider = provider, base_url = base_url, api_key = api_key
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
#' @param s2_results Tibble from run_zero_shot()
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
