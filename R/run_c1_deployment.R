# Deployment-side C1 pipeline helpers.
# Counterparts to the dev-side targets, with no ground-truth dependencies.
# Reuses construct_codebook_prompt() and classify_with_codebook() from
# R/codebook_stage_0.R.

# Null coalescing (guard against missing definition when sourced standalone)
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b


#' Filter C1 predictions to chunks for downstream C2a deployment
#'
#' Keeps chunks with `pred_label == "FISCAL_MEASURE"` AND
#' `discusses_motivation == TRUE` (mirrors US dev primary condition;
#' see `c2_input_data` target in `_targets.R`). Joins back original chunk
#' text and metadata so downstream C2a can read both prediction + text.
#'
#' @param predictions Tibble from `run_c1_deployment()`
#' @param chunks Tibble from `make_chunks()` with doc_id, chunk_id, text,
#'   year, country, source, doc_language, ...
#' @return Tibble with C1 outputs + chunk text, filtered to FISCAL_MEASURE
#'   AND discusses_motivation == TRUE
#' @export
filter_c1_measures <- function(predictions, chunks) {
  if (nrow(predictions) == 0L) {
    return(predictions |> dplyr::mutate(text = character(0)))
  }

  meta_cols <- intersect(
    c("country", "source", "doc_language", "year"),
    names(chunks)
  )

  # Boundary pre-filter for the C1 v0.7.0 → C2a handoff.
  # `predictions` is long-form (one row per chunk × measure under v0.7.0).
  # C2a (v0.5.0) still consumes one (chunk, measure_name) per call; restrict
  # to `measure_rank == 1L` to preserve v0.6.0 single-name semantics until
  # C2a v0.6.0 (Step 5 of the C0 sequencing plan) consumes the full array.
  # After this filter, `discusses_motivation` refers to the most prominent
  # measure's flag — a deliberate semantic shift inherited from selecting
  # `measures[0]` as the prominent measure.
  #
  # Foreign-comparator drop: C1's per-measure `measure_country` enum is either
  # the corpus country's own ISO or "OTHER" (a measure enacted by another
  # government, cited as a comparator). Both downstream consumers — C2a evidence
  # extraction and the C0 act aggregator — must only ever see domestic measures,
  # so we drop "OTHER" here at the single chokepoint. The `%in%` form is NA-safe:
  # a FISCAL_MEASURE whose country tag failed to parse (NA) is kept rather than
  # silently discarded.
  predictions |>
    dplyr::filter(
      pred_label == "FISCAL_MEASURE",
      measure_rank == 1L,
      discusses_motivation %in% TRUE,
      !measure_country %in% "OTHER"
    ) |>
    dplyr::left_join(
      chunks |> dplyr::select(dplyr::all_of(c("doc_id", "chunk_id", "text", meta_cols))),
      by = c("doc_id", "chunk_id"),
      suffix = c("", ".chunk")
    )
}


#' Run C1 measure-identification on all chunks (deployment, no ground truth)
#'
#' Per-chunk single-pass classifier. Counterpart to `run_zero_shot()` in
#' `R/codebook_stage_2.R` — same model wrapper, no `true_label` /
#' `text_type` / `correct` columns, no Tier sampling. Returns long-form
#' rows (one per chunk × measure) per C1 v0.7.0 schema; chunk-level fields
#' repeat across the chunk's rows, `measure_rank` identifies most-prominent
#' (1L) vs. secondary measures, NOT_FISCAL_MEASURE / parse_failure emit a
#' single row with NA measure fields.
#'
#' Empty-input safe.
#'
#' @param chunks Tibble from `make_chunks()` with chunk_id, doc_id, text,
#'   year, country, ...
#' @param codebook Validated C1 codebook object (`load_validate_codebook()`)
#' @param country_iso Character ISO-style code (e.g. "MY" for Malaysia) for
#'   runtime `{country_iso}` substitution and per-measure `country` enum
#'   validation. Defaults to "US"; deployment branches should pass the
#'   value from `build_country_configs()`.
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param show_progress Logical
#' @param max_retries Integer retries on API failure
#' @param use_cache Logical prompt-caching flag
#' @param provider Character API provider (default "anthropic")
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return Long-form tibble: one row per (chunk × measure). Columns include
#'   chunk-level fields (chunk_id, doc_id, country [corpus country, not
#'   measure country], year, pred_label, reasoning, raw_response,
#'   stop_reason, confidence) and per-measure fields (measure_name,
#'   measure_country, discusses_motivation, discusses_timing,
#'   discusses_magnitude, measure_rank, parse_failure).
#' @export
run_c1_deployment <- function(chunks,
                              codebook,
                              country_iso = "US",
                              model = "claude-haiku-4-5-20251001",
                              max_tokens = 1024,
                              show_progress = TRUE,
                              max_retries = 10,
                              use_cache = TRUE,
                              provider = "anthropic",
                              base_url = NULL,
                              api_key = NULL) {

  empty_schema <- tibble::tibble(
    chunk_id             = integer(0),
    doc_id               = character(0),
    country              = character(0),
    year                 = integer(0),
    pred_label           = character(0),
    measure_name         = character(0),
    measure_country      = character(0),
    discusses_motivation = logical(0),
    discusses_timing     = logical(0),
    discusses_magnitude  = logical(0),
    measure_rank         = integer(0),
    parse_failure        = logical(0),
    confidence           = numeric(0),
    reasoning            = character(0),
    raw_response         = character(0),
    stop_reason          = character(0),
    model                = character(0),
    provider             = character(0)
  )

  if (nrow(chunks) == 0L) {
    message("C1 deployment: no chunks to classify (empty input)")
    return(empty_schema)
  }

  n_chunks <- nrow(chunks)
  country_label <- if ("country" %in% names(chunks)) {
    paste(unique(chunks$country), collapse = ", ")
  } else {
    "unknown"
  }
  message(sprintf(
    "C1 deployment: %d chunks (corpus = %s, country_iso = %s)",
    n_chunks, country_label, country_iso
  ))

  system_prompt <- construct_codebook_prompt(codebook, country_iso = country_iso)

  pb <- NULL
  if (show_progress) {
    pb <- progress::progress_bar$new(
      format = "  C1 deploy [:bar] :current/:total (:percent) eta: :eta",
      total = n_chunks,
      clear = FALSE
    )
  }

  results <- purrr::map_dfr(seq_len(n_chunks), function(j) {
    if (!is.null(pb)) pb$tick()

    pred <- tryCatch({
      classify_with_codebook(
        text = chunks$text[j],
        codebook = codebook,
        few_shot_examples = list(),
        model = model,
        temperature = 0,
        use_self_consistency = FALSE,
        system_prompt = system_prompt,
        max_tokens = max_tokens,
        max_retries = max_retries,
        use_cache = use_cache,
        provider = provider,
        base_url = base_url,
        api_key = api_key,
        country_iso = country_iso
      )
    }, error = function(e) {
      list(label = NA_character_, reasoning = e$message,
           confidence = NA_real_, raw_response = NA_character_,
           stop_reason = NA_character_, measures = list(),
           parse_failure = TRUE)
    })

    base_row <- tibble::tibble(
      chunk_id     = chunks$chunk_id[j],
      doc_id       = chunks$doc_id[j],
      country      = if ("country" %in% names(chunks)) chunks$country[j] else NA_character_,
      year         = if ("year" %in% names(chunks)) chunks$year[j] else NA_integer_,
      pred_label   = pred$label %||% NA_character_,
      confidence   = pred$confidence %||% NA_real_,
      reasoning    = pred$reasoning %||% NA_character_,
      raw_response = pred$raw_response %||% NA_character_,
      stop_reason  = pred$stop_reason %||% NA_character_
    )

    fan_measures_long(
      base_row,
      measures = pred$measures %||% list(),
      parse_failure = isTRUE(pred$parse_failure)
    )
  })

  results <- results |> dplyr::mutate(model = model, provider = provider)

  chunk_results <- results |>
    dplyr::distinct(chunk_id, doc_id, .keep_all = TRUE)
  n_measures <- sum(chunk_results$pred_label == "FISCAL_MEASURE", na.rm = TRUE)
  prominent_motivation_flags <- results |>
    dplyr::filter(measure_rank == 1L) |>
    dplyr::pull(discusses_motivation)
  n_motivation <- sum(prominent_motivation_flags %in% TRUE, na.rm = TRUE)
  n_parse_failures <- sum(chunk_results$parse_failure, na.rm = TRUE)
  message(sprintf(
    "C1 deployment complete: %d FISCAL_MEASURE / %d chunks (%.1f%%); %d prominent measures with discusses_motivation == TRUE; %d parse_failure",
    n_measures, n_chunks,
    100 * n_measures / max(n_chunks, 1L),
    n_motivation, n_parse_failures
  ))

  results
}
