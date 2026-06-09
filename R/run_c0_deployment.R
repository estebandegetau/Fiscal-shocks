# C0 Act Aggregator — production deployment wrappers
#
# Continues the main per-country deployment chain past `country_c2a_evidence`.
# Each country branch is one whole-country measure pool, so C0 pools the entire
# country jointly (EN + BM together for Malaysia) in a single M5 LLM clustering
# call — one deduplicated cross-language act inventory per country.
#
# These are deployment-specific wrappers (cf. run_c1_deployment.R,
# run_c2a_deployment.R): decisions are hardcoded (single seed, joint pool, clean
# act names). They do NOT carry the EN/BM scope machinery of the malay_er_*
# consistency sub-pipeline (run_malay_er_c0 / reshape_c0_clusters_to_chunks /
# aggregate_c0_acts_for_c2b), which remain the reference for the join + act-year
# logic mirrored here.
#
# Reused primitives from c0_aggregator.R: build_c0_measure_pool(),
# run_m5_llm_clusters(), extract_year_from_string(), .mode_int(). Every function
# is empty-input safe (a country with zero domestic fiscal measures yields an
# empty branch, which must return a typed empty tibble rather than error — an
# unguarded empty branch aborts the whole tar_make).


#' Build the per-country C0 measure pool from filtered C1 measures
#'
#' Thin wrapper over `build_c0_measure_pool()`. `filter_c1_measures()` already
#' restricts to rank-1 domestic FISCAL_MEASURE rows; we re-stamp `pred_label`
#' and default `measure_rank` for robustness across schema vintages (pre-v0.7.0
#' cached C1 output lacks `measure_rank`), mirroring
#' `build_malay_er_measure_pool()`.
#'
#' Empty-input safe (delegates to `build_c0_measure_pool()`).
#'
#' @param c1_measures Tibble from `filter_c1_measures()`.
#' @return Tibble: measure_name, year, doc_id, chunk_id, measure_rank,
#'   n_occurrences.
#' @export
build_country_measure_pool <- function(c1_measures) {
  prepared <- c1_measures |>
    dplyr::mutate(pred_label = "FISCAL_MEASURE")

  if (!"measure_rank" %in% names(prepared)) {
    prepared <- dplyr::mutate(prepared, measure_rank = 1L)
  }

  build_c0_measure_pool(prepared)
}


#' Run C0 (M5 LLM canonical clustering) on a whole-country measure pool
#'
#' Single deterministic clustering call (one seed) over the entire country pool,
#' jointly across languages. Unlike C1 deployment, the C0 canonicalize prompt is
#' country-agnostic (no `{country_iso}` token), so no `country_iso` argument is
#' needed. Multi-seed order-sensitivity is characterised separately in
#' `c0_aggregator.qmd`.
#'
#' Empty-input safe: returns the empty cluster schema WITHOUT an API call when
#' the pool is empty.
#'
#' @param measure_pool Tibble from `build_country_measure_pool()`.
#' @param instruction Character C0 canonicalize system prompt
#'   (`c0_m5_prompt$instruction`).
#' @param model Character model ID.
#' @param max_tokens Integer max output tokens.
#' @param seed Integer shuffle seed (single deterministic clustering).
#' @param provider,base_url,api_key Passed to `run_m5_llm_clusters()`.
#' @return Tibble: variant_id, measure_name, cluster_id, canonical_name,
#'   n_members (with "integrity" attribute from `run_m5_llm_clusters()`).
#' @export
run_c0_deployment <- function(measure_pool,
                              instruction,
                              model = "claude-haiku-4-5-20251001",
                              max_tokens = 8192L,
                              seed = 1L,
                              provider = "anthropic",
                              base_url = NULL,
                              api_key = NULL) {
  empty <- tibble::tibble(
    variant_id = character(0), measure_name = character(0),
    cluster_id = integer(0), canonical_name = character(0),
    n_members = integer(0)
  )
  if (nrow(measure_pool) == 0L) {
    message("C0 deployment: empty measure pool, skipping clustering")
    return(empty)
  }

  run_m5_llm_clusters(
    measure_pool,
    model = model, instruction = instruction,
    max_tokens = max_tokens, provider = provider,
    base_url = base_url, api_key = api_key, seeds = seed
  )
}


#' Expand C0 cluster assignments back to chunk-level rows
#'
#' `run_c0_deployment()` returns one row per (measure_name, cluster) with no
#' document / chunk / year. Join back to the measure pool on `measure_name`
#' (single country pool — no scope_group, unlike the malay reference) to recover
#' doc_id / chunk_id / year, yielding the chunk-level cluster table the C2b-input
#' merge needs.
#'
#' Empty-input safe.
#'
#' @param c0_clusters Tibble from `run_c0_deployment()`.
#' @param measure_pool Tibble from `build_country_measure_pool()`.
#' @return Tibble: year, doc_id, chunk_id, cluster_id, canonical_name,
#'   measure_name, n_members.
#' @export
reshape_c0_clusters_deployment <- function(c0_clusters, measure_pool) {
  empty <- tibble::tibble(
    year = integer(0), doc_id = character(0), chunk_id = integer(0),
    cluster_id = integer(0), canonical_name = character(0),
    measure_name = character(0), n_members = integer(0)
  )
  if (nrow(c0_clusters) == 0L || nrow(measure_pool) == 0L) return(empty)

  c0_clusters |>
    dplyr::distinct(measure_name, cluster_id, canonical_name, n_members) |>
    dplyr::inner_join(
      measure_pool |> dplyr::select(measure_name, year, doc_id, chunk_id),
      by = "measure_name",
      relationship = "many-to-many"
    ) |>
    dplyr::transmute(year, doc_id, chunk_id, cluster_id, canonical_name,
                     measure_name, n_members)
}


#' Build C2b act inputs by merging C0 acts with C2a evidence
#'
#' One row per (cluster × member chunk), joining C2a evidence list-columns by
#' (chunk_id, doc_id). Each act gets a single act-level year (regex year from
#' the canonical name when present, else the modal contributing-document year)
#' so `run_c2b_classification()`'s (act_name, year) grouping keeps an act
#' together even when it spans documents.
#'
#' `act_name = "<canonical_name> [c<cluster_id>]"`: the cluster-id suffix
#' disambiguates two distinct clusters that happen to select the same canonical
#' surface form, which would otherwise be wrongly merged by the (act_name, year)
#' grouping. `cluster_id` is unique within the single country-pool clustering
#' call, so the suffix is sufficient. Bare `canonical_name` is carried through
#' for the human-facing inventory.
#'
#' Rows with `c2a_valid == FALSE` (empty evidence) are kept so the downstream
#' `n_c2a_failures` count stays accurate, mirroring the malay reference.
#'
#' Empty-input safe.
#'
#' @param c0_acts Tibble from `reshape_c0_clusters_deployment()`.
#' @param c2a_evidence Tibble from `run_c2a_deployment()`.
#' @return Tibble: act_name, year, act_name_year, doc_year_modal,
#'   canonical_name, cluster_id, chunk_id, doc_id, measure_name, evidence,
#'   enacted_signals, timing_signals, c2a_valid.
#' @export
aggregate_c0_acts_deployment <- function(c0_acts, c2a_evidence) {
  empty <- tibble::tibble(
    act_name = character(0), year = integer(0),
    act_name_year = integer(0), doc_year_modal = integer(0),
    canonical_name = character(0), cluster_id = integer(0),
    chunk_id = integer(0), doc_id = character(0), measure_name = character(0),
    evidence = list(), enacted_signals = list(), timing_signals = list(),
    c2a_valid = logical(0)
  )
  if (nrow(c0_acts) == 0L) return(empty)

  ev <- c2a_evidence |>
    dplyr::select(chunk_id, doc_id, evidence, enacted_signals,
                  timing_signals, c2a_valid)

  joined <- c0_acts |>
    dplyr::inner_join(ev, by = c("chunk_id", "doc_id"))

  if (nrow(joined) == 0L) return(empty)

  act_year <- joined |>
    dplyr::group_by(cluster_id) |>
    dplyr::summarize(
      canonical_name = dplyr::first(canonical_name),
      act_name_year  = extract_year_from_string(dplyr::first(canonical_name)),
      doc_year_modal = .mode_int(year),
      .groups = "drop"
    ) |>
    dplyr::mutate(act_year = dplyr::coalesce(act_name_year, doc_year_modal))

  joined |>
    dplyr::left_join(
      dplyr::select(act_year, cluster_id, act_name_year, doc_year_modal,
                    act_year),
      by = "cluster_id"
    ) |>
    dplyr::mutate(
      act_name = sprintf("%s [c%d]", canonical_name, cluster_id),
      year = act_year
    ) |>
    dplyr::select(act_name, year, act_name_year, doc_year_modal,
                  canonical_name, cluster_id, chunk_id, doc_id, measure_name,
                  evidence, enacted_signals, timing_signals, c2a_valid)
}


# =============================================================================
# Streaming C0 deployment variants
#
# Purely additive twins of run_c0_deployment() / run_m5_llm_clusters() /
# .run_m5_one_seed(). Each is a line-for-line copy of its original with a single
# swapped call: the API request goes through the streaming `call_claude_api_stream()`
# instead of the non-streaming `call_llm_api()`. This lets slow, high-`max_tokens`
# models (e.g. claude-sonnet-4-6 at max_tokens = 64000) stream their response
# instead of buffering it into a connection that the idle timeout drops mid-flight.
#
# Output contract is identical to the non-streaming chain — tibble (variant_id,
# measure_name, cluster_id, canonical_name, n_members) with the "integrity"
# attribute — so reshape_c0_clusters_deployment() consumes it unchanged. Only the
# model and the transport differ from the Haiku path; the cluster-assembly logic
# is byte-identical, keeping the Sonnet-vs-Haiku comparison apples-to-apples.
# All reused helpers (build_m5_user_message, prepare_m5_input, parse_json_response,
# .coerce_m5_records, .empty_m5_clusters) are sourced globally and untouched.
# =============================================================================

#' Streaming twin of `run_c0_deployment()`
#'
#' Identical signature and empty-pool guard; delegates to the streaming
#' `run_m5_llm_clusters_stream()`. See `run_c0_deployment()` for parameter docs.
#' @keywords internal
#' @export
run_c0_deployment_stream <- function(measure_pool,
                                     instruction,
                                     model = "claude-sonnet-4-6",
                                     max_tokens = 8192L,
                                     seed = 1L,
                                     provider = "anthropic",
                                     base_url = NULL,
                                     api_key = NULL) {
  empty <- tibble::tibble(
    variant_id = character(0), measure_name = character(0),
    cluster_id = integer(0), canonical_name = character(0),
    n_members = integer(0)
  )
  if (nrow(measure_pool) == 0L) {
    message("C0 deployment (stream): empty measure pool, skipping clustering")
    return(empty)
  }

  run_m5_llm_clusters_stream(
    measure_pool,
    model = model, instruction = instruction,
    max_tokens = max_tokens, provider = provider,
    base_url = base_url, api_key = api_key, seeds = seed
  )
}


#' Streaming twin of `run_m5_llm_clusters()`
#'
#' Line-for-line copy of `run_m5_llm_clusters()` that maps the streaming
#' `.run_m5_one_seed_stream()` over seeds. See `run_m5_llm_clusters()` for docs.
#' @keywords internal
run_m5_llm_clusters_stream <- function(measure_pool, model, instruction,
                                       max_tokens = 8192, temperature = 0,
                                       provider = "anthropic", base_url = NULL,
                                       api_key = NULL, seeds = 1:5) {
  m5_input <- prepare_m5_input(measure_pool)

  results <- purrr::map(seeds, function(s) {
    .run_m5_one_seed_stream(m5_input, s, model, instruction, max_tokens,
                            temperature, provider, base_url, api_key)
  })

  clusters  <- purrr::map_dfr(results, "clusters")
  integrity <- purrr::map_dfr(results, "integrity")
  attr(clusters, "integrity") <- integrity
  clusters
}


#' Streaming twin of `.run_m5_one_seed()`
#'
#' Line-for-line copy of `.run_m5_one_seed()` with the single non-streaming
#' `call_llm_api()` call replaced by the streaming `call_claude_api_stream()`
#' (anthropic-only; `provider`/`base_url`/`api_key` are accepted for signature
#' parity but unused on the stream path, exactly as `call_llm_api()` ignores them
#' for the anthropic provider). Everything else is identical.
#' @keywords internal
.run_m5_one_seed_stream <- function(m5_input, seed, model, instruction, max_tokens,
                                    temperature, provider, base_url, api_key) {
  variant_id <- sprintf("m5_haiku_namesyear_s%d", seed)
  expected   <- m5_input$surface_id

  ord       <- withr::with_seed(seed, sample.int(nrow(m5_input)))
  user_msg  <- build_m5_user_message(m5_input[ord, , drop = FALSE])

  resp <- call_claude_api_stream(
    messages    = list(list(role = "user", content = user_msg)),
    model       = model,
    max_tokens  = max_tokens,
    temperature = temperature,
    system      = instruction
  )
  stop_reason <- resp$stop_reason %||% NA_character_
  text        <- tryCatch(resp$content[[1]]$text, error = function(e) "")
  parsed      <- parse_json_response(text)
  records     <- if (!is.null(parsed$error)) NULL else .coerce_m5_records(parsed)

  empty_integrity <- function(parse_ok) {
    tibble::tibble(variant_id = variant_id, seed = seed,
                   n_expected = length(expected), n_returned = 0L,
                   n_missing = length(expected), n_extra = 0L,
                   parse_ok = parse_ok, stop_reason = stop_reason)
  }
  if (is.null(records)) {
    warning(sprintf("M5 seed %d: could not parse a {id, cluster} array", seed))
    return(list(clusters = .empty_m5_clusters(), integrity = empty_integrity(FALSE)))
  }

  assign_df <- purrr::map_dfr(records, function(e) {
    tibble::tibble(surface_id  = suppressWarnings(as.integer(e[["id"]])),
                   raw_cluster = as.character(e[["cluster"]]))
  }) |>
    dplyr::filter(!is.na(surface_id)) |>
    dplyr::distinct(surface_id, .keep_all = TRUE)

  n_returned  <- nrow(assign_df)
  n_extra     <- sum(!assign_df$surface_id %in% expected)
  assign_df   <- assign_df |> dplyr::filter(surface_id %in% expected)
  missing_ids <- setdiff(expected, assign_df$surface_id)

  filled <- dplyr::bind_rows(
    assign_df,
    tibble::tibble(surface_id  = missing_ids,
                   raw_cluster = paste0("__singleton_", missing_ids))
  ) |>
    dplyr::mutate(cluster_id = as.integer(factor(raw_cluster))) |>
    dplyr::left_join(m5_input, by = "surface_id")

  canon <- filled |>
    dplyr::arrange(dplyr::desc(n_occurrences),
                   dplyr::desc(nchar(measure_name)), measure_name) |>
    dplyr::group_by(cluster_id) |>
    dplyr::summarize(canonical_name = dplyr::first(measure_name),
                     n_members = dplyr::n(), .groups = "drop")

  clusters <- filled |>
    dplyr::left_join(canon, by = "cluster_id") |>
    dplyr::transmute(variant_id = variant_id,
                     measure_name, cluster_id, canonical_name, n_members)

  integrity <- tibble::tibble(
    variant_id = variant_id, seed = seed, n_expected = length(expected),
    n_returned = n_returned, n_missing = length(missing_ids), n_extra = n_extra,
    parse_ok = TRUE, stop_reason = stop_reason)

  list(clusters = clusters, integrity = integrity)
}
