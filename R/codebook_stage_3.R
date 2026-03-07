# Codebook Stage 3: Error Analysis
# Generic functions reusable for C1-C4
#
# Runs H&K Tests V-VII and ablation studies.

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
#' Orchestrates Tests V-VII and ablation study.
#'
#' @param codebook A validated codebook object
#' @param s3_test_set Tibble from assemble_s3_test_set()
#' @param model Character model ID (default: "claude-haiku-4-5-20251001")
#' @return List with test results, ablation, and error categorization
#' @export
run_error_analysis <- function(codebook,
                               s3_test_set,
                               model = "claude-haiku-4-5-20251001",
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL) {

  message("Running S3 error analysis...")

  # Extract texts and labels from pre-assembled test set
  test_texts <- s3_test_set$text
  true_labels <- s3_test_set$true_label

  # Compute baseline predictions once, share across all tests
  message("  Computing baseline predictions...")
  baseline_preds <- classify_batch_for_test(
    codebook, test_texts, model,
    provider = provider, base_url = base_url, api_key = api_key
  )

  # Test V: Exclusion Criteria Consistency (H&K 4-combo design)
  message("  Test V: Exclusion Criteria Consistency...")
  test_v <- test_exclusion_criteria(
    codebook, test_texts, true_labels, model,
    provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
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
    provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
  )
  message(sprintf("    Original accuracy: %.1f%%, Generic accuracy: %.1f%%",
                  test_vi$original_accuracy * 100,
                  test_vi$generic_accuracy * 100))
  message(sprintf("    Change rate: %.1f%%", test_vi$change_rate * 100))

  # Test VII: Swapped Labels
  message("  Test VII: Swapped Labels...")
  test_vii <- test_swapped_labels(
    codebook, test_texts, true_labels, model,
    provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
  )
  message(sprintf("    Follows definitions: %.1f%%, Follows names: %.1f%%",
                  test_vii$follows_definitions_rate * 100,
                  test_vii$follows_names_rate * 100))
  message(sprintf("    %s", test_vii$interpretation))

  # Ablation Study (H&K Table 4 design)
  message("  Running ablation study...")
  ablation <- run_ablation_study(
    codebook, test_texts, true_labels, tiers = s3_test_set$tier,
    model = model, provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
  )

  message("\nS3 error analysis complete.")

  list(
    test_v = test_v,
    test_vi = test_vi,
    test_vii = test_vii,
    ablation = ablation,
    model = model,
    n_test_texts = length(test_texts),
    timestamp = Sys.time()
  )
}


#' Run ablation study on codebook components (H&K Table 4 design)
#'
#' Tests 6 ablation conditions matching Halterman & Keith (2025) Table 4:
#' progressively removing component types (label definitions, examples,
#' clarifications, output instructions) and measuring metric degradation.
#'
#' @param codebook A validated codebook object
#' @param test_texts Character vector of test passages
#' @param true_labels Character vector of true labels
#' @param tiers Integer vector of tier assignments (1, 2, or NA for negatives),
#'   same length as test_texts. Used to compute tier-stratified recall.
#' @param model Character model ID
#' @param provider Character API provider
#' @param base_url Optional base URL for API
#' @param api_key Optional API key
#' @param baseline_preds Optional character vector of pre-computed baseline
#'   predictions. If NULL, computes baseline internally.
#' @return Tibble with per-condition metrics and drops. One row per ablation
#'   condition, sorted by f1_drop descending.
#' @export
run_ablation_study <- function(codebook,
                               test_texts,
                               true_labels,
                               tiers = NULL,
                               model = "claude-haiku-4-5-20251001",
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL,
                               baseline_preds = NULL) {

  labels <- unique(true_labels)

  # Local helper: compute full metrics from prediction vectors
  calc_metrics <- function(preds, true_labels, tiers) {
    results_tbl <- tibble::tibble(true_label = true_labels, pred_label = preds)
    m <- compute_binary_metrics(results_tbl, labels)
    positive_label <- labels[1]

    t1r <- if (!is.null(tiers) && any(tiers == 1, na.rm = TRUE)) {
      mean(preds[tiers == 1] == positive_label, na.rm = TRUE)
    } else {
      NA_real_
    }
    t2r <- if (!is.null(tiers) && any(tiers == 2, na.rm = TRUE)) {
      mean(preds[tiers == 2] == positive_label, na.rm = TRUE)
    } else {
      NA_real_
    }

    list(accuracy = m$accuracy, precision = m$precision, recall = m$recall,
         f1 = m$f1, tier1_recall = t1r, tier2_recall = t2r)
  }

  # Baseline (reuse cached predictions if available)
  if (is.null(baseline_preds)) {
    baseline_preds <- classify_batch_for_test(codebook, test_texts, model,
                                              provider = provider,
                                              base_url = base_url,
                                              api_key = api_key)
  }
  baseline_m <- calc_metrics(baseline_preds, true_labels, tiers)

  # H&K Table 4 ablation conditions
  conditions <- list(
    list(
      condition = "full",
      sections_removed = character(0)
    ),
    list(
      condition = "no_label_def",
      sections_removed = "label_definition"
    ),
    list(
      condition = "no_examples",
      sections_removed = c("positive_examples", "negative_examples")
    ),
    list(
      condition = "no_examples_no_clarifications",
      sections_removed = c("positive_examples", "negative_examples",
                           "clarifications", "negative_clarifications")
    ),
    list(
      condition = "no_output_no_examples_no_neg_clar",
      sections_removed = c("output_instructions", "positive_examples",
                           "negative_examples", "negative_clarifications")
    ),
    list(
      condition = "all_removed",
      sections_removed = c("label_definition", "output_instructions",
                           "positive_examples", "negative_examples",
                           "clarifications", "negative_clarifications")
    )
  )

  results <- purrr::map(conditions, function(cond) {
    if (length(cond$sections_removed) == 0) {
      # Full baseline — reuse cached predictions
      abl_m <- baseline_m
    } else {
      ablated_prompt <- construct_codebook_prompt(
        codebook, exclude_sections = cond$sections_removed
      )
      ablated_preds <- classify_batch_for_test(
        codebook, test_texts, model, system_prompt = ablated_prompt,
        provider = provider, base_url = base_url, api_key = api_key
      )
      abl_m <- calc_metrics(ablated_preds, true_labels, tiers)
    }

    tibble::tibble(
      condition = cond$condition,
      sections_removed = paste(cond$sections_removed, collapse = ", "),
      accuracy = abl_m$accuracy,
      precision = abl_m$precision,
      recall = abl_m$recall,
      f1 = abl_m$f1,
      tier1_recall = abl_m$tier1_recall,
      tier2_recall = abl_m$tier2_recall,
      accuracy_drop = baseline_m$accuracy - abl_m$accuracy,
      precision_drop = baseline_m$precision - abl_m$precision,
      recall_drop = baseline_m$recall - abl_m$recall,
      f1_drop = baseline_m$f1 - abl_m$f1,
      tier1_recall_drop = baseline_m$tier1_recall - abl_m$tier1_recall,
      tier2_recall_drop = baseline_m$tier2_recall - abl_m$tier2_recall
    )
  })

  ablation_results <- dplyr::bind_rows(results)

  # Log summary (skip baseline row for max drop)
  ablated_rows <- ablation_results |> dplyr::filter(condition != "full")
  message(sprintf(
    "  Ablation: %d conditions tested. Max F1 drop: %.1f%%, Max recall drop: %.1f%%",
    nrow(ablated_rows),
    max(ablated_rows$f1_drop, na.rm = TRUE) * 100,
    max(ablated_rows$recall_drop, na.rm = TRUE) * 100
  ))

  ablation_results
}


