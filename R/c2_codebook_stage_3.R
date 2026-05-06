# C2 S3: Error Analysis for Motivation Classification
#
# Implements H&K Tests V-VII and ablation study for C2b (motivation
# classification). Uses cached C2a evidence from c2_s2_results as input;
# only re-runs C2b with modified codebooks.
#
# Parallels R/codebook_stage_3.R but does NOT modify it.
# Reuses: construct_codebook_prompt(), get_valid_labels() from R/codebook_stage_0.R
#         call_codebook_generic() from R/codebook_stage_0.R
#         format_c2b_input(), validate_c2b_output() from R/c2_behavioral_tests.R
#         compute_multiclass_metrics() from R/c2_codebook_stage_2.R

# Null coalescing (guard against missing definition)
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b


# =============================================================================
# Core Helper: C2b Batch Classification
# =============================================================================

#' Classify a batch of acts using C2b with pre-extracted evidence
#'
#' Analogous to classify_batch_for_test() but for C2b's structured I/O.
#' Takes pre-extracted C2a evidence bundles and runs C2b classification.
#'
#' @param c2b_codebook Parsed C2b codebook
#' @param acts_evidence Tibble with act_name, year, evidence (list-col),
#'   enacted_signals (list-col)
#' @param model Character model ID
#' @param system_prompt Optional override system prompt (for ablation)
#' @param max_tokens Integer max output tokens (default 1024)
#' @param max_retries Integer retries on validation failure (default 1)
#' @param provider Character API provider
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return Character vector of predicted motivation labels (one per act)
#' @export
classify_c2b_batch <- function(c2b_codebook,
                               acts_evidence,
                               model = "claude-haiku-4-5-20251001",
                               system_prompt = NULL,
                               max_tokens = 1024,
                               max_retries = 1,
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL) {

  if (is.null(system_prompt)) {
    system_prompt <- construct_codebook_prompt(c2b_codebook)
  }
  c2b_labels <- get_valid_labels(c2b_codebook)
  n_acts <- nrow(acts_evidence)

  preds <- vapply(seq_len(n_acts), function(i) {
    act <- acts_evidence[i, ]

    timing_input <- if ("timing_signals" %in% names(act)) {
      act$timing_signals[[1]] %||% list()
    } else {
      list()
    }
    user_msg <- format_c2b_input(
      act_name = act$act_name,
      year = act$year,
      evidence = act$evidence[[1]],
      enacted_signals = act$enacted_signals[[1]],
      timing_signals = timing_input
    )

    parsed <- NULL
    valid <- FALSE

    for (attempt in seq_len(1 + max_retries)) {
      result <- tryCatch({
        p <- call_codebook_generic(
          user_message = user_msg,
          codebook = c2b_codebook,
          model = model,
          system_prompt = system_prompt,
          max_tokens = max_tokens,
          temperature = 0,
          provider = provider,
          base_url = base_url,
          api_key = api_key
        )
        v <- validate_c2b_output(p, c2b_labels)
        list(parsed = p, valid = v$valid, reason = v$reason)
      }, error = function(e) {
        list(parsed = NULL, valid = FALSE, reason = e$message)
      })

      if (result$valid) {
        parsed <- result$parsed
        valid <- TRUE
        break
      }
    }

    if (!valid || is.null(parsed)) {
      return(NA_character_)
    }

    parsed$label
  }, character(1))

  preds
}


# =============================================================================
# Test V: Exclusion Criteria Consistency (H&K 4-combo design)
# =============================================================================

#' Test V: Exclusion Criteria Consistency for C2b
#'
#' Tests whether C2b correctly follows exclusion criteria using four
#' conditions: (normal/modified evidence) x (normal/modified codebook).
#'
#' Modified evidence: injects a distractor evidence record about elephants.
#' Modified codebook: adds negative_clarification to all non-LONG_RUN classes
#' saying "does not apply if evidence mentions elephants", forcing LONG_RUN.
#'
#' Combo 1: Normal evidence + Normal codebook -> baseline predictions
#' Combo 2: Modified evidence + Normal codebook -> baseline predictions
#' Combo 3: Normal evidence + Modified codebook -> baseline predictions
#' Combo 4: Modified evidence + Modified codebook -> all LONG_RUN
#'
#' @param c2b_codebook Parsed C2b codebook
#' @param acts_evidence Tibble with act_name, year, evidence, enacted_signals
#' @param true_labels Character vector of true motivation labels
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param max_retries Integer retries on validation failure
#' @param provider Character API provider
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @param baseline_preds Optional character vector of pre-computed baseline
#' @return List with per-combo accuracy and overall consistency
#' @export
test_c2b_exclusion_criteria <- function(
    c2b_codebook,
    acts_evidence,
    true_labels,
    model = "claude-haiku-4-5-20251001",
    max_tokens = 1024,
    max_retries = 1,
    provider = "anthropic",
    base_url = NULL,
    api_key = NULL,
    baseline_preds = NULL) {

  override_label <- "LONG_RUN"

  # --- Modified evidence: inject distractor into each act's evidence ---
  distractor_record <- list(
    quote = "The committee also discussed the welfare of elephants.",
    signal = "elephant welfare"
  )

  modified_evidence <- acts_evidence
  modified_evidence$evidence <- lapply(acts_evidence$evidence, function(ev) {
    c(ev, list(distractor_record))
  })

  # --- Modified codebook: add exclusion rule to non-LONG_RUN classes ---
  exclusion_text <- paste(
    "IMPORTANT: This category does not apply if the evidence",
    "discusses elephants."
  )

  modified_codebook <- c2b_codebook
  modified_codebook$classes <- lapply(c2b_codebook$classes, function(cls) {
    cls <- as.list(cls)
    if (cls$label != override_label) {
      cls$negative_clarification <- c(
        cls$negative_clarification,
        exclusion_text
      )
    }
    cls
  })

  # --- Expected labels per combo ---
  combo4_expected <- rep(override_label, length(true_labels))

  # --- Run four combos ---
  combos <- list(
    list(name = "normal_ev_normal_cb",   evidence = acts_evidence,     cb = c2b_codebook,      expected = baseline_preds %||% true_labels),
    list(name = "modified_ev_normal_cb", evidence = modified_evidence, cb = c2b_codebook,      expected = baseline_preds %||% true_labels),
    list(name = "normal_ev_modified_cb", evidence = acts_evidence,     cb = modified_codebook, expected = baseline_preds %||% true_labels),
    list(name = "modified_ev_modified_cb", evidence = modified_evidence, cb = modified_codebook, expected = combo4_expected)
  )

  all_details <- purrr::map(combos, function(combo) {
    # Reuse cached baseline for combo 1
    if (!is.null(baseline_preds) && combo$name == "normal_ev_normal_cb") {
      preds <- baseline_preds
    } else {
      preds <- classify_c2b_batch(
        combo$cb, combo$evidence, model,
        max_tokens = max_tokens, max_retries = max_retries,
        provider = provider, base_url = base_url, api_key = api_key
      )
    }

    combo_name <- combo$name
    combo_expected <- combo$expected

    tibble::tibble(
      combo = combo_name,
      act_id = seq_along(preds),
      true_label = true_labels,
      expected = combo_expected,
      predicted = preds,
      correct = preds == combo_expected
    )
  }) |> dplyr::bind_rows()

  combos_tbl <- all_details |>
    dplyr::group_by(combo) |>
    dplyr::summarise(
      n_correct = sum(correct, na.rm = TRUE),
      n_total = dplyr::n(),
      accuracy = n_correct / n_total,
      .groups = "drop"
    )

  overall <- sum(combos_tbl$n_correct) / sum(combos_tbl$n_total)

  all_correct <- all_details |>
    dplyr::group_by(act_id) |>
    dplyr::summarise(all_correct = all(correct), .groups = "drop")
  all_combos_correct_rate <- mean(all_correct$all_correct)

  list(
    test = "V_exclusion_criteria",
    combos = combos_tbl,
    overall_consistency = overall,
    all_combos_correct_rate = all_combos_correct_rate,
    override_label = override_label,
    details = all_details
  )
}


# =============================================================================
# Test VI: Generic Labels
# =============================================================================

#' Test VI: Generic Labels for C2b
#'
#' Replaces semantically meaningful motivation labels (SPENDING_DRIVEN, etc.)
#' with generic LABEL_1, LABEL_2, etc. Detects if model relies on label
#' semantics vs. definitions.
#'
#' @param c2b_codebook Parsed C2b codebook
#' @param acts_evidence Tibble with act_name, year, evidence, enacted_signals
#' @param true_labels Character vector of true motivation labels
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param max_retries Integer retries on validation failure
#' @param provider Character API provider
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @param baseline_preds Optional character vector of pre-computed baseline
#' @return List with original vs generic predictions and change rate
#' @export
test_c2b_generic_labels <- function(
    c2b_codebook,
    acts_evidence,
    true_labels,
    model = "claude-haiku-4-5-20251001",
    max_tokens = 1024,
    max_retries = 1,
    provider = "anthropic",
    base_url = NULL,
    api_key = NULL,
    baseline_preds = NULL) {

  # Create modified codebook with generic labels
  generic_codebook <- c2b_codebook
  label_map <- list()  # original -> generic

  for (i in seq_along(generic_codebook$classes)) {
    original_label <- generic_codebook$classes[[i]]$label
    generic_label <- paste0("LABEL_", i)
    label_map[[original_label]] <- generic_label
    generic_codebook$classes[[i]]$label <- generic_label
  }
  attr(generic_codebook, "valid_labels") <- unlist(label_map, use.names = FALSE)

  # Update output_instructions to use generic labels
  for (orig in names(label_map)) {
    generic_codebook$output_instructions <- gsub(
      orig, label_map[[orig]], generic_codebook$output_instructions
    )
  }

  # Original predictions (reuse cached baseline if available)
  original_preds <- if (!is.null(baseline_preds)) {
    baseline_preds
  } else {
    classify_c2b_batch(
      c2b_codebook, acts_evidence, model,
      max_tokens = max_tokens, max_retries = max_retries,
      provider = provider, base_url = base_url, api_key = api_key
    )
  }

  # Classify with generic labels
  generic_preds <- classify_c2b_batch(
    generic_codebook, acts_evidence, model,
    max_tokens = max_tokens, max_retries = max_retries,
    provider = provider, base_url = base_url, api_key = api_key
  )

  # Map generic predictions back to original labels
  reverse_map <- stats::setNames(names(label_map), unlist(label_map))
  generic_preds_mapped <- reverse_map[generic_preds]

  # Compute metrics
  original_acc <- mean(original_preds == true_labels, na.rm = TRUE)
  generic_acc <- mean(generic_preds_mapped == true_labels, na.rm = TRUE)
  change_rate <- mean(original_preds != generic_preds_mapped, na.rm = TRUE)

  motivation_levels <- c("SPENDING_DRIVEN", "COUNTERCYCLICAL",
                         "DEFICIT_DRIVEN", "LONG_RUN")

  original_metrics <- compute_multiclass_metrics(
    original_preds, true_labels, motivation_levels
  )
  generic_metrics <- compute_multiclass_metrics(
    generic_preds_mapped, true_labels, motivation_levels
  )

  list(
    test = "VI_generic_labels",
    original_accuracy = original_acc,
    generic_accuracy = generic_acc,
    accuracy_difference = original_acc - generic_acc,
    change_rate = change_rate,
    original_weighted_f1 = original_metrics$weighted_f1,
    generic_weighted_f1 = generic_metrics$weighted_f1,
    f1_difference = original_metrics$weighted_f1 - generic_metrics$weighted_f1,
    original_metrics = original_metrics,
    generic_metrics = generic_metrics,
    label_map = label_map,
    details = tibble::tibble(
      act_id = seq_along(true_labels),
      true_label = true_labels,
      original_pred = original_preds,
      generic_pred_mapped = generic_preds_mapped,
      changed = original_preds != generic_preds_mapped
    )
  )
}


# =============================================================================
# Test VII: Swapped Labels
# =============================================================================

#' Test VII: Swapped Labels for C2b
#'
#' Rotates definitions cyclically across label names. If predictions follow
#' swapped names rather than swapped definitions, model ignores definitions.
#'
#' @param c2b_codebook Parsed C2b codebook
#' @param acts_evidence Tibble with act_name, year, evidence, enacted_signals
#' @param true_labels Character vector of true motivation labels
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param max_retries Integer retries on validation failure
#' @param provider Character API provider
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @param baseline_preds Optional character vector of pre-computed baseline
#' @return List with follows_definitions_rate and follows_names_rate
#' @export
test_c2b_swapped_labels <- function(
    c2b_codebook,
    acts_evidence,
    true_labels,
    model = "claude-haiku-4-5-20251001",
    max_tokens = 1024,
    max_retries = 1,
    provider = "anthropic",
    base_url = NULL,
    api_key = NULL,
    baseline_preds = NULL) {

  n_classes <- length(c2b_codebook$classes)
  if (n_classes < 2) {
    stop("Need at least 2 classes for swapped label test")
  }

  # Create swapped codebook: rotate definitions by one position
  # Label names stay the same, but definitions/clarifications rotate
  swapped_codebook <- c2b_codebook
  for (i in seq_len(n_classes)) {
    source_idx <- (i %% n_classes) + 1  # Rotate by one
    swapped_codebook$classes[[i]]$label_definition <-
      c2b_codebook$classes[[source_idx]]$label_definition
    swapped_codebook$classes[[i]]$clarification <-
      c2b_codebook$classes[[source_idx]]$clarification
    swapped_codebook$classes[[i]]$negative_clarification <-
      c2b_codebook$classes[[source_idx]]$negative_clarification
  }

  # Original predictions (reuse cached baseline)
  original_preds <- if (!is.null(baseline_preds)) {
    baseline_preds
  } else {
    classify_c2b_batch(
      c2b_codebook, acts_evidence, model,
      max_tokens = max_tokens, max_retries = max_retries,
      provider = provider, base_url = base_url, api_key = api_key
    )
  }

  # Classify with swapped definitions
  swapped_preds <- classify_c2b_batch(
    swapped_codebook, acts_evidence, model,
    max_tokens = max_tokens, max_retries = max_retries,
    provider = provider, base_url = base_url, api_key = api_key
  )

  # Build definition mapping: if model follows definitions, predictions rotate
  # Class i now has class (i%%n)+1's definition, so a text that was predicted
  # as class (i%%n)+1 should now be predicted as class i
  original_labels <- vapply(c2b_codebook$classes, function(c) c$label, character(1))
  def_map <- stats::setNames(
    original_labels,
    vapply(seq_len(n_classes), function(i) {
      c2b_codebook$classes[[(i %% n_classes) + 1]]$label
    }, character(1))
  )

  follows_definitions <- mean(
    swapped_preds == def_map[original_preds], na.rm = TRUE
  )
  follows_names <- mean(swapped_preds == original_preds, na.rm = TRUE)

  motivation_levels <- c("SPENDING_DRIVEN", "COUNTERCYCLICAL",
                         "DEFICIT_DRIVEN", "LONG_RUN")

  swapped_metrics <- compute_multiclass_metrics(
    swapped_preds, true_labels, motivation_levels
  )

  list(
    test = "VII_swapped_labels",
    follows_definitions_rate = follows_definitions,
    follows_names_rate = follows_names,
    swapped_weighted_f1 = swapped_metrics$weighted_f1,
    swapped_accuracy = swapped_metrics$accuracy,
    swapped_metrics = swapped_metrics,
    interpretation = if (follows_names > follows_definitions) {
      "WARNING: Model appears to rely on label names rather than definitions"
    } else {
      "Model appears to follow definitions rather than label names"
    },
    details = tibble::tibble(
      act_id = seq_along(true_labels),
      true_label = true_labels,
      original_pred = original_preds,
      swapped_pred = swapped_preds
    )
  )
}


# =============================================================================
# Ablation Study
# =============================================================================

#' Run ablation study on C2b codebook components
#'
#' Tests 4 conditions matching C1 S3 ablation (H&K Table 4 design):
#' progressively removing semantic C2b components and measuring metric
#' degradation. Output instructions are kept in all conditions.
#'
#' @param c2b_codebook Parsed C2b codebook
#' @param acts_evidence Tibble with act_name, year, evidence, enacted_signals
#' @param true_labels Character vector of true motivation labels
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param max_retries Integer retries on validation failure
#' @param provider Character API provider
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @param baseline_preds Optional character vector of pre-computed baseline
#' @return Tibble with per-condition metrics and drops
#' @export
run_c2b_ablation <- function(c2b_codebook,
                             acts_evidence,
                             true_labels,
                             model = "claude-haiku-4-5-20251001",
                             max_tokens = 1024,
                             max_retries = 1,
                             provider = "anthropic",
                             base_url = NULL,
                             api_key = NULL,
                             baseline_preds = NULL) {

  motivation_levels <- c("SPENDING_DRIVEN", "COUNTERCYCLICAL",
                         "DEFICIT_DRIVEN", "LONG_RUN")

  # Local helper: compute metrics from prediction vector
  calc_metrics <- function(preds, true_labels) {
    m <- compute_multiclass_metrics(preds, true_labels, motivation_levels)
    list(
      accuracy = m$accuracy,
      weighted_f1 = m$weighted_f1,
      macro_f1 = m$macro_f1,
      per_class = m$per_class
    )
  }

  # Baseline (reuse cached predictions if available)
  if (is.null(baseline_preds)) {
    baseline_preds <- classify_c2b_batch(
      c2b_codebook, acts_evidence, model,
      max_tokens = max_tokens, max_retries = max_retries,
      provider = provider, base_url = base_url, api_key = api_key
    )
  }
  baseline_m <- calc_metrics(baseline_preds, true_labels)

  # H&K Table 4 ablation conditions (output_instructions always kept)
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
      abl_m <- baseline_m
    } else {
      ablated_prompt <- construct_codebook_prompt(
        c2b_codebook, exclude_sections = cond$sections_removed
      )
      ablated_preds <- classify_c2b_batch(
        c2b_codebook, acts_evidence, model,
        system_prompt = ablated_prompt,
        max_tokens = max_tokens, max_retries = max_retries,
        provider = provider, base_url = base_url, api_key = api_key
      )
      abl_m <- calc_metrics(ablated_preds, true_labels)
    }

    tibble::tibble(
      condition = cond$condition,
      sections_removed = paste(cond$sections_removed, collapse = ", "),
      accuracy = abl_m$accuracy,
      weighted_f1 = abl_m$weighted_f1,
      macro_f1 = abl_m$macro_f1,
      accuracy_drop = baseline_m$accuracy - abl_m$accuracy,
      weighted_f1_drop = baseline_m$weighted_f1 - abl_m$weighted_f1,
      macro_f1_drop = baseline_m$macro_f1 - abl_m$macro_f1
    )
  })

  ablation_results <- dplyr::bind_rows(results)

  ablated_rows <- ablation_results |> dplyr::filter(condition != "full")
  message(sprintf(
    "  Ablation: %d conditions tested. Max weighted F1 drop: %.1f%%, Max accuracy drop: %.1f%%",
    nrow(ablated_rows),
    max(ablated_rows$weighted_f1_drop, na.rm = TRUE) * 100,
    max(ablated_rows$accuracy_drop, na.rm = TRUE) * 100
  ))

  ablation_results
}


# =============================================================================
# Orchestrator
# =============================================================================

#' Run C2 S3 error analysis
#'
#' Orchestrates Tests V-VII and ablation study for C2b motivation
#' classification. Uses cached C2a evidence from c2_s2_results as baseline;
#' only re-runs C2b with modified codebooks.
#'
#' @param c2b_codebook Parsed C2b codebook
#' @param c2_s2_results Tibble from run_c2b_classification() with evidence_raw,
#'   enacted_signals_raw, pred_label, true_motivation columns
#' @param model Character model ID (default "claude-haiku-4-5-20251001")
#' @param max_tokens_c2b Integer max output tokens for C2b (default 1024)
#' @param max_retries Integer retries on validation failure (default 1)
#' @param provider Character API provider (default "anthropic")
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with baseline_preds, true_labels, test_v, test_vi, test_vii,
#'   ablation, model, n_acts, timestamp
#' @export
run_c2_error_analysis <- function(c2b_codebook,
                                  c2_s2_results,
                                  model = "claude-haiku-4-5-20251001",
                                  max_tokens_c2b = 1024,
                                  max_retries = 1,
                                  provider = "anthropic",
                                  base_url = NULL,
                                  api_key = NULL) {

  message("Running C2 S3 error analysis...")

  # --- v0.7.0+ guard: Tests V-VII depend on the 4-class structure ---
  # The minimal Das-et-al.-style codebook has no classes, no per-class
  # negative_clarification fields to ablate, and no semantically loaded
  # label names to swap. The shuffle diagnostic
  # (c2b_evidence_shuffle_diagnostic target) supersedes Tests V-VII for
  # v0.7.0+ codebooks.
  if (is.null(c2b_codebook$classes) || length(c2b_codebook$classes) == 0) {
    message("  SKIPPED: codebook has no classes; ",
            "Tests V-VII and ablation are degenerate. ",
            "Use c2b_evidence_shuffle_diagnostic for v0.7.0+ stability checks.")
    return(list(
      baseline_preds = character(0),
      true_labels = character(0),
      test_v = list(skipped = TRUE,
                    reason = "No classes in v0.7.0+ codebook"),
      test_vi = list(skipped = TRUE,
                     reason = "No classes in v0.7.0+ codebook"),
      test_vii = list(skipped = TRUE,
                      reason = "No classes in v0.7.0+ codebook"),
      ablation = list(skipped = TRUE,
                      reason = "No per-class clarifications to ablate"),
      model = model,
      n_acts = 0L,
      codebook_version = c2b_codebook$version %||% NA_character_,
      timestamp = Sys.time(),
      skipped = TRUE
    ))
  }

  # --- Extract baseline from c2_s2_results ---
  valid <- c2_s2_results |>
    dplyr::filter(!is.na(pred_label))

  baseline_preds <- valid$pred_label
  true_labels <- valid$true_motivation
  n_acts <- nrow(valid)

  message(sprintf("  Baseline: %d acts with valid predictions", n_acts))

  # Build acts_evidence tibble for classify_c2b_batch()
  acts_evidence <- tibble::tibble(
    act_name = valid$act_name,
    year = valid$year,
    evidence = valid$evidence_raw,
    enacted_signals = valid$enacted_signals_raw
  )

  # Shared API params
  api_args <- list(
    model = model, max_tokens = max_tokens_c2b, max_retries = max_retries,
    provider = provider, base_url = base_url, api_key = api_key
  )

  # --- Test V: Exclusion Criteria Consistency ---
  message("  Test V: Exclusion Criteria Consistency...")
  test_v <- test_c2b_exclusion_criteria(
    c2b_codebook, acts_evidence, true_labels, model,
    max_tokens = max_tokens_c2b, max_retries = max_retries,
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

  # --- Test VI: Generic Labels ---
  message("  Test VI: Generic Labels...")
  test_vi <- test_c2b_generic_labels(
    c2b_codebook, acts_evidence, true_labels, model,
    max_tokens = max_tokens_c2b, max_retries = max_retries,
    provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
  )
  message(sprintf("    Original accuracy: %.1f%%, Generic accuracy: %.1f%%",
                  test_vi$original_accuracy * 100,
                  test_vi$generic_accuracy * 100))
  message(sprintf("    Change rate: %.1f%%", test_vi$change_rate * 100))
  message(sprintf("    Original wF1: %.3f, Generic wF1: %.3f",
                  test_vi$original_weighted_f1, test_vi$generic_weighted_f1))

  # --- Test VII: Swapped Labels ---
  message("  Test VII: Swapped Labels...")
  test_vii <- test_c2b_swapped_labels(
    c2b_codebook, acts_evidence, true_labels, model,
    max_tokens = max_tokens_c2b, max_retries = max_retries,
    provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
  )
  message(sprintf("    Follows definitions: %.1f%%, Follows names: %.1f%%",
                  test_vii$follows_definitions_rate * 100,
                  test_vii$follows_names_rate * 100))
  message(sprintf("    %s", test_vii$interpretation))

  # --- Ablation Study ---
  message("  Running ablation study...")
  ablation <- run_c2b_ablation(
    c2b_codebook, acts_evidence, true_labels, model,
    max_tokens = max_tokens_c2b, max_retries = max_retries,
    provider = provider, base_url = base_url, api_key = api_key,
    baseline_preds = baseline_preds
  )

  message("\nC2 S3 error analysis complete.")

  list(
    baseline_preds = baseline_preds,
    true_labels = true_labels,
    test_v = test_v,
    test_vi = test_vi,
    test_vii = test_vii,
    ablation = ablation,
    model = model,
    n_acts = n_acts,
    timestamp = Sys.time()
  )
}
