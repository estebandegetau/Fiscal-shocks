# Deployment-side C1 pipeline helpers.
# Counterparts to the dev-side targets, with no ground-truth dependencies.
# Reuses construct_codebook_prompt() and classify_with_codebook() from
# R/codebook_stage_0.R.

# Null coalescing (guard against missing definition when sourced standalone)
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b


#' Extract text for a country, empty-input safe
#'
#' Thin wrapper around `pull_text_local()` that returns an empty schema
#' tibble when the URL vector is empty (the underlying function errors
#' on empty input). Lets the deployment pipeline parse and run end-to-end
#' even before country-specific URLs are populated.
#'
#' @param pdf_url Character vector of PDF URLs (may be length 0)
#' @param ... Forwarded to `pull_text_local()`
#' @return Tibble matching `pull_text_local()` schema; 0 rows if input empty
#' @export
pull_country_text <- function(pdf_url, ...) {
  if (length(pdf_url) == 0L) {
    return(tibble::tibble(
      text            = list(),
      n_pages         = integer(0),
      ocr_used        = logical(0),
      extraction_time = numeric(0),
      extracted_at    = as.POSIXct(character(0))
    ))
  }
  pull_text_local(pdf_url = pdf_url, ...)
}


#' Bind URL metadata with extracted text into a country body tibble
#'
#' Mirrors `us_body <- us_urls |> bind_cols(us_text)` from `_targets.R`,
#' but country-agnostic and used inside dynamic branches. Empty-input safe.
#'
#' @param urls Tibble from `get_country_urls()` — one row per PDF URL
#' @param text Tibble from `pull_country_text()` — one row per PDF
#' @return Tibble with all `urls` columns + text/n_pages/ocr_used/...
#' @export
bind_country_body <- function(urls, text) {
  if (nrow(urls) == 0L) {
    return(dplyr::bind_cols(urls, text))
  }
  dplyr::bind_cols(urls, text)
}


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

  predictions |>
    dplyr::filter(
      pred_label == "FISCAL_MEASURE",
      discusses_motivation %in% TRUE
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
#' `text_type` / `correct` columns, no Tier sampling. Returns chunk-level
#' predictions plus C1 v0.6.0's extracted `measure_name` and the three
#' relevance flags (`discusses_motivation`, `discusses_timing`,
#' `discusses_magnitude`).
#'
#' Empty-input safe.
#'
#' @param chunks Tibble from `make_chunks()` with chunk_id, doc_id, text,
#'   year, country, ...
#' @param codebook Validated C1 codebook object (`load_validate_codebook()`)
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param show_progress Logical
#' @param max_retries Integer retries on API failure
#' @param use_cache Logical prompt-caching flag
#' @param provider Character API provider (default "anthropic")
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return Tibble — one row per chunk: chunk_id, doc_id, country, year,
#'   pred_label, measure_name, discusses_motivation, discusses_timing,
#'   discusses_magnitude, confidence, reasoning, raw_response, stop_reason,
#'   model, provider
#' @export
run_c1_deployment <- function(chunks,
                              codebook,
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
    discusses_motivation = logical(0),
    discusses_timing     = logical(0),
    discusses_magnitude  = logical(0),
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
  message(sprintf("C1 deployment: %d chunks (%s)", n_chunks, country_label))

  system_prompt <- construct_codebook_prompt(codebook)

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
        api_key = api_key
      )
    }, error = function(e) {
      list(label = NA_character_, reasoning = e$message,
           confidence = NA_real_, raw_response = NA_character_,
           stop_reason = NA_character_, measure_name = NA_character_,
           discusses_motivation = NA, discusses_timing = NA,
           discusses_magnitude = NA)
    })

    tibble::tibble(
      chunk_id             = chunks$chunk_id[j],
      doc_id               = chunks$doc_id[j],
      country              = if ("country" %in% names(chunks)) chunks$country[j] else NA_character_,
      year                 = if ("year" %in% names(chunks)) chunks$year[j] else NA_integer_,
      pred_label           = pred$label %||% NA_character_,
      measure_name         = pred$measure_name %||% NA_character_,
      discusses_motivation = pred$discusses_motivation %||% NA,
      discusses_timing     = pred$discusses_timing %||% NA,
      discusses_magnitude  = pred$discusses_magnitude %||% NA,
      confidence           = pred$confidence %||% NA_real_,
      reasoning            = pred$reasoning %||% NA_character_,
      raw_response         = pred$raw_response %||% NA_character_,
      stop_reason          = pred$stop_reason %||% NA_character_
    )
  })

  results <- results |> dplyr::mutate(model = model, provider = provider)

  n_measures <- sum(results$pred_label == "FISCAL_MEASURE", na.rm = TRUE)
  n_motivation <- sum(results$discusses_motivation %in% TRUE, na.rm = TRUE)
  message(sprintf(
    "C1 deployment complete: %d FISCAL_MEASURE / %d total (%.1f%%); %d with discusses_motivation == TRUE",
    n_measures, n_chunks,
    100 * n_measures / max(n_chunks, 1L),
    n_motivation
  ))

  results
}
