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
#' Groups C2 input chunks by act and joins ground truth from aligned_data.
#' Carries the v0.8.0 ground-truth fields (`true_exogenous`, `true_sign`,
#' `true_quarters`) alongside the legacy 4-class label (`true_motivation`) for
#' diagnostic compatibility. The 4-class label is no longer used by
#' `evaluate_c2_classification()` under v0.7.0+, but it is kept on the
#' test-set tibble so error analysis can still group by R&R category.
#'
#' Sign convention: `true_sign` is "+" when ground-truth `magnitude_billions`
#' is positive (tax increase / fiscal liabilities up), "-" when negative
#' (tax cut / liabilities down), "0" when zero, NA when missing.
#'
#' Quarter convention: `true_quarters` is a list-column of `YYYY-QN` character
#' vectors derived from `aligned_data$ground_truth_quarters` via
#' `normalize_ground_truth_quarters()`. R&R's `YYYY-MM` format is converted to
#' `YYYY-QN` (Q = ceiling(month / 3)) and same-quarter duplicates within an
#' act are de-duplicated, matching C2b's `enacted_quarter[]` set semantics.
#'
#' @param c2_data Tibble from assemble_c2_input_data() or assemble_c2_s2_sensitivity_data()
#' @param aligned_data Tibble from align_labels_shocks() with act-level labels,
#'   `magnitude_billions` (sign-bearing), and `ground_truth_quarters` (list-col).
#' @return Tibble with one row per act: act_name, year, true_motivation,
#'   true_exogenous, true_sign, true_quarters (list-col of YYYY-QN strings),
#'   chunks (list-column), n_chunks
#' @export
assemble_c2_s2_test_set <- function(c2_data, aligned_data) {

  motivation_map <- c(
    "Spending-driven" = "SPENDING_DRIVEN",
    "Countercyclical" = "COUNTERCYCLICAL",
    "Deficit-driven"  = "DEFICIT_DRIVEN",
    "Long-run"        = "LONG_RUN"
  )

  exo_map <- c("Exogenous" = TRUE, "Endogenous" = FALSE)

  if (!"magnitude_billions" %in% names(aligned_data)) {
    stop("aligned_data is missing 'magnitude_billions' column required for true_sign")
  }

  if (!"ground_truth_quarters" %in% names(aligned_data)) {
    stop("aligned_data is missing 'ground_truth_quarters' list-column required for true_quarters")
  }

  derive_sign <- function(x) {
    dplyr::case_when(
      is.na(x)  ~ NA_character_,
      x  >  0   ~ "+",
      x  <  0   ~ "-",
      TRUE      ~ "0"
    )
  }

  # Canonical ground truth from aligned_data (one row per act)
  labels <- aligned_data |>
    dplyr::select(act_name, motivation_category, exogenous_flag,
                  magnitude_billions, ground_truth_quarters) |>
    dplyr::distinct(act_name, .keep_all = TRUE) |>
    dplyr::mutate(
      true_motivation = motivation_map[motivation_category],
      true_exogenous = exo_map[exogenous_flag],
      true_sign = derive_sign(magnitude_billions),
      true_quarters = purrr::map(ground_truth_quarters,
                                 normalize_ground_truth_quarters)
    )

  # Validate mapping completeness
  unmapped <- labels |> dplyr::filter(is.na(true_motivation))
  if (nrow(unmapped) > 0) {
    stop(sprintf(
      "Unmapped motivation categories: %s",
      paste(unique(unmapped$motivation_category), collapse = ", ")
    ))
  }

  n_missing_sign <- sum(is.na(labels$true_sign))
  if (n_missing_sign > 0) {
    warning(sprintf(
      "C2 S2 test set: %d act(s) have NA true_sign (missing magnitude_billions)",
      n_missing_sign
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
        tier = tier,
        discusses_motivation = if ("discusses_motivation" %in% names(dplyr::cur_data()))
          discusses_motivation else NA
      )),
      n_chunks = dplyr::n(),
      .groups = "drop"
    )

  # Join ground truth
  result <- nested |>
    dplyr::inner_join(
      labels |> dplyr::select(act_name, true_motivation, true_exogenous,
                              true_sign, true_quarters),
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
    dplyr::select(act_name, year, true_motivation, true_exogenous, true_sign,
                  true_quarters, chunks, n_chunks)
}


#' Convert R&R quarter rows to a deduplicated set of `YYYY-QN` strings
#'
#' R&R's `us_shocks.csv` carries quarter assignments that `align_labels_shocks()`
#' surfaces in `aligned_data$ground_truth_quarters$change_in_liabilities_quarter`
#' as `<Date>` values pointing to the first day of the month (e.g.,
#' `1946-01-01` for 1946Q1). The same column may also appear as a character
#' `YYYY-MM` string in fresh CSV reads. R&R may record multiple rows per
#' quarter when an act has distinct provisions taking effect together (e.g.,
#' Tax Reform Act of 1969: two rows in `1971-01-01` from separate provisions).
#' C2b's `enacted_quarter[]` is naturally a set of unique quarters, so we
#' convert month → quarter and de-duplicate before any quarter-set comparison.
#'
#' @param gtq Tibble (one row per ground-truth quarter for an act) or a vector
#'   of quarter values directly. NULL is treated as empty. Accepted formats
#'   for `change_in_liabilities_quarter` (or for the vector itself):
#'   `<Date>`, `YYYY-MM` strings, or already-normalized `YYYY-QN` strings.
#' @return Character vector of unique `YYYY-QN` strings, sorted chronologically.
#'   Returns `character(0)` when input is NULL, empty, or all-NA.
#' @keywords internal
normalize_ground_truth_quarters <- function(gtq) {
  if (is.null(gtq)) return(character(0))
  if (is.data.frame(gtq)) {
    if (!"change_in_liabilities_quarter" %in% names(gtq)) return(character(0))
    raw <- gtq$change_in_liabilities_quarter
  } else {
    raw <- gtq
  }
  if (length(raw) == 0) return(character(0))

  # Date input: convert via month/year arithmetic.
  if (inherits(raw, "Date") || inherits(raw, "POSIXt")) {
    raw <- raw[!is.na(raw)]
    if (length(raw) == 0) return(character(0))
    yy <- as.integer(format(raw, "%Y"))
    mm <- as.integer(format(raw, "%m"))
    q <- ceiling(mm / 3)
    converted <- sprintf("%04d-Q%d", yy, q)
    return(sort(unique(converted)))
  }

  # Character input: handle YYYY-QN passthrough, YYYY-MM, and YYYY-MM-DD.
  raw <- raw[!is.na(raw)]
  if (length(raw) == 0) return(character(0))

  converted <- vapply(as.character(raw), function(s) {
    if (grepl("^[0-9]{4}-Q[1-4]$", s)) return(s)
    if (grepl("^[0-9]{4}-[0-9]{2}(-[0-9]{2})?$", s)) {
      year <- substr(s, 1, 4)
      month <- as.integer(substr(s, 6, 7))
      if (is.na(month) || month < 1 || month > 12) return(NA_character_)
      q <- ceiling(month / 3)
      return(sprintf("%s-Q%d", year, q))
    }
    NA_character_
  }, character(1))

  converted <- converted[!is.na(converted)]
  if (length(converted) == 0) return(character(0))

  sort(unique(converted))
}


# =============================================================================
# Split Runner: C2a extraction + C2b classification (preferred)
# =============================================================================

#' Run C2a evidence extraction on all chunks
#'
#' Extracts motivation evidence from each chunk independently. Returns a
#' chunk-level tibble that can be filtered (e.g., by discusses_motivation)
#' before feeding into run_c2b_classification().
#'
#' @param c2a_codebook Parsed C2a codebook (evidence extraction)
#' @param c2_s2_test_set Tibble from assemble_c2_s2_test_set() with nested chunks
#' @param model Character model ID
#' @param max_tokens_c2a Integer max output tokens for C2a (default 4096)
#' @param max_retries Integer retries on validation failure (default 1)
#' @param show_progress Logical show progress messages (default TRUE)
#' @param provider Character API provider (default "anthropic")
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return Tibble with one row per chunk: chunk_id, act_name, year,
#'   discusses_motivation, evidence (list-col), enacted_signals (list-col),
#'   timing_signals (list-col, added in C2a v0.5.0),
#'   c2a_valid (logical), c2a_failure_reason (character|NA)
#' @export
run_c2a_extraction <- function(c2a_codebook,
                               c2_s2_test_set,
                               model = "claude-haiku-4-5-20251001",
                               max_tokens_c2a = 4096,
                               max_retries = 1,
                               show_progress = TRUE,
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL) {

  c2a_system <- construct_codebook_prompt(c2a_codebook)

  # Unnest to flat chunk tibble
  flat <- c2_s2_test_set |>
    tidyr::unnest(chunks) |>
    dplyr::select(chunk_id, act_name, year, doc_id, text, tier,
                  dplyr::any_of("discusses_motivation"))

  n_chunks <- nrow(flat)
  message(sprintf("C2a extraction: %d chunks across %d acts",
                  n_chunks, dplyr::n_distinct(flat$act_name)))

  results <- purrr::map_dfr(seq_len(n_chunks), function(j) {
    chunk <- flat[j, ]

    if (show_progress) {
      message(sprintf(
        "  C2a chunk %d/%d [%s] chunk_id=%s",
        j, n_chunks, chunk$act_name, chunk$chunk_id
      ))
    }

    user_msg <- format_c2a_input(
      text = chunk$text,
      act_name = chunk$act_name,
      year = chunk$year
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
      validation <- validate_c2a_output(parsed)
      if (!validation$valid) {
        list(valid = FALSE, reason = validation$reason, parsed = parsed)
      } else {
        list(valid = TRUE, parsed = parsed)
      }
    }, error = function(e) {
      list(valid = FALSE, reason = e$message, parsed = NULL)
    })

    # Retry on failure
    if (!c2a_result$valid && max_retries >= 1) {
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
        validation <- validate_c2a_output(parsed)
        if (!validation$valid) {
          list(valid = FALSE, reason = validation$reason, parsed = parsed)
        } else {
          list(valid = TRUE, parsed = parsed)
        }
      }, error = function(e) {
        list(valid = FALSE, reason = e$message, parsed = NULL)
      })
    }

    if (!c2a_result$valid) {
      warning(sprintf(
        "C2a validation failed for [%s] chunk_id=%s: %s",
        chunk$act_name, chunk$chunk_id,
        c2a_result$reason %||% "unknown"
      ))
    }

    tibble::tibble(
      chunk_id = chunk$chunk_id,
      act_name = chunk$act_name,
      year = chunk$year,
      discusses_motivation = if ("discusses_motivation" %in% names(chunk))
        chunk$discusses_motivation else NA,
      evidence = list(
        if (c2a_result$valid) c2a_result$parsed$evidence %||% list() else list()
      ),
      enacted_signals = list(
        if (c2a_result$valid) c2a_result$parsed$enacted_signals %||% list() else list()
      ),
      timing_signals = list(
        if (c2a_result$valid) c2a_result$parsed$timing_signals %||% list() else list()
      ),
      c2a_valid = c2a_result$valid,
      c2a_failure_reason = if (!c2a_result$valid) c2a_result$reason %||% "unknown"
                           else NA_character_
    )
  })

  n_valid <- sum(results$c2a_valid)
  n_failed <- sum(!results$c2a_valid)
  message(sprintf(
    "C2a extraction complete: %d/%d valid, %d failed",
    n_valid, n_chunks, n_failed
  ))

  results
}


#' Run C2b act-level classification from pre-extracted C2a evidence
#'
#' Aggregates chunk-level C2a evidence by act, then runs C2b classification.
#' Accepts pre-filtered c2a_results (e.g., filtered to discusses_motivation == TRUE
#' for the primary condition).
#'
#' @param c2b_codebook Parsed C2b codebook (motivation classification)
#' @param c2a_results Tibble from run_c2a_extraction(), potentially pre-filtered
#' @param test_set Tibble from assemble_c2_s2_test_set() with ground truth
#' @param model Character model ID
#' @param max_tokens_c2b Integer max output tokens for C2b (default 4096)
#' @param max_retries Integer retries on validation failure (default 1)
#' @param show_progress Logical show progress messages (default TRUE)
#' @param provider Character API provider (default "anthropic")
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return Tibble with one row per act (same schema as run_c2_zero_shot output)
#' @export
run_c2b_classification <- function(c2b_codebook,
                                   c2a_results,
                                   test_set,
                                   model = "claude-haiku-4-5-20251001",
                                   max_tokens_c2b = 4096,
                                   max_retries = 1,
                                   show_progress = TRUE,
                                   provider = "anthropic",
                                   base_url = NULL,
                                   api_key = NULL) {

  c2b_system <- construct_codebook_prompt(c2b_codebook)

  # Defensive: cached c2a_evidence from C2a v0.4.0 lacks timing_signals.
  # Default to a per-row empty list so aggregation works either way.
  if (!"timing_signals" %in% names(c2a_results)) {
    warning(
      "c2a_results lacks 'timing_signals' column (likely cached from C2a v0.4.0). ",
      "Defaulting to empty timing_signals per chunk; rerun c2a_evidence to populate."
    )
    c2a_results <- c2a_results |>
      dplyr::mutate(timing_signals = purrr::map(seq_len(dplyr::n()), ~ list()))
  }

  # Aggregate C2a evidence by act
  act_evidence <- c2a_results |>
    dplyr::group_by(act_name, year) |>
    dplyr::summarize(
      all_evidence = list(unlist(evidence, recursive = FALSE)),
      all_enacted = list(unlist(enacted_signals, recursive = FALSE)),
      all_timing = list(unlist(timing_signals, recursive = FALSE)),
      n_chunks = dplyr::n(),
      n_c2a_failures = sum(!c2a_valid),
      .groups = "drop"
    )

  # Join ground truth from test_set (only acts present in both)
  combined <- act_evidence |>
    dplyr::inner_join(
      test_set |> dplyr::select(act_name, dplyr::any_of("true_motivation"),
                                true_exogenous, true_sign,
                                dplyr::any_of("true_quarters")),
      by = "act_name"
    )

  n_acts <- nrow(combined)
  message(sprintf("C2b classification: %d acts", n_acts))

  results <- purrr::map_dfr(seq_len(n_acts), function(i) {
    act <- combined[i, ]
    all_evidence <- act$all_evidence[[1]]
    all_enacted <- act$all_enacted[[1]]
    all_timing <- act$all_timing[[1]]

    if (show_progress) {
      message(sprintf(
        "  C2b act %d/%d [%s] — %d evidence, %d enacted, %d timing signals",
        i, n_acts, act$act_name,
        length(all_evidence), length(all_enacted), length(all_timing)
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
          enacted_signals = all_enacted,
          timing_signals = all_timing
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
        validation <- validate_c2b_output(parsed)
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

    # ------ Extract v0.9.1 schema fields ------
    pred_label <- NA_character_
    pred_exogenous <- NA  # logical — deterministic mapping from label
    pred_sign_raw <- NA_character_  # v0.9.1 enum: increase/decrease/no_change
    pred_sign <- NA_character_      # canonical sign convention: +/-/0
    enacted <- NA
    confidence <- NA_character_
    reasoning <- NA_character_

    if (c2b_valid && !is.null(c2b_parsed)) {
      pred_label <- c2b_parsed$label %||% NA_character_
      enacted <- c2b_parsed$enacted %||% NA
      pred_sign_raw <- c2b_parsed$sign %||% NA_character_
      confidence <- c2b_parsed$confidence %||% NA_character_
      reasoning <- c2b_parsed$reasoning %||% NA_character_

      pred_exogenous <- dplyr::case_when(
        pred_label %in% c("DEFICIT_DRIVEN", "LONG_RUN")          ~ TRUE,
        pred_label %in% c("SPENDING_DRIVEN", "COUNTERCYCLICAL")  ~ FALSE,
        TRUE                                                     ~ NA
      )

      pred_sign <- dplyr::case_when(
        identical(pred_sign_raw, "increase")  ~ "+",
        identical(pred_sign_raw, "decrease")  ~ "-",
        identical(pred_sign_raw, "no_change") ~ "0",
        TRUE                                  ~ NA_character_
      )
    }

    tibble::tibble(
      act_name = act$act_name,
      year = act$year,
      true_motivation = act$true_motivation %||% NA_character_,
      true_exogenous = act$true_exogenous,
      true_sign = act$true_sign,
      pred_label = pred_label,
      pred_exogenous = pred_exogenous,
      pred_sign = pred_sign,
      pred_sign_raw = pred_sign_raw,
      enacted = enacted,
      confidence = confidence,
      evidence_raw = list(all_evidence),
      enacted_signals_raw = list(all_enacted),
      timing_signals_raw = list(all_timing),
      c2b_raw_response = if (c2b_valid) c2b_parsed$raw_response else NA_character_,
      reasoning = reasoning,
      n_chunks = act$n_chunks,
      n_evidence_items = length(all_evidence),
      n_timing_signals = length(all_timing),
      n_c2a_failures = act$n_c2a_failures
    )
  })

  message(sprintf(
    paste0("\nC2b classification complete: %d acts, %d valid labels, ",
           "%d NA exogenous, %d NA sign"),
    nrow(results),
    sum(!is.na(results$pred_label)),
    sum(is.na(results$pred_exogenous)),
    sum(is.na(results$pred_sign))
  ))

  results
}


# =============================================================================
# Composed Runner (C2a → C2b) — DEPRECATED
# Use run_c2a_extraction() + run_c2b_classification() instead.
# Kept for reference and backward compatibility with cached targets.
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
        validation <- validate_c2a_output(parsed)
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
          validation <- validate_c2a_output(parsed)
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
      enacted_signals_raw = list(all_enacted),
      c2b_raw_response = if (c2b_valid) c2b_parsed$raw_response else NA_character_,
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

#' Evaluate C2 motivation and sign classification results (v0.9.1)
#'
#' Computes the headline metrics for the v0.9.1 act-level output schema:
#' (a) **exogenous precision** (binary, TRUE-class precision; exogenous flag
#' is derived deterministically from the 4-way `label` in
#' `run_c2b_classification`); (b) **sign accuracy on true-exogenous acts**;
#' (c) joint diagnostic **signed-exogenous precision** (P(correct exo AND
#' correct sign | true exogenous)).
#'
#' Quarter-based metrics (primary-quarter exact match, ±1 quarter tolerance,
#' phased-act detection rate, quarter-set Jaccard) are deferred until
#' `enacted_quarter[]` is restored to the codebook output schema in a future
#' v0.9.x. Until then those four metrics return NA and the test set carries
#' no quarter list-columns.
#'
#' Bootstrap CIs are computed by resampling **at the act level** (the unit of
#' independence). Exo precision, sign accuracy, and signed exo precision are
#' recomputed inside each resample because their denominators depend on
#' subset filters (not-NA pred_exogenous, true_exogenous == TRUE).
#'
#' v0.9.1 has no UNCLEAR exogenous path — `pred_exogenous` is a deterministic
#' function of `pred_label`, NA only when the model returned an unparseable
#' or out-of-vocabulary label. NA sign predictions count as incorrect when
#' ground truth is exogenous (the model failed to commit to a direction the
#' shock series requires).
#'
#' @param c2_s2_results Tibble from `run_c2b_classification()`; must include
#'   columns `pred_label` (character), `pred_exogenous` (logical),
#'   `true_exogenous` (logical), `pred_sign` (character), `true_sign`
#'   (character).
#' @param n_bootstrap Integer bootstrap resamples (default 1000)
#' @param ci_level Numeric confidence level (default 0.95)
#' @return List with exogenous metrics, sign metrics, per-act results,
#'   and quality flags
#' @export
evaluate_c2_classification <- function(c2_s2_results,
                                       n_bootstrap = 1000,
                                       ci_level = 0.95) {

  # An act is "valid" for exogenous evaluation if pred_exogenous is non-NA.
  # NA predictions are out-of-vocabulary labels (the model returned a label
  # not in {SPENDING_DRIVEN, COUNTERCYCLICAL, DEFICIT_DRIVEN, LONG_RUN}).
  valid <- c2_s2_results |>
    dplyr::filter(!is.na(pred_exogenous))

  n_total <- nrow(c2_s2_results)
  n_valid <- nrow(valid)
  n_na_exo <- sum(is.na(c2_s2_results$pred_exogenous))

  if (n_valid < n_total) {
    warning(sprintf(
      "%d/%d acts had NA pred_exogenous (out-of-vocabulary label) and were excluded",
      n_total - n_valid, n_total
    ))
  }

  if (n_valid == 0) {
    stop("No valid label predictions to evaluate")
  }

  # --- Exogenous metrics (binary) ---
  exo_cm <- table(
    Predicted = factor(valid$pred_exogenous, levels = c(TRUE, FALSE)),
    True = factor(valid$true_exogenous, levels = c(TRUE, FALSE))
  )

  exo_point <- compute_exo_metrics(valid$pred_exogenous, valid$true_exogenous)

  # --- Sign accuracy on true-exogenous acts ---
  sign_point <- compute_sign_metrics_on_true_exo(
    pred_sign = c2_s2_results$pred_sign,
    true_sign = c2_s2_results$true_sign,
    true_exo  = c2_s2_results$true_exogenous,
    pred_exo  = c2_s2_results$pred_exogenous
  )

  # --- Act-level bootstrap ---
  set.seed(42)
  boot_stats <- replicate(n_bootstrap, {
    boot_idx <- sample(seq_len(n_total), n_total, replace = TRUE)
    boot_data <- c2_s2_results[boot_idx, ]
    boot_valid <- boot_data |> dplyr::filter(!is.na(pred_exogenous))

    if (nrow(boot_valid) == 0) {
      e <- list(precision = NA_real_, recall = NA_real_,
                f1 = NA_real_, accuracy = NA_real_)
    } else {
      e <- compute_exo_metrics(boot_valid$pred_exogenous,
                               boot_valid$true_exogenous)
    }

    s <- compute_sign_metrics_on_true_exo(
      pred_sign = boot_data$pred_sign,
      true_sign = boot_data$true_sign,
      true_exo  = boot_data$true_exogenous,
      pred_exo  = boot_data$pred_exogenous
    )

    c(exo_precision = e$precision,
      exo_recall = e$recall,
      exo_f1 = e$f1,
      exo_accuracy = e$accuracy,
      sign_acc_on_true_exo = s$sign_accuracy,
      signed_exo_precision = s$signed_exo_precision)
  })

  alpha <- 1 - ci_level
  ci_lower <- apply(boot_stats, 1, quantile, probs = alpha / 2, na.rm = TRUE)
  ci_upper <- apply(boot_stats, 1, quantile, probs = 1 - alpha / 2, na.rm = TRUE)

  # --- Per-act results ---
  per_act_cols <- c(
    "act_name", "year", "true_motivation",
    "true_exogenous", "pred_label", "pred_exogenous", "correct_exogenous",
    "true_sign", "pred_sign", "pred_sign_raw", "correct_sign_on_true_exo",
    "confidence", "n_chunks", "n_evidence_items", "n_c2a_failures"
  )

  per_act <- c2_s2_results |>
    dplyr::mutate(
      correct_exogenous = !is.na(pred_exogenous) &
        pred_exogenous == true_exogenous,
      correct_sign_on_true_exo = dplyr::if_else(
        true_exogenous,
        !is.na(pred_sign) & pred_sign == true_sign,
        NA
      )
    ) |>
    dplyr::select(dplyr::any_of(per_act_cols)) |>
    dplyr::arrange(correct_exogenous, correct_sign_on_true_exo, act_name)

  # --- Quality flags ---
  quality_flags <- list(
    n_c2a_failures_total = sum(c2_s2_results$n_c2a_failures, na.rm = TRUE),
    n_na_exo = n_na_exo,
    n_na_pred_sign = sum(is.na(c2_s2_results$pred_sign)),
    n_na_pred_label = sum(is.na(c2_s2_results$pred_label))
  )

  list(
    # Exogenous metrics (binary)
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

    # Sign metrics (conditional on true_exogenous == TRUE)
    sign_accuracy_on_true_exo = sign_point$sign_accuracy,
    sign_accuracy_on_true_exo_ci = c(
      lower = ci_lower["sign_acc_on_true_exo"],
      upper = ci_upper["sign_acc_on_true_exo"]
    ),
    sign_confusion_matrix_on_true_exo = sign_point$confusion_matrix,
    n_true_exo = sign_point$n_true_exo,

    # Joint diagnostic: precision of (correct exo flag AND correct sign | true exogenous)
    signed_exo_precision = sign_point$signed_exo_precision,
    signed_exo_precision_ci = c(
      lower = ci_lower["signed_exo_precision"],
      upper = ci_upper["signed_exo_precision"]
    ),

    # Quarter metrics deferred to v0.9.x (enacted_quarter[] not in v0.9.1 schema)

    # Diagnostics
    per_act_results = per_act,
    quality_flags = quality_flags,
    n_total = n_total,
    n_valid = n_valid,
    n_bootstrap = n_bootstrap,
    ci_level = ci_level,
    bootstrap_unit = "act"
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


#' Compute sign accuracy on true-exogenous acts
#'
#' Sign correctness is only meaningful for acts whose ground truth is
#' exogenous (the population whose sign enters the shock series). Returns
#' (a) sign accuracy on the true-exogenous subset (denominator counts all
#' true-exogenous acts; UNCLEAR/NA pred_sign counts as incorrect), and
#' (b) signed exogenous precision: P(pred_exo == TRUE AND pred_sign matches
#' true_sign | true_exogenous == TRUE).
#'
#' @param pred_sign Character vector of predicted sign in {"+", "-", "0", "UNCLEAR", NA}
#' @param true_sign Character vector of true sign in {"+", "-", "0", NA}
#' @param true_exo Logical vector of true exogenous flag
#' @param pred_exo Logical vector of predicted exogenous flag (NA when UNCLEAR)
#' @return List with sign_accuracy, signed_exo_precision, confusion_matrix,
#'   n_true_exo
#' @keywords internal
compute_sign_metrics_on_true_exo <- function(pred_sign, true_sign,
                                             true_exo, pred_exo) {
  exo_idx <- which(isTRUE_vec(true_exo))
  n_true_exo <- length(exo_idx)

  if (n_true_exo == 0) {
    return(list(
      sign_accuracy = NA_real_,
      signed_exo_precision = NA_real_,
      confusion_matrix = NULL,
      n_true_exo = 0L
    ))
  }

  ps <- pred_sign[exo_idx]
  ts <- true_sign[exo_idx]
  pe <- pred_exo[exo_idx]

  # Sign accuracy: of acts whose ground truth is exogenous, fraction where
  # the predicted sign matches the true sign. UNCLEAR/NA pred_sign counts
  # as incorrect (the model failed to commit on a direction the shock
  # series requires).
  sign_correct <- !is.na(ps) & ps != "UNCLEAR" & ps == ts
  sign_accuracy <- mean(sign_correct, na.rm = FALSE)

  # Signed exogenous precision: of acts whose ground truth is exogenous,
  # fraction where BOTH pred_exogenous == TRUE AND pred_sign matches true_sign.
  signed_correct <- isTRUE_vec(pe) & sign_correct
  signed_exo_precision <- mean(signed_correct, na.rm = FALSE)

  # Confusion matrix: pred_sign x true_sign on the true-exogenous subset
  sign_levels <- c("+", "-", "0", "UNCLEAR")
  cm <- table(
    Predicted = factor(ifelse(is.na(ps), "NA", ps), levels = c(sign_levels, "NA")),
    True = factor(ts, levels = sign_levels)
  )

  list(
    sign_accuracy = sign_accuracy,
    signed_exo_precision = signed_exo_precision,
    confusion_matrix = cm,
    n_true_exo = n_true_exo
  )
}


# isTRUE-style vectorised helper (TRUE only when value is non-NA TRUE)
isTRUE_vec <- function(x) !is.na(x) & x


#' Convert a `YYYY-QN` quarter string to an integer index for distance arithmetic
#'
#' @param q Character vector of quarter strings (e.g., "1946-Q1"). Returns NA
#'   for malformed strings.
#' @return Integer vector: `year * 4 + (quarter - 1)`. NA where input is invalid.
#' @keywords internal
quarter_to_int <- function(q) {
  out <- rep(NA_integer_, length(q))
  ok <- !is.na(q) & grepl("^[0-9]{4}-Q[1-4]$", q)
  if (any(ok)) {
    yy <- as.integer(substr(q[ok], 1, 4))
    qn <- as.integer(substr(q[ok], 7, 7))
    out[ok] <- yy * 4L + (qn - 1L)
  }
  out
}


#' Compute per-act quarter-comparison metrics
#'
#' Given a single act's predicted and true quarter sets (each a character
#' vector of `YYYY-QN` strings, possibly empty), returns a one-row tibble
#' of metrics used by `evaluate_c2_classification()`:
#'
#' - `primary_quarter_exact`: predicted earliest == R&R primary (earliest true)
#' - `primary_quarter_within_one`: same with ±1 quarter tolerance
#' - `quarter_jaccard`: |pred ∩ true| / |pred ∪ true|; defined as 1 when
#'   both sets are empty (both correctly returned no quarters), NA when only
#'   one side is empty (asymmetric coverage)
#' - `phased_act`: TRUE when the act has ≥2 ground-truth quarters
#' - `phased_detection`: TRUE when phased and pred has ≥2 quarters; NA for
#'   non-phased acts (excluded from phased-detection-rate denominator)
#' - `n_pred_quarters`, `n_true_quarters`: cardinalities
#'
#' Both inputs are assumed to be already deduplicated and `YYYY-QN`-formatted.
#'
#' @param pred_q Character vector of predicted quarters (may be empty).
#' @param true_q Character vector of true quarters (may be empty).
#' @return A 1-row tibble with the metric columns above.
#' @keywords internal
compute_act_quarter_metrics <- function(pred_q, true_q) {
  pred_q <- if (is.null(pred_q)) character(0) else pred_q
  true_q <- if (is.null(true_q)) character(0) else true_q

  n_pred <- length(pred_q)
  n_true <- length(true_q)

  # Primary quarter: earliest in each set
  if (n_pred == 0 || n_true == 0) {
    primary_exact <- NA
    primary_within_one <- NA
  } else {
    pred_int <- sort(quarter_to_int(pred_q))
    true_int <- sort(quarter_to_int(true_q))
    pred_primary <- pred_int[1]
    true_primary <- true_int[1]
    if (is.na(pred_primary) || is.na(true_primary)) {
      primary_exact <- NA
      primary_within_one <- NA
    } else {
      primary_exact <- pred_primary == true_primary
      primary_within_one <- abs(pred_primary - true_primary) <= 1L
    }
  }

  # Jaccard
  if (n_pred == 0 && n_true == 0) {
    quarter_jaccard <- 1.0
  } else if (n_pred == 0 || n_true == 0) {
    # Asymmetric coverage: NA rather than 0, so means are not penalised
    # by acts the model legitimately skipped (or true sets we lack).
    # Phased and primary metrics already capture coverage failure.
    quarter_jaccard <- NA_real_
  } else {
    inter <- length(intersect(pred_q, true_q))
    uni   <- length(union(pred_q, true_q))
    quarter_jaccard <- if (uni > 0) inter / uni else NA_real_
  }

  phased_act <- n_true >= 2L
  phased_detection <- if (phased_act) n_pred >= 2L else NA

  tibble::tibble(
    primary_quarter_exact = primary_exact,
    primary_quarter_within_one = primary_within_one,
    quarter_jaccard = quarter_jaccard,
    phased_act = phased_act,
    phased_detection = phased_detection,
    n_pred_quarters = n_pred,
    n_true_quarters = n_true
  )
}


#' Compute aggregate quarter-set metrics over a results tibble
#'
#' @param results Tibble with `pred_quarters` and `true_quarters` list-columns
#'   plus the per-act metric columns added by `add_quarter_metrics()`.
#' @return Named list with point estimates for the four headline quarter
#'   metrics plus the (pred_n, true_n) distribution.
#' @keywords internal
summarize_quarter_metrics <- function(results) {
  n_phased <- sum(results$phased_act, na.rm = TRUE)
  n_with_both <- sum(results$n_pred_quarters > 0 & results$n_true_quarters > 0,
                     na.rm = TRUE)
  n_jaccard_defined <- sum(!is.na(results$quarter_jaccard))

  list(
    primary_quarter_exact = mean(results$primary_quarter_exact, na.rm = TRUE),
    primary_quarter_within_one = mean(results$primary_quarter_within_one,
                                       na.rm = TRUE),
    phased_act_detection_rate = if (n_phased > 0) {
      mean(results$phased_detection[results$phased_act], na.rm = TRUE)
    } else {
      NA_real_
    },
    quarter_set_jaccard = mean(results$quarter_jaccard, na.rm = TRUE),
    n_phased_acts = n_phased,
    n_with_both_quarters = n_with_both,
    n_jaccard_defined = n_jaccard_defined,
    pred_n_true_n_distribution = table(
      pred_n = results$n_pred_quarters,
      true_n = results$n_true_quarters
    )
  )
}


#' Add per-act quarter metric columns to a results tibble
#'
#' @param results Tibble with `pred_quarters` and `true_quarters` list-columns.
#' @return Same tibble with seven new columns appended (see
#'   `compute_act_quarter_metrics`).
#' @keywords internal
add_quarter_metrics <- function(results) {
  if (!"pred_quarters" %in% names(results) ||
      !"true_quarters" %in% names(results)) {
    stop("results must contain pred_quarters and true_quarters list-columns")
  }
  qm <- purrr::map2_dfr(
    results$pred_quarters, results$true_quarters,
    compute_act_quarter_metrics
  )
  dplyr::bind_cols(results, qm)
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
