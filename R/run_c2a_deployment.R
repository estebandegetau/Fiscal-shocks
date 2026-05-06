# Deployment-side C2a evidence-extraction runner.
# Counterpart to run_c2a_extraction() in R/c2_codebook_stage_2.R, with no
# ground-truth dependency. Uses C1's extracted measure_name as the
# act_name input to format_c2a_input(). Reuses format_c2a_input(),
# call_codebook_generic(), validate_c2a_output() from R/c2_behavioral_tests.R
# and construct_codebook_prompt() from R/codebook_stage_0.R.

# Null coalescing
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b


#' Run C2a evidence extraction in deployment mode
#'
#' Per-chunk extraction. Each chunk is identified by C1's `measure_name`
#' (extracted by C1 v0.6.0 alongside the FISCAL_MEASURE label) — that
#' measure_name is passed as the `act_name` input to `format_c2a_input()`,
#' replacing the ground-truth-supplied act_name used in dev.
#'
#' Chunks with `measure_name == NA` are skipped with a warning count
#' (C1 sometimes returns FISCAL_MEASURE without identifying a specific
#' measure). Empty-input safe.
#'
#' Note: this returns chunk-level evidence with no act-level aggregation.
#' Aggregation by `(measure_name, year)` and any name-canonicalization
#' across chunks is a C2b-deployment concern, deferred until the C2b
#' codebook stabilizes.
#'
#' @param c1_measures Tibble from `filter_c1_measures()`: chunks with C1
#'   outputs + chunk text (FISCAL_MEASURE + discusses_motivation == TRUE)
#' @param codebook Validated C2a codebook (`load_validate_codebook()`)
#' @param model Character model ID
#' @param max_tokens_c2a Integer max output tokens
#' @param max_retries Integer retries on validation failure
#' @param show_progress Logical
#' @param provider Character API provider
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return Tibble — one row per processed chunk: chunk_id, doc_id, country,
#'   year, measure_name, evidence (list-col), enacted_signals (list-col),
#'   timing_signals (list-col), c2a_valid, c2a_failure_reason
#' @export
run_c2a_deployment <- function(c1_measures,
                               codebook,
                               model = "claude-haiku-4-5-20251001",
                               max_tokens_c2a = 16384,
                               max_retries = 1,
                               show_progress = TRUE,
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL) {

  empty_schema <- tibble::tibble(
    chunk_id           = integer(0),
    doc_id             = character(0),
    country            = character(0),
    year               = integer(0),
    measure_name       = character(0),
    evidence           = list(),
    enacted_signals    = list(),
    timing_signals     = list(),
    c2a_valid          = logical(0),
    c2a_failure_reason = character(0)
  )

  if (nrow(c1_measures) == 0L) {
    message("C2a deployment: no FISCAL_MEASURE chunks to process (empty input)")
    return(empty_schema)
  }

  n_skipped <- sum(is.na(c1_measures$measure_name))
  if (n_skipped > 0L) {
    message(sprintf(
      "C2a deployment: skipping %d chunk(s) with NA measure_name",
      n_skipped
    ))
  }

  flat <- c1_measures |> dplyr::filter(!is.na(measure_name))
  n_chunks <- nrow(flat)

  if (n_chunks == 0L) {
    warning("C2a deployment: no chunks with non-NA measure_name to process")
    return(empty_schema)
  }

  message(sprintf(
    "C2a deployment: %d chunks across %d distinct measure_name value(s)",
    n_chunks, dplyr::n_distinct(flat$measure_name)
  ))

  c2a_system <- construct_codebook_prompt(codebook)

  attempt_call <- function(user_msg) {
    tryCatch({
      parsed <- call_codebook_generic(
        user_message = user_msg,
        codebook = codebook,
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
        list(valid = TRUE, reason = NA_character_, parsed = parsed)
      }
    }, error = function(e) {
      list(valid = FALSE, reason = e$message, parsed = NULL)
    })
  }

  results <- purrr::map_dfr(seq_len(n_chunks), function(j) {
    chunk <- flat[j, ]

    if (show_progress) {
      message(sprintf(
        "  C2a chunk %d/%d [%s] chunk_id=%s",
        j, n_chunks, chunk$measure_name, chunk$chunk_id
      ))
    }

    user_msg <- format_c2a_input(
      text = chunk$text,
      act_name = chunk$measure_name,
      year = chunk$year
    )

    c2a_result <- attempt_call(user_msg)
    if (!c2a_result$valid && max_retries >= 1L) {
      c2a_result <- attempt_call(user_msg)
    }

    if (!c2a_result$valid) {
      warning(sprintf(
        "C2a validation failed for [%s] chunk_id=%s: %s",
        chunk$measure_name, chunk$chunk_id,
        c2a_result$reason %||% "unknown"
      ))
    }

    tibble::tibble(
      chunk_id           = chunk$chunk_id,
      doc_id             = chunk$doc_id,
      country            = if ("country" %in% names(chunk)) chunk$country else NA_character_,
      year               = chunk$year,
      measure_name       = chunk$measure_name,
      evidence           = list(if (c2a_result$valid) c2a_result$parsed$evidence else list()),
      enacted_signals    = list(if (c2a_result$valid) c2a_result$parsed$enacted_signals else list()),
      timing_signals     = list(if (c2a_result$valid) c2a_result$parsed$timing_signals %||% list() else list()),
      c2a_valid          = c2a_result$valid,
      c2a_failure_reason = if (c2a_result$valid) NA_character_ else c2a_result$reason %||% NA_character_
    )
  })

  message(sprintf(
    "C2a deployment complete: %d chunk(s) — %d valid, %d failed",
    nrow(results),
    sum(results$c2a_valid),
    sum(!results$c2a_valid)
  ))

  results
}
