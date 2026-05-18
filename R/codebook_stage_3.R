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
                               max_tokens = 1024,
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL,
                               country_iso = "US",
                               multi_act_chunks = NULL) {

  message(sprintf("Running S3 error analysis (country_iso = %s)...", country_iso))

  # Extract texts and labels from pre-assembled test set
  test_texts <- s3_test_set$text
  true_labels <- s3_test_set$true_label

  # Compute baseline predictions once, share across all tests.
  # baseline_details now carries a `measures` list-column under C1 v0.7.0 —
  # used by compute_overlisting_diagnostic() and
  # compute_country_distribution_diagnostic() below.
  message("  Computing baseline predictions...")
  baseline_details <- classify_batch_for_test(
    codebook, test_texts, model,
    return_details = TRUE, max_tokens = max_tokens,
    provider = provider, base_url = base_url, api_key = api_key,
    country_iso = country_iso
  )
  baseline_preds <- baseline_details$label

  # Test V: Exclusion Criteria Consistency (H&K 4-combo design)
  message("  Test V: Exclusion Criteria Consistency...")
  test_v <- test_exclusion_criteria(
    codebook, test_texts, true_labels, model,
    max_tokens = max_tokens,
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
  message(sprintf("    All combos correct: %.1f%%",
                  test_v$all_combos_correct_rate * 100))

  # Test VI: Generic Labels
  message("  Test VI: Generic Labels...")
  test_vi <- test_generic_labels(
    codebook, test_texts, true_labels, model,
    max_tokens = max_tokens,
    provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
  )
  message(sprintf("    Original accuracy: %.1f%%, Generic accuracy: %.1f%%",
                  test_vi$original_accuracy * 100,
                  test_vi$generic_accuracy * 100))
  message(sprintf("    Change rate: %.1f%%", test_vi$change_rate * 100))
  message(sprintf("    Original F1: %.3f, Generic F1: %.3f",
                  test_vi$original_f1, test_vi$generic_f1))

  # Test VII: Swapped Labels
  message("  Test VII: Swapped Labels...")
  test_vii <- test_swapped_labels(
    codebook, test_texts, true_labels, model,
    max_tokens = max_tokens,
    provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
  )
  message(sprintf("    Follows definitions: %.1f%%, Follows names: %.1f%%",
                  test_vii$follows_definitions_rate * 100,
                  test_vii$follows_names_rate * 100))
  message(sprintf("    %s", test_vii$interpretation))
  message(sprintf("    Swapped F1: %.3f", test_vii$swapped_f1))

  # Ablation Study (H&K Table 4 design)
  message("  Running ablation study...")
  ablation <- run_ablation_study(
    codebook, test_texts, true_labels, tiers = s3_test_set$tier,
    model = model, max_tokens = max_tokens,
    provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
  )

  # C1 v0.7.0 multi-measure failure-mode diagnostics
  # ----------------------------------------------------------------------
  # Over-listing: mean(length(measures)) on Tier-1 chunks; tail (>=3)
  # surfaced for manual review. Computed from baseline_details (no extra
  # API cost).
  message("  Over-listing diagnostic...")
  overlisting <- compute_overlisting_diagnostic(
    baseline_details, s3_test_set, tier_filter = 1L
  )
  message(sprintf(
    "    Tier-1 chunks: mean(len(measures)) = %.2f, max = %d, tail (>=3) = %d/%d",
    overlisting$mean_n_measures, overlisting$max_n_measures,
    overlisting$n_tail, overlisting$n_chunks
  ))

  # Country distribution: surface chunks whose measures include a non-corpus
  # country (potential comparators). Phase 0 US deployment expects ~all
  # country == country_iso; OTHER tags are surfaced for sanity check.
  message("  Country distribution diagnostic...")
  country_dist <- compute_country_distribution_diagnostic(
    baseline_details, country_iso = country_iso
  )
  message(sprintf(
    "    Measures with country == %s: %d; OTHER: %d; chunks with any OTHER: %d",
    country_iso, country_dist$n_domestic, country_dist$n_other,
    country_dist$n_chunks_with_other
  ))

  # Under-listing: API-calling. Only runs if caller supplied multi_act_chunks
  # (derived programmatically from c1_chunk_tiers' tier1 where chunk_id has
  # >=2 distinct act_name matches). Skipped here when input is absent.
  under_listing <- if (!is.null(multi_act_chunks) && nrow(multi_act_chunks) > 0L) {
    message("  Under-listing diagnostic (API-calling)...")
    test_under_listing(
      codebook, multi_act_chunks, model = model, max_tokens = max_tokens,
      provider = provider, base_url = base_url, api_key = api_key,
      country_iso = country_iso
    )
  } else {
    message("  Under-listing diagnostic: skipped (no multi_act_chunks supplied)")
    NULL
  }

  message("\nS3 error analysis complete.")

  list(
    test_v = test_v,
    test_vi = test_vi,
    test_vii = test_vii,
    ablation = ablation,
    overlisting = overlisting,
    country_distribution = country_dist,
    under_listing = under_listing,
    baseline_details = baseline_details,
    model = model,
    n_test_texts = length(test_texts),
    timestamp = Sys.time()
  )
}


#' Over-listing diagnostic: distribution of len(measures) per chunk
#'
#' C1 v0.7.0 multi-measure failure mode #1 — model fragments one named act
#' into multiple `measures[]` entries (e.g., separate entries for distinct
#' provisions of the same omnibus bill). On chunks where the gold partition
#' (Tier 1) shows exactly one labeled act per chunk, mean(len(measures))
#' substantially above 1.0 signals fragmentation.
#'
#' @param baseline_details Tibble from `classify_batch_for_test(return_details=TRUE)`
#'   with `text_id`, `label`, `measures` (list-column).
#' @param s3_test_set Tibble used to compute baseline_details, with `tier`,
#'   `chunk_id`, `doc_id` columns (row-aligned to baseline_details via text_id).
#' @param tier_filter Integer tier to restrict to (default 1L for "exactly one
#'   gold act"). Use NA_integer_ to compute across all rows.
#' @return List: mean_n_measures, p50, p90, max_n_measures, n_tail (chunks
#'   with >=3 measures), n_chunks (denominator), tail_chunk_ids (character
#'   vector for manual review).
#' @export
compute_overlisting_diagnostic <- function(baseline_details, s3_test_set,
                                           tier_filter = 1L) {
  # Row-align via text_id (baseline_details is in s3_test_set order)
  joined <- baseline_details |>
    dplyr::mutate(
      tier     = s3_test_set$tier,
      chunk_id = s3_test_set$chunk_id,
      doc_id   = s3_test_set$doc_id,
      n_measures = purrr::map_int(measures, length)
    )

  if (!is.na(tier_filter)) {
    joined <- joined |> dplyr::filter(tier == tier_filter)
  }

  # Only count rows where the model produced a measures[] array
  # (NOT_FISCAL_MEASURE has n_measures = 0 by design — exclude from
  # fragmentation count, otherwise we deflate the mean)
  joined <- joined |> dplyr::filter(label == "FISCAL_MEASURE")

  if (nrow(joined) == 0L) {
    return(list(
      mean_n_measures = NA_real_, p50 = NA_real_, p90 = NA_real_,
      max_n_measures = NA_integer_, n_tail = 0L, n_chunks = 0L,
      tail_chunk_ids = character(0)
    ))
  }

  tail_mask <- joined$n_measures >= 3L

  list(
    mean_n_measures = mean(joined$n_measures),
    p50             = stats::median(joined$n_measures),
    p90             = stats::quantile(joined$n_measures, 0.9, names = FALSE),
    max_n_measures  = max(joined$n_measures),
    n_tail          = sum(tail_mask),
    n_chunks        = nrow(joined),
    tail_chunk_ids  = paste(joined$doc_id[tail_mask],
                            joined$chunk_id[tail_mask], sep = "||")
  )
}


#' Country distribution diagnostic: per-measure country tag distribution
#'
#' C1 v0.7.0 multi-measure failure mode #3 — country misattribution. Surfaces
#' the count of per-measure country tags across baseline predictions and the
#' set of chunks containing at least one OTHER tag (potential foreign
#' comparators). For US Phase 0 this is a sanity check (expect ~all domestic);
#' for Malaysia Phase 2 the OTHER count is the comparator-filter recall
#' signal.
#'
#' @param baseline_details Tibble from `classify_batch_for_test(return_details=TRUE)`
#'   with `measures` list-column.
#' @param country_iso Character corpus country ISO code (default "US")
#' @return List: n_domestic (measures with country == country_iso), n_other
#'   (measures with country == "OTHER"), n_chunks_with_other (chunks where
#'   at least one measure tagged OTHER), other_chunk_text_ids (for manual
#'   review).
#' @export
compute_country_distribution_diagnostic <- function(baseline_details,
                                                     country_iso = "US") {
  per_chunk <- baseline_details |>
    dplyr::mutate(
      has_other = purrr::map_lgl(measures, function(ms) {
        if (length(ms) == 0L) return(FALSE)
        any(vapply(ms, function(m) identical(m$country, "OTHER"), logical(1)))
      })
    )

  all_countries <- baseline_details$measures |>
    purrr::map(function(ms) vapply(ms, function(m) m$country %||% NA_character_,
                                   character(1))) |>
    unlist()

  n_domestic <- sum(all_countries == country_iso, na.rm = TRUE)
  n_other <- sum(all_countries == "OTHER", na.rm = TRUE)

  list(
    n_domestic = n_domestic,
    n_other = n_other,
    n_chunks_with_other = sum(per_chunk$has_other),
    other_chunk_text_ids = per_chunk$text_id[per_chunk$has_other]
  )
}


#' Run ablation study on codebook components (H&K Table 4 design)
#'
#' Tests 4 ablation conditions inspired by Halterman & Keith (2025) Table 4:
#' progressively removing semantic codebook components (label definitions,
#' clarifications) and measuring metric degradation. Output instructions are
#' kept in all conditions as they are infrastructure, not semantic content.
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
                               max_tokens = 1024,
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
                                              max_tokens = max_tokens,
                                              provider = provider,
                                              base_url = base_url,
                                              api_key = api_key)
  }
  baseline_m <- calc_metrics(baseline_preds, true_labels, tiers)

  # H&K Table 4 ablation conditions (4 conditions, output_instructions always kept)
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
      condition = "no_clarifications",
      sections_removed = c("clarifications", "negative_clarifications")
    ),
    list(
      condition = "all_removed",
      sections_removed = c("label_definition", "positive_examples",
                           "negative_examples", "clarifications",
                           "negative_clarifications")
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
        max_tokens = max_tokens,
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


