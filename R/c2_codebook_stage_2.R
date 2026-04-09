# C2 S2: Zero-shot motivation classification (two-codebook pipeline)
#
# Implements the composed C2a→C2b evaluation pipeline for H&K Stage 2.
# Parallels R/codebook_stage_2.R but does NOT modify it.
# Reuses: call_codebook_generic(), format_c2a_input(), format_c2b_input(),
#          validate_c2a_output(), validate_c2b_output() from R/c2_behavioral_tests.R
#          construct_codebook_prompt(), get_valid_labels() from R/codebook_stage_0.R

# Null coalescing (guard against missing definition)
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b


# =============================================================================
# Data Assembly
# =============================================================================

#' Assemble C2 S2 sensitivity data (relaxed discusses_motivation filter)
#'
#' Like assemble_c2_input_data() but only requires pred_label == "FISCAL_MEASURE",
#' dropping the discusses_motivation requirement. This tests whether C2 finds
#' motivation evidence that C1's discusses_motivation flag missed.
#'
#' @param c1_classified_chunks Tibble from assemble_c1_classified_chunks()
#' @return Tibble of filtered chunks for C2 sensitivity evaluation
#' @export
assemble_c2_s2_sensitivity_data <- function(c1_classified_chunks) {

  result <- c1_classified_chunks |>
    dplyr::filter(pred_label == "FISCAL_MEASURE")

  # Compare to what the primary condition produces
  n_primary <- sum(
    c1_classified_chunks$pred_label == "FISCAL_MEASURE" &
      c1_classified_chunks$discusses_motivation == TRUE,
    na.rm = TRUE
  )

  message(sprintf(
    paste0(
      "C2 sensitivity data: %d chunks across %d acts ",
      "(vs %d chunks in primary condition, +%d chunks)"
    ),
    nrow(result),
    dplyr::n_distinct(result$act_name),
    n_primary,
    nrow(result) - n_primary
  ))

  result
}


#' Assemble C2 S2 test set (act-level with nested chunks)
#'
#' Groups C2 input chunks by act and joins ground truth labels from aligned_data.
#' Maps label formats from aligned_data (e.g., "Spending-driven") to codebook
#' format (e.g., "SPENDING_DRIVEN") for direct comparison with predictions.
#'
#' @param c2_data Tibble from assemble_c2_input_data() or assemble_c2_s2_sensitivity_data()
#' @param aligned_data Tibble from align_labels_shocks() with act-level labels
#' @return Tibble with one row per act: act_name, year, true_motivation,
#'   true_exogenous, chunks (list-column), n_chunks
#' @export
assemble_c2_s2_test_set <- function(c2_data, aligned_data) {

  motivation_map <- c(
    "Spending-driven" = "SPENDING_DRIVEN",
    "Countercyclical" = "COUNTERCYCLICAL",
    "Deficit-driven"  = "DEFICIT_DRIVEN",
    "Long-run"        = "LONG_RUN"
  )

  exo_map <- c("Exogenous" = TRUE, "Endogenous" = FALSE)

  # Canonical ground truth from aligned_data
  labels <- aligned_data |>
    dplyr::select(act_name, motivation_category, exogenous_flag) |>
    dplyr::distinct() |>
    dplyr::mutate(
      true_motivation = motivation_map[motivation_category],
      true_exogenous = exo_map[exogenous_flag]
    )

  # Validate mapping completeness
  unmapped <- labels |> dplyr::filter(is.na(true_motivation))
  if (nrow(unmapped) > 0) {
    stop(sprintf(
      "Unmapped motivation categories: %s",
      paste(unique(unmapped$motivation_category), collapse = ", ")
    ))
  }

  # Nest chunks by act
  nested <- c2_data |>
    dplyr::group_by(act_name) |>
    dplyr::summarize(
      year = dplyr::first(year),
      chunks = list(dplyr::tibble(
        chunk_id = chunk_id,
        doc_id = doc_id,
        text = text,
        tier = tier
      )),
      n_chunks = dplyr::n(),
      .groups = "drop"
    )

  # Join ground truth
  result <- nested |>
    dplyr::inner_join(
      labels |> dplyr::select(act_name, true_motivation, true_exogenous),
      by = "act_name"
    )

  # Check for acts lost
  lost_acts <- setdiff(labels$act_name, result$act_name)
  if (length(lost_acts) > 0) {
    warning(sprintf(
      "C2 S2 test set: %d act(s) have zero chunks in c2_data: %s",
      length(lost_acts),
      paste(lost_acts, collapse = ", ")
    ))
  }

  message(sprintf(
    "C2 S2 test set: %d acts, %d total chunks (%.1f chunks/act avg)",
    nrow(result),
    sum(result$n_chunks),
    mean(result$n_chunks)
  ))

  result |>
    dplyr::select(act_name, year, true_motivation, true_exogenous,
                  chunks, n_chunks)
}


# =============================================================================
# Composed Runner (C2a → C2b)
# =============================================================================

#' Run C2 zero-shot evaluation (composed C2a→C2b pipeline)
#'
#' For each act: (1) runs C2a evidence extraction on every chunk,
#' (2) aggregates evidence across chunks, (3) runs C2b act-level
#' classification on aggregated evidence.
#'
#' @param c2a_codebook Parsed C2a codebook (evidence extraction)
#' @param c2b_codebook Parsed C2b codebook (motivation classification)
#' @param c2_s2_test_set Tibble from assemble_c2_s2_test_set()
#' @param model Character model ID (default "claude-haiku-4-5-20251001")
#' @param max_tokens_c2a Integer max output tokens for C2a (default 1024)
#' @param max_tokens_c2b Integer max output tokens for C2b (default 1024)
#' @param max_retries Integer retries on validation failure (default 1)
#' @param show_progress Logical show progress messages (default TRUE)
#' @param provider Character API provider (default "anthropic")
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return Tibble with one row per act containing predictions and diagnostics
#' @export
run_c2_zero_shot <- function(c2a_codebook,
                             c2b_codebook,
                             c2_s2_test_set,
                             model = "claude-haiku-4-5-20251001",
                             max_tokens_c2a = 1024,
                             max_tokens_c2b = 1024,
                             max_retries = 1,
                             show_progress = TRUE,
                             provider = "anthropic",
                             base_url = NULL,
                             api_key = NULL) {

  c2a_system <- construct_codebook_prompt(c2a_codebook)
  c2b_system <- construct_codebook_prompt(c2b_codebook)
  c2a_labels <- get_valid_labels(c2a_codebook)
  c2b_labels <- get_valid_labels(c2b_codebook)
  n_acts <- nrow(c2_s2_test_set)

  results <- purrr::map_dfr(seq_len(n_acts), function(i) {
    act <- c2_s2_test_set[i, ]
    act_chunks <- act$chunks[[1]]

    if (show_progress) {
      message(sprintf(
        "C2 S2: act %d/%d [%s] — %d chunks",
        i, n_acts, act$act_name, nrow(act_chunks)
      ))
    }

    # ------ C2a: extract evidence from each chunk ------
    all_evidence <- list()
    all_enacted <- list()
    n_c2a_failures <- 0L

    for (j in seq_len(nrow(act_chunks))) {
      user_msg <- format_c2a_input(
        text = act_chunks$text[j],
        act_name = act$act_name,
        year = act$year
      )

      c2a_result <- tryCatch({
        parsed <- call_codebook_generic(
          user_message = user_msg,
          codebook = c2a_codebook,
          model = model,
          system_prompt = c2a_system,
          max_tokens = max_tokens_c2a,
          temperature = 0,
          provider = provider,
          base_url = base_url,
          api_key = api_key
        )
        validation <- validate_c2a_output(parsed, c2a_labels)
        if (!validation$valid) {
          list(valid = FALSE, reason = validation$reason, parsed = parsed)
        } else {
          list(valid = TRUE, parsed = parsed)
        }
      }, error = function(e) {
        list(valid = FALSE, reason = e$message, parsed = NULL)
      })

      # Retry once on failure
      if (!c2a_result$valid) {
        c2a_result <- tryCatch({
          parsed <- call_codebook_generic(
            user_message = user_msg,
            codebook = c2a_codebook,
            model = model,
            system_prompt = c2a_system,
            max_tokens = max_tokens_c2a,
            temperature = 0,
            provider = provider,
            base_url = base_url,
            api_key = api_key
          )
          validation <- validate_c2a_output(parsed, c2a_labels)
          if (!validation$valid) {
            list(valid = FALSE, reason = validation$reason, parsed = parsed)
          } else {
            list(valid = TRUE, parsed = parsed)
          }
        }, error = function(e) {
          list(valid = FALSE, reason = e$message, parsed = NULL)
        })
      }

      if (c2a_result$valid) {
        all_evidence <- c(all_evidence, c2a_result$parsed$evidence %||% list())
        all_enacted <- c(all_enacted, c2a_result$parsed$enacted_signals %||% list())
      } else {
        n_c2a_failures <- n_c2a_failures + 1L
        warning(sprintf(
          "C2a validation failed for [%s] chunk %d/%d: %s",
          act$act_name, j, nrow(act_chunks),
          c2a_result$reason %||% "unknown"
        ))
      }
    }

    if (show_progress) {
      message(sprintf(
        "  C2a complete: %d evidence items, %d enacted signals, %d failures",
        length(all_evidence), length(all_enacted), n_c2a_failures
      ))
    }

    # ------ C2b: classify from aggregated evidence ------
    c2b_parsed <- NULL
    c2b_valid <- FALSE

    for (attempt in seq_len(1 + max_retries)) {
      c2b_result <- tryCatch({
        user_msg_b <- format_c2b_input(
          act_name = act$act_name,
          year = act$year,
          evidence = all_evidence,
          enacted_signals = all_enacted
        )
        parsed <- call_codebook_generic(
          user_message = user_msg_b,
          codebook = c2b_codebook,
          model = model,
          system_prompt = c2b_system,
          max_tokens = max_tokens_c2b,
          temperature = 0,
          provider = provider,
          base_url = base_url,
          api_key = api_key
        )
        validation <- validate_c2b_output(parsed, c2b_labels)
        if (!validation$valid) {
          list(valid = FALSE, reason = validation$reason, parsed = parsed)
        } else {
          list(valid = TRUE, parsed = parsed)
        }
      }, error = function(e) {
        list(valid = FALSE, reason = e$message, parsed = NULL)
      })

      if (c2b_result$valid) {
        c2b_parsed <- c2b_result$parsed
        c2b_valid <- TRUE
        break
      }
    }

    if (!c2b_valid) {
      warning(sprintf(
        "C2b validation failed for [%s] after %d attempts: %s",
        act$act_name, 1 + max_retries,
        c2b_result$reason %||% "unknown"
      ))
    }

    # ------ Collapse motivations[] to single label ------
    pred_motivation <- NA_character_
    pred_exogenous <- NA
    enacted <- NA
    confidence <- NA_character_
    reasoning <- NA_character_
    motivations_raw <- list(NULL)
    multiple_dominant <- FALSE
    no_dominant <- FALSE

    if (c2b_valid && !is.null(c2b_parsed)) {
      motivations <- c2b_parsed$motivations %||% list()
      motivations_raw <- list(motivations)
      enacted <- c2b_parsed$enacted %||% NA
      pred_exogenous <- c2b_parsed$exogenous %||% NA
      confidence <- c2b_parsed$confidence %||% NA_character_
      reasoning <- c2b_parsed$reasoning %||% NA_character_

      if (length(motivations) > 0) {
        shares <- vapply(motivations, function(m) m$share %||% "", character(1))

        sole_idx <- which(shares == "sole")
        dominant_idx <- which(shares == "dominant")

        if (length(sole_idx) >= 1) {
          pred_motivation <- motivations[[sole_idx[1]]]$category
        } else if (length(dominant_idx) == 1) {
          pred_motivation <- motivations[[dominant_idx[1]]]$category
        } else if (length(dominant_idx) > 1) {
          multiple_dominant <- TRUE
          pred_motivation <- motivations[[dominant_idx[1]]]$category
          warning(sprintf(
            "Multiple 'dominant' motivations for [%s]: %s",
            act$act_name,
            paste(vapply(motivations[dominant_idx],
                         function(m) m$category, character(1)),
                  collapse = ", ")
          ))
        } else {
          # All "minor" or unrecognized shares
          no_dominant <- TRUE
          pred_motivation <- motivations[[1]]$category
          warning(sprintf(
            "No 'dominant' or 'sole' motivation for [%s], using first: %s",
            act$act_name, pred_motivation
          ))
        }
      }
    }

    tibble::tibble(
      act_name = act$act_name,
      year = act$year,
      true_motivation = act$true_motivation,
      true_exogenous = act$true_exogenous,
      pred_motivation = pred_motivation,
      pred_exogenous = pred_exogenous,
      enacted = enacted,
      confidence = confidence,
      motivations_raw = motivations_raw,
      evidence_raw = list(all_evidence),
      reasoning = reasoning,
      n_chunks = nrow(act_chunks),
      n_evidence_items = length(all_evidence),
      n_c2a_failures = n_c2a_failures,
      multiple_dominant = multiple_dominant,
      no_dominant = no_dominant
    )
  })

  message(sprintf(
    "\nC2 S2 complete: %d acts, %d valid predictions, %d NA predictions",
    nrow(results),
    sum(!is.na(results$pred_motivation)),
    sum(is.na(results$pred_motivation))
  ))

  results
}


# =============================================================================
# Evaluation
# =============================================================================

#' Evaluate C2 motivation classification results
#'
#' Computes multi-class motivation metrics (4x4 confusion matrix, weighted F1,
#' per-class precision/recall/F1) and binary exogenous metrics (2x2 confusion
#' matrix, exogenous precision) with bootstrap CIs.
#'
#' @param c2_s2_results Tibble from run_c2_zero_shot()
#' @param n_bootstrap Integer bootstrap resamples (default 1000)
#' @param ci_level Numeric confidence level (default 0.95)
#' @return List with motivation metrics, exogenous metrics, per-act results,
#'   and quality flags
#' @export
evaluate_c2_classification <- function(c2_s2_results,
                                       n_bootstrap = 1000,
                                       ci_level = 0.95) {

  # Filter valid predictions
  valid <- c2_s2_results |>
    dplyr::filter(!is.na(pred_motivation))

  n_total <- nrow(c2_s2_results)
  n_valid <- nrow(valid)

  if (n_valid < n_total) {
    warning(sprintf(
      "%d/%d acts had NA predictions and were excluded",
      n_total - n_valid, n_total
    ))
  }

  if (n_valid == 0) {
    stop("No valid predictions to evaluate")
  }

  # --- Motivation metrics (4-class) ---
  motivation_levels <- c("SPENDING_DRIVEN", "COUNTERCYCLICAL",
                         "DEFICIT_DRIVEN", "LONG_RUN")

  motivation_cm <- table(
    Predicted = factor(valid$pred_motivation, levels = motivation_levels),
    True = factor(valid$true_motivation, levels = motivation_levels)
  )

  motivation_point <- compute_multiclass_metrics(
    valid$pred_motivation, valid$true_motivation, motivation_levels
  )

  # --- Exogenous metrics (binary) ---
  exo_cm <- table(
    Predicted = factor(valid$pred_exogenous, levels = c(TRUE, FALSE)),
    True = factor(valid$true_exogenous, levels = c(TRUE, FALSE))
  )

  exo_point <- compute_exo_metrics(valid$pred_exogenous, valid$true_exogenous)

  # --- Exogenous consistency check ---
  exo_from_motivation <- valid$pred_motivation %in% c("DEFICIT_DRIVEN", "LONG_RUN")
  exo_inconsistent <- sum(exo_from_motivation != valid$pred_exogenous, na.rm = TRUE)

  # --- Bootstrap CIs ---
  set.seed(42)
  boot_stats <- replicate(n_bootstrap, {
    boot_idx <- sample(seq_len(n_valid), n_valid, replace = TRUE)
    boot_data <- valid[boot_idx, ]

    m <- compute_multiclass_metrics(
      boot_data$pred_motivation, boot_data$true_motivation, motivation_levels
    )
    e <- compute_exo_metrics(boot_data$pred_exogenous, boot_data$true_exogenous)

    c(weighted_f1 = m$weighted_f1,
      macro_f1 = m$macro_f1,
      accuracy = m$accuracy,
      exo_precision = e$precision,
      exo_recall = e$recall,
      exo_f1 = e$f1,
      exo_accuracy = e$accuracy)
  })

  alpha <- 1 - ci_level
  ci_lower <- apply(boot_stats, 1, quantile, probs = alpha / 2, na.rm = TRUE)
  ci_upper <- apply(boot_stats, 1, quantile, probs = 1 - alpha / 2, na.rm = TRUE)

  # --- Per-act results ---
  per_act <- valid |>
    dplyr::mutate(
      correct_motivation = pred_motivation == true_motivation,
      correct_exogenous = pred_exogenous == true_exogenous
    ) |>
    dplyr::select(
      act_name, year, true_motivation, pred_motivation, correct_motivation,
      true_exogenous, pred_exogenous, correct_exogenous,
      confidence, n_chunks, n_evidence_items,
      n_c2a_failures, multiple_dominant, no_dominant
    ) |>
    dplyr::arrange(correct_motivation, correct_exogenous, act_name)

  # --- Quality flags ---
  quality_flags <- list(
    n_c2a_failures_total = sum(valid$n_c2a_failures),
    n_multiple_dominant = sum(valid$multiple_dominant),
    n_no_dominant = sum(valid$no_dominant),
    n_exo_inconsistent = exo_inconsistent
  )

  list(
    # Motivation metrics
    motivation_confusion_matrix = motivation_cm,
    motivation_weighted_f1 = motivation_point$weighted_f1,
    motivation_weighted_f1_ci = c(
      lower = ci_lower["weighted_f1"], upper = ci_upper["weighted_f1"]
    ),
    motivation_macro_f1 = motivation_point$macro_f1,
    motivation_macro_f1_ci = c(
      lower = ci_lower["macro_f1"], upper = ci_upper["macro_f1"]
    ),
    motivation_accuracy = motivation_point$accuracy,
    motivation_accuracy_ci = c(
      lower = ci_lower["accuracy"], upper = ci_upper["accuracy"]
    ),
    motivation_per_class = motivation_point$per_class,

    # Exogenous metrics
    exogenous_confusion_matrix = exo_cm,
    exogenous_precision = exo_point$precision,
    exogenous_precision_ci = c(
      lower = ci_lower["exo_precision"], upper = ci_upper["exo_precision"]
    ),
    exogenous_recall = exo_point$recall,
    exogenous_recall_ci = c(
      lower = ci_lower["exo_recall"], upper = ci_upper["exo_recall"]
    ),
    exogenous_f1 = exo_point$f1,
    exogenous_f1_ci = c(
      lower = ci_lower["exo_f1"], upper = ci_upper["exo_f1"]
    ),
    exogenous_accuracy = exo_point$accuracy,

    # Diagnostics
    per_act_results = per_act,
    quality_flags = quality_flags,
    n_total = n_total,
    n_valid = n_valid,
    n_bootstrap = n_bootstrap,
    ci_level = ci_level
  )
}


# =============================================================================
# Internal Helpers
# =============================================================================

#' Compute multi-class metrics (weighted and macro F1)
#'
#' @param pred Character vector of predicted labels
#' @param true Character vector of true labels
#' @param levels Character vector of all class labels
#' @return List with weighted_f1, macro_f1, accuracy, per_class tibble
#' @keywords internal
compute_multiclass_metrics <- function(pred, true, levels) {

  pred_f <- factor(pred, levels = levels)
  true_f <- factor(true, levels = levels)

  # Per-class one-vs-rest metrics
  per_class <- purrr::map_dfr(levels, function(cls) {
    tp <- sum(pred == cls & true == cls, na.rm = TRUE)
    fp <- sum(pred == cls & true != cls, na.rm = TRUE)
    fn <- sum(pred != cls & true == cls, na.rm = TRUE)
    support <- sum(true == cls, na.rm = TRUE)

    precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
    recall <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
    f1 <- if (!is.na(precision) && !is.na(recall) && precision + recall > 0) {
      2 * precision * recall / (precision + recall)
    } else {
      NA_real_
    }

    tibble::tibble(
      class = cls,
      precision = precision,
      recall = recall,
      f1 = f1,
      support = support
    )
  })

  # Weighted F1: weight by class support
  total_support <- sum(per_class$support)
  weighted_f1 <- if (total_support > 0) {
    sum(per_class$f1 * per_class$support, na.rm = TRUE) / total_support
  } else {
    NA_real_
  }

  # Macro F1: unweighted mean
  macro_f1 <- mean(per_class$f1, na.rm = TRUE)

  # Overall accuracy
  accuracy <- sum(pred == true, na.rm = TRUE) / length(pred)

  list(
    weighted_f1 = weighted_f1,
    macro_f1 = macro_f1,
    accuracy = accuracy,
    per_class = per_class
  )
}


#' Compute binary exogenous classification metrics
#'
#' @param pred Logical vector of predicted exogenous flags
#' @param true Logical vector of true exogenous flags
#' @return List with precision, recall, f1, accuracy
#' @keywords internal
compute_exo_metrics <- function(pred, true) {
  tp <- sum(pred == TRUE & true == TRUE, na.rm = TRUE)
  fp <- sum(pred == TRUE & true == FALSE, na.rm = TRUE)
  fn <- sum(pred == FALSE & true == TRUE, na.rm = TRUE)
  tn <- sum(pred == FALSE & true == FALSE, na.rm = TRUE)

  precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
  recall <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
  f1 <- if (!is.na(precision) && !is.na(recall) && precision + recall > 0) {
    2 * precision * recall / (precision + recall)
  } else {
    NA_real_
  }
  accuracy <- (tp + tn) / (tp + fp + fn + tn)

  list(
    precision = precision,
    recall = recall,
    f1 = f1,
    accuracy = accuracy,
    tp = tp, fp = fp, fn = fn, tn = tn
  )
}
