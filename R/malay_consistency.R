# Malaysia EN/BM cross-language consistency test.
#
# Self-contained sub-pipeline: slices country_chunks to ER documents that have
# parallel EN+BM versions, runs its own C1 -> C2a -> C2b chain on the slice,
# clusters near-duplicate measure names within each doc, has an LLM (Sonnet)
# propose EN<->BM cluster matches for human curation, then compares C2b labels
# on the curated matched pairs.
#
# Exploratory framing: agreement rates with bootstrap 95% CIs, no PASS/FAIL.
# Reuses run_c1_deployment(), filter_c1_measures(), run_c2a_deployment(),
# run_c2b_classification(), call_llm_api(), parse_json_response().


if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b


# Vectorised: doc_id ending in "-BM" is the BM version; otherwise EN.
derive_doc_language <- function(doc_id) {
  dplyr::if_else(stringr::str_detect(doc_id, "-BM$"), "bm", "en")
}


#' Pair-year selection from the Economic Report MANIFEST
#'
#' Reads `data/manual/malaysia/economic_report/MANIFEST.csv` and returns the
#' integer vector of years where both languages are available. Dynamic so
#' that adding new pair years on disk auto-extends the test scope.
#'
#' @param manifest_path Character path to MANIFEST.csv
#' @return Integer vector of years sorted ascending
#' @export
select_malay_er_pair_years <- function(manifest_path) {
  readr::read_csv(manifest_path, show_col_types = FALSE) |>
    dplyr::filter(has_en, has_bm) |>
    dplyr::pull(year) |>
    as.integer() |>
    sort()
}


#' Slice country_chunks to ER documents with parallel EN+BM coverage
#'
#' Extracts the Malaysia branch (the single iteration-list element) and filters
#' to `MY_ECON_REPORT-<year>` + `MY_ECON_REPORT-<year>-BM` for the requested
#' pair years. Derives `doc_language` from the `-BM` suffix on doc_id. Drops
#' any pair year where one of the two sides is absent from the chunk corpus
#' (defensive against partial coverage in country_chunks).
#'
#' @param country_chunks List from the dynamic-branched `country_chunks` target.
#'   Single Malaysia element keyed by branch hash in the current config.
#' @param pair_years Integer vector from `select_malay_er_pair_years()`
#' @return Tibble with original chunk columns plus a `doc_language` column
#' @export
slice_malay_er_chunks <- function(country_chunks, pair_years) {
  malaysia <- country_chunks[[1]]  # single-country deployment
  if (is.null(malaysia) || nrow(malaysia) == 0L) {
    stop("country_chunks[[1]] is empty; expected Malaysia branch with chunks")
  }

  target_ids <- c(
    sprintf("MY_ECON_REPORT-%d", pair_years),
    sprintf("MY_ECON_REPORT-%d-BM", pair_years)
  )

  sliced <- malaysia |>
    dplyr::filter(doc_id %in% target_ids) |>
    dplyr::mutate(doc_language = derive_doc_language(doc_id))

  # Drop pair years missing one side
  by_year <- sliced |>
    dplyr::distinct(doc_id, doc_language) |>
    dplyr::mutate(yr = as.integer(stringr::str_extract(doc_id, "\\d{4}"))) |>
    dplyr::count(yr, name = "n_langs")

  kept_years <- by_year |>
    dplyr::filter(n_langs == 2L) |>
    dplyr::pull(yr)

  dropped_years <- setdiff(pair_years, kept_years)
  if (length(dropped_years) > 0L) {
    warning(sprintf(
      "Dropped pair year(s) with missing language side: %s",
      paste(dropped_years, collapse = ", ")
    ))
  }

  sliced |>
    dplyr::filter(as.integer(stringr::str_extract(doc_id, "\\d{4}")) %in% kept_years)
}


#' Cluster near-duplicate measure_name values within each document
#'
#' Single-linkage hierarchical clustering on Jaro-Winkler string distance,
#' cut at `threshold`. Returns one row per (doc_id, member) so the same
#' chunk_id can appear in only one cluster within a doc. Canonical name =
#' longest member by character length (alphabetic tiebreak — deterministic).
#'
#' Empty-input safe.
#'
#' @param c2a_evidence Tibble from `run_c2a_deployment()` with at least
#'   `chunk_id, doc_id, year, measure_name, c2a_valid`
#' @param threshold Numeric Jaro-Winkler distance cutoff (default 0.15)
#' @return Tibble `(doc_id, year, doc_language, cluster_id, canonical_name,
#'   measure_name, chunk_id, n_evidence_items)`
#' @export
cluster_measure_names_within_doc <- function(c2a_evidence, threshold = 0.15) {

  empty <- tibble::tibble(
    doc_id = character(0), year = integer(0), doc_language = character(0),
    cluster_id = integer(0), canonical_name = character(0),
    measure_name = character(0), chunk_id = integer(0),
    n_evidence_items = integer(0)
  )

  if (nrow(c2a_evidence) == 0L) return(empty)

  enriched <- c2a_evidence |>
    dplyr::filter(c2a_valid, !is.na(measure_name)) |>
    dplyr::mutate(
      doc_language = derive_doc_language(doc_id),
      n_evidence_items = purrr::map_int(evidence, length)
    )

  if (nrow(enriched) == 0L) return(empty)

  cluster_one_doc <- function(rows) {
    measures <- unique(rows$measure_name)
    if (length(measures) == 1L) {
      assignment <- tibble::tibble(measure_name = measures, cluster_id = 1L)
    } else {
      dmat <- stringdist::stringdistmatrix(measures, measures, method = "jw")
      d <- stats::as.dist(dmat)
      hc <- stats::hclust(d, method = "single")
      cl <- stats::cutree(hc, h = threshold)
      assignment <- tibble::tibble(measure_name = measures,
                                   cluster_id = as.integer(cl))
    }

    canonical <- assignment |>
      dplyr::mutate(nchar = nchar(measure_name)) |>
      dplyr::arrange(dplyr::desc(nchar), measure_name) |>
      dplyr::group_by(cluster_id) |>
      dplyr::summarize(canonical_name = dplyr::first(measure_name), .groups = "drop")

    rows |>
      dplyr::left_join(assignment, by = "measure_name") |>
      dplyr::left_join(canonical, by = "cluster_id") |>
      dplyr::select(year, doc_language, cluster_id, canonical_name,
                    measure_name, chunk_id, n_evidence_items)
  }

  enriched |>
    dplyr::group_by(doc_id) |>
    dplyr::group_modify(~ cluster_one_doc(.x)) |>
    dplyr::ungroup() |>
    dplyr::select(doc_id, year, doc_language, cluster_id, canonical_name,
                  measure_name, chunk_id, n_evidence_items)
}


# ---------------------------------------------------------------------------
# LLM-proposed candidate matches (Sonnet)
# ---------------------------------------------------------------------------

# System prompt for the matcher. Held as a constant so target hashing tracks
# any future edits.
.malay_matcher_system_prompt <- paste(
  "You are matching fiscal measures across English and Bahasa Malaysia",
  "versions of the same Malaysian Economic Report. Both lists describe the",
  "same source document's fiscal measures, one extracted from the English",
  "text and one from the Bahasa text. Identify which EN-side cluster",
  "corresponds to which BM-side cluster.",
  "",
  "Rules:",
  "- Each EN cluster may match at most one BM cluster, and vice versa.",
  "- It is acceptable for clusters to be unmatched on either side; do not",
  "  force a match if the evidence does not support one.",
  "- Confidence: 'high' = clearly the same measure; 'medium' = probably the",
  "  same; 'low' = uncertain.",
  "- Output JSON only, no prose, no markdown fences.",
  "",
  "Output schema:",
  "{\"matches\": [",
  "  {\"en_cluster_id\": int|null, \"bm_cluster_id\": int|null,",
  "   \"confidence\": \"high\"|\"medium\"|\"low\", \"rationale\": \"string\"}",
  "]}",
  "Use null on exactly one side for unmatched clusters; never null on both.",
  sep = "\n"
)


# Build the per-year user message: serialise EN and BM cluster summaries as
# compact JSON for the model to reason over.
.format_matcher_user_message <- function(year, en_summary, bm_summary) {
  payload <- list(
    year = year,
    en_clusters = en_summary,
    bm_clusters = bm_summary
  )
  jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE)
}


# One-year cluster summary builder (canonical name + up to two evidence
# excerpts per cluster, truncated for prompt-budget hygiene).
.summarise_clusters_for_year <- function(year_evidence, year_clusters) {
  excerpt_for <- function(chunk_id) {
    rec <- year_evidence |> dplyr::filter(chunk_id == .env$chunk_id)
    if (nrow(rec) == 0L) return(NULL)
    items <- rec$evidence[[1]]
    if (length(items) == 0L) return(NULL)
    purrr::map_chr(items, ~ stringr::str_trunc(.x$quote %||% "", 240))
  }

  year_clusters |>
    dplyr::group_by(cluster_id, canonical_name) |>
    dplyr::summarize(
      member_chunk_ids = list(unique(chunk_id)),
      .groups = "drop"
    ) |>
    purrr::pmap(function(cluster_id, canonical_name, member_chunk_ids) {
      excerpts <- purrr::map(member_chunk_ids, excerpt_for) |>
        purrr::compact() |>
        unlist() |>
        unique()
      list(
        cluster_id = as.integer(cluster_id),
        canonical_name = canonical_name,
        evidence_excerpts = head(excerpts, 3L)
      )
    })
}


#' Propose EN<->BM cluster matches per year using Sonnet
#'
#' For each year present in `clusters`, calls Sonnet once with the year's EN
#' and BM cluster summaries (canonical name + up to 3 evidence excerpts each)
#' and asks for proposed matches with confidence labels. Returns a long tibble
#' suitable for CSV export + human review.
#'
#' Empty-input safe; rate-limited via call_llm_api().
#'
#' @param clusters Tibble from `cluster_measure_names_within_doc()`
#' @param c2a_evidence Tibble from `run_c2a_deployment()` (needed for the
#'   evidence excerpts attached to each cluster summary)
#' @param model Character Sonnet model ID (default Sonnet 4)
#' @param max_tokens Integer max output tokens (default 4096)
#' @param max_retries Integer per-year retry limit on validation failure
#' @return Tibble: year, en_cluster_id, en_canonical_name, bm_cluster_id,
#'   bm_canonical_name, confidence, rationale, match_status
#' @export
propose_en_bm_match_candidates <- function(clusters,
                                           c2a_evidence,
                                           model = "claude-sonnet-4-20250514",
                                           max_tokens = 4096L,
                                           max_retries = 1L) {

  empty <- tibble::tibble(
    year = integer(0),
    en_cluster_id = integer(0), en_canonical_name = character(0),
    bm_cluster_id = integer(0), bm_canonical_name = character(0),
    confidence = character(0), rationale = character(0),
    match_status = character(0)
  )

  if (nrow(clusters) == 0L) return(empty)

  # run_c2a_deployment() does not emit a doc_language column; derive from
  # the -BM suffix on doc_id so the per-language filters below have something
  # to match on. Same pattern as aggregate_act_evidence_for_c2b().
  ev <- c2a_evidence |>
    dplyr::mutate(doc_language = derive_doc_language(doc_id))

  years <- sort(unique(clusters$year))

  results <- purrr::map_dfr(years, function(yr) {
    yr_clusters <- clusters |> dplyr::filter(year == yr)
    yr_evidence <- ev |> dplyr::filter(year == yr)

    en_clusters <- yr_clusters |> dplyr::filter(doc_language == "en")
    bm_clusters <- yr_clusters |> dplyr::filter(doc_language == "bm")

    if (nrow(en_clusters) == 0L || nrow(bm_clusters) == 0L) {
      warning(sprintf(
        "Year %d: one side has no clusters (en=%d, bm=%d); skipping matcher call",
        yr, nrow(en_clusters), nrow(bm_clusters)
      ))
      return(tibble::tibble())
    }

    en_summary <- .summarise_clusters_for_year(
      yr_evidence |> dplyr::filter(doc_language == "en"), en_clusters
    )
    bm_summary <- .summarise_clusters_for_year(
      yr_evidence |> dplyr::filter(doc_language == "bm"), bm_clusters
    )

    user_msg <- .format_matcher_user_message(yr, en_summary, bm_summary)

    parsed <- NULL
    for (attempt in seq_len(1L + max_retries)) {
      # Inter-retry backoff: skip on first attempt; otherwise sleep 2^attempt
      # seconds before retrying. Mirrors the backoff inside call_claude_api()
      # and prevents tight retry loops from compounding rate-limit pressure.
      if (attempt > 1L) Sys.sleep(min(60, 2^attempt))

      result <- tryCatch({
        raw <- call_llm_api(
          messages = list(list(role = "user", content = user_msg)),
          model = model,
          max_tokens = max_tokens,
          temperature = 0,
          system = .malay_matcher_system_prompt,
          provider = "anthropic"
        )
        txt <- raw$content[[1]]$text
        p <- parse_json_response(txt)
        if (is.null(p$matches) || !is.list(p$matches)) {
          list(ok = FALSE, parsed = p, reason = "missing matches field")
        } else {
          list(ok = TRUE, parsed = p, reason = NA_character_)
        }
      }, error = function(e) list(ok = FALSE, parsed = NULL, reason = e$message))

      if (result$ok) { parsed <- result$parsed; break }
    }

    if (is.null(parsed)) {
      warning(sprintf("Matcher failed for year %d after %d attempts: %s",
                      yr, 1L + max_retries, result$reason %||% "unknown"))
      return(tibble::tibble())
    }

    en_lookup <- en_clusters |>
      dplyr::distinct(cluster_id, canonical_name) |>
      dplyr::rename(en_cluster_id = cluster_id,
                    en_canonical_name = canonical_name)
    bm_lookup <- bm_clusters |>
      dplyr::distinct(cluster_id, canonical_name) |>
      dplyr::rename(bm_cluster_id = cluster_id,
                    bm_canonical_name = canonical_name)

    purrr::map_dfr(parsed$matches, function(m) {
      en_id <- if (is.null(m$en_cluster_id)) NA_integer_ else as.integer(m$en_cluster_id)
      bm_id <- if (is.null(m$bm_cluster_id)) NA_integer_ else as.integer(m$bm_cluster_id)
      status <- dplyr::case_when(
        !is.na(en_id) & !is.na(bm_id) ~ "proposed",
        !is.na(en_id) & is.na(bm_id)  ~ "en_unmatched",
        is.na(en_id)  & !is.na(bm_id) ~ "bm_unmatched",
        TRUE                          ~ "invalid"
      )
      tibble::tibble(
        year = yr,
        en_cluster_id = en_id,
        en_canonical_name = if (!is.na(en_id)) {
          en_lookup$en_canonical_name[match(en_id, en_lookup$en_cluster_id)]
        } else NA_character_,
        bm_cluster_id = bm_id,
        bm_canonical_name = if (!is.na(bm_id)) {
          bm_lookup$bm_canonical_name[match(bm_id, bm_lookup$bm_cluster_id)]
        } else NA_character_,
        confidence = m$confidence %||% NA_character_,
        rationale = m$rationale %||% NA_character_,
        match_status = status
      )
    })
  })

  results
}


#' Write the candidates tibble to CSV for human review
#'
#' Trivial; exists so the target carries a `format = "file"` dependency on
#' the on-disk artefact.
#'
#' @param candidates Tibble from `propose_en_bm_match_candidates()`
#' @param path Character target path (will be created if directory missing)
#' @return Character path
#' @export
write_malay_er_candidates_csv <- function(candidates, path) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  readr::write_csv(candidates, path, na = "")
  path
}


#' Ensure the curated matches CSV exists, initialising an empty stub if absent
#'
#' On first pipeline run the curated CSV does not yet exist on disk.
#' `format = "file"` requires the path to be present, so this helper writes a
#' header-only stub (zero data rows) when the file is missing. Existing
#' curated files are never overwritten — human edits are preserved across
#' pipeline runs.
#'
#' `candidates_path` is unused inside the function; it is threaded through so
#' that targets registers a dependency edge from the curated-file target to
#' the candidates-file target, ensuring the stub is only initialised after
#' Sonnet has produced candidates worth curating.
#'
#' @param curated_path Character path to the curated CSV
#' @param candidates_path Character path to the candidates CSV (dependency only)
#' @return Character `curated_path`
#' @export
ensure_curated_matches_file <- function(curated_path, candidates_path) {
  if (!file.exists(curated_path)) {
    dir.create(dirname(curated_path), showWarnings = FALSE, recursive = TRUE)
    stub <- tibble::tibble(
      year = integer(0),
      en_cluster_id = integer(0),
      bm_cluster_id = integer(0),
      match_status = character(0),
      notes = character(0)
    )
    readr::write_csv(stub, curated_path, na = "")
  }
  curated_path
}


#' Load human-curated matches or return empty stub
#'
#' Returns an empty tibble (with the curated-schema columns) when the curated
#' CSV has no rows tagged `match_status = "curated"`. This is the graceful-skip
#' mechanism that lets Levels 1-2 of the notebook render without forcing
#' curation to be done before Level 3. Both the header-only stub initialised
#' by `ensure_curated_matches_file()` and a verbatim copy of the candidates
#' CSV (where all rows carry `match_status = "proposed"`) resolve to the empty
#' stub via the `match_status == "curated"` filter.
#'
#' Curated schema (what the human edits to): year, en_cluster_id,
#' bm_cluster_id, match_status, notes. `match_status` should be set to
#' "curated" on rows the human kept as true matches; anything else is
#' ignored downstream.
#'
#' @param curated_path Character path to the curated CSV (file-target value)
#' @return Tibble of curated matches (zero rows if not yet curated)
#' @export
load_curated_matches_or_stub <- function(curated_path) {

  empty <- tibble::tibble(
    year = integer(0),
    en_cluster_id = integer(0),
    bm_cluster_id = integer(0),
    match_status = character(0),
    notes = character(0)
  )

  # Defensive: ensure_curated_matches_file() should have created the stub,
  # but keep this guard so the loader is safe to call standalone.
  if (!file.exists(curated_path)) return(empty)

  curated <- readr::read_csv(curated_path, show_col_types = FALSE)

  required <- c("year", "en_cluster_id", "bm_cluster_id", "match_status")
  missing <- setdiff(required, names(curated))
  if (length(missing) > 0L) {
    stop("Curated matches CSV missing required columns: ",
         paste(missing, collapse = ", "))
  }

  if (nrow(curated) == 0L) return(empty)

  curated |>
    dplyr::filter(match_status == "curated",
                  !is.na(en_cluster_id), !is.na(bm_cluster_id)) |>
    dplyr::mutate(
      year = as.integer(year),
      en_cluster_id = as.integer(en_cluster_id),
      bm_cluster_id = as.integer(bm_cluster_id),
      notes = if ("notes" %in% names(curated)) as.character(notes) else NA_character_
    ) |>
    dplyr::select(year, en_cluster_id, bm_cluster_id, match_status, notes)
}


#' Aggregate per-side chunk-level evidence for C2b classification
#'
#' For each curated match, emits one row per (cluster x member chunk) for
#' each side (EN and BM independently) with a synthetic `act_name` that
#' encodes language and year. This mirrors the chunk-level layout that
#' `run_c2b_classification()` expects.
#'
#' Empty-input safe.
#'
#' @param curated_matches Tibble from `load_curated_matches_or_stub()`
#' @param clusters Tibble from `cluster_measure_names_within_doc()`
#' @param c2a_evidence Tibble from `run_c2a_deployment()` — needed for the
#'   evidence list-columns (clusters has only chunk IDs)
#' @return Tibble: pair_id (int), side ("EN"|"BM"), act_name, year, chunk_id,
#'   doc_id, doc_language, measure_name, evidence, enacted_signals,
#'   timing_signals, c2a_valid
#' @export
aggregate_act_evidence_for_c2b <- function(curated_matches, clusters,
                                           c2a_evidence) {

  empty <- tibble::tibble(
    pair_id = integer(0), side = character(0),
    act_name = character(0), year = integer(0),
    chunk_id = integer(0), doc_id = character(0),
    doc_language = character(0), measure_name = character(0),
    evidence = list(), enacted_signals = list(),
    timing_signals = list(), c2a_valid = logical(0)
  )

  if (nrow(curated_matches) == 0L) return(empty)

  ev <- c2a_evidence |>
    dplyr::mutate(doc_language = derive_doc_language(doc_id))

  pairs <- curated_matches |>
    dplyr::mutate(pair_id = dplyr::row_number())

  build_side <- function(side_label, lang, cluster_col) {
    pairs |>
      dplyr::select(pair_id, year, cluster_id = !!cluster_col) |>
      dplyr::inner_join(
        clusters |> dplyr::filter(doc_language == lang) |>
          dplyr::select(year, cluster_id, canonical_name, chunk_id, doc_id,
                        measure_name, doc_language),
        by = c("year", "cluster_id")
      ) |>
      dplyr::inner_join(
        ev |> dplyr::select(chunk_id, doc_id, evidence, enacted_signals,
                            timing_signals, c2a_valid),
        by = c("chunk_id", "doc_id")
      ) |>
      dplyr::mutate(
        side = side_label,
        act_name = sprintf("%s [%s %d]", canonical_name, doc_language, year)
      ) |>
      dplyr::select(pair_id, side, act_name, year, chunk_id, doc_id,
                    doc_language, measure_name, evidence, enacted_signals,
                    timing_signals, c2a_valid)
  }

  dplyr::bind_rows(
    build_side("EN", "en", "en_cluster_id"),
    build_side("BM", "bm", "bm_cluster_id")
  )
}


#' Run C2b on the aggregated act inputs (EN and BM sides each scored)
#'
#' Thin wrapper around `run_c2b_classification()`. Builds the stub `test_set`
#' that the dev-side function expects for joining ground-truth columns
#' (here all NA — Malaysia has no labels). Empty-input safe.
#'
#' @param act_inputs Tibble from `aggregate_act_evidence_for_c2b()`
#' @param c2b_codebook Validated C2b codebook object
#' @param model Character model ID (default deployment Haiku)
#' @param max_tokens_c2b Integer
#' @param api_key Optional API key
#' @return Tibble from `run_c2b_classification()` plus side / pair_id columns
#'   threaded back from the act_name encoding
#' @export
run_malay_er_c2b <- function(act_inputs,
                             c2b_codebook,
                             model = "claude-haiku-4-5-20251001",
                             max_tokens_c2b = 4096L,
                             provider = "anthropic",
                             base_url = NULL,
                             api_key = NULL) {

  if (nrow(act_inputs) == 0L) {
    return(tibble::tibble(
      act_name = character(0), year = integer(0),
      pred_label = character(0), pred_exogenous = logical(0),
      pred_sign = character(0), confidence = character(0),
      reasoning = character(0), c2b_raw_response = character(0),
      side = character(0), pair_id = integer(0)
    ))
  }

  stub_test_set <- act_inputs |>
    dplyr::distinct(act_name, year) |>
    dplyr::mutate(
      true_motivation = NA_character_,
      true_exogenous  = NA,
      true_sign       = NA_character_,
      true_quarters   = NA_character_
    )

  c2b_results <- run_c2b_classification(
    c2b_codebook = c2b_codebook,
    c2a_results = act_inputs,
    test_set = stub_test_set,
    model = model,
    max_tokens_c2b = max_tokens_c2b,
    provider = provider,
    base_url = base_url,
    api_key = api_key
  )

  side_map <- act_inputs |>
    dplyr::distinct(act_name, side, pair_id)

  c2b_results |>
    dplyr::left_join(side_map, by = "act_name")
}


# Percentile bootstrap CI for a binary 0/1 vector. Returns (lo, hi) on the
# rate scale. Handles n == 0 by returning (NA, NA). Sandboxes RNG via
# withr::with_seed so the global random stream is unaffected.
.bootstrap_rate_ci <- function(x, n_boot = 1000L, seed = 1L, ci = 0.95) {
  x <- as.numeric(x)
  if (length(x) == 0L) return(c(lo = NA_real_, hi = NA_real_))
  reps <- withr::with_seed(
    seed,
    replicate(n_boot, mean(sample(x, length(x), replace = TRUE)))
  )
  alpha <- (1 - ci) / 2
  c(lo = unname(stats::quantile(reps, alpha)),
    hi = unname(stats::quantile(reps, 1 - alpha)))
}


#' Compute the three-level consistency metrics with bootstrap CIs
#'
#' Returns a list of tibbles: `level1` per-year cluster counts and signed
#' drift; `level2` overall match rate (curated / proposed) with CI; `level3`
#' label and sign agreement rates with CIs plus a confusion matrix; and
#' `per_pair` one row per matched pair with side-by-side labels / signs.
#'
#' Empty-input safe at each level: if curation is pending, level2/level3 are
#' empty tibbles and the notebook will surface "curation pending" banners.
#'
#' @param c1_results Tibble from `run_c1_deployment()` on the slice
#' @param c2b_results Tibble from `run_malay_er_c2b()`
#' @param curated_matches Tibble from `load_curated_matches_or_stub()`
#' @param candidates Tibble from `propose_en_bm_match_candidates()` (used to
#'   compute match rate vs proposed and human-override count)
#' @param clusters Tibble from `cluster_measure_names_within_doc()`
#' @param n_boot Integer bootstrap replicates (default 1000)
#' @param seed Integer RNG seed
#' @return List(level1, level2, level3, per_pair)
#' @export
compute_malay_er_consistency_metrics <- function(c1_results,
                                                 c2b_results,
                                                 curated_matches,
                                                 candidates,
                                                 clusters,
                                                 n_boot = 1000L,
                                                 seed = 20260514L) {

  # ----- Level 1: cluster counts per year, per language -----
  level1_empty <- tibble::tibble(
    year = integer(0),
    n_clusters_en = integer(0), n_clusters_bm = integer(0),
    signed_drift = integer(0), drift_pct = double(0)
  )

  level1 <- if (nrow(clusters) == 0L) {
    level1_empty
  } else {
    wide <- clusters |>
      dplyr::distinct(year, doc_language, cluster_id) |>
      dplyr::count(year, doc_language, name = "n_clusters") |>
      tidyr::pivot_wider(names_from = doc_language, values_from = n_clusters,
                         names_prefix = "n_clusters_", values_fill = 0L)
    # Ensure both language columns exist even when one side is missing
    for (col in c("n_clusters_en", "n_clusters_bm")) {
      if (!col %in% names(wide)) wide[[col]] <- 0L
    }
    wide |>
      dplyr::mutate(
        signed_drift = n_clusters_bm - n_clusters_en,
        drift_pct = ifelse(pmax(n_clusters_en, n_clusters_bm) > 0,
                           signed_drift / pmax(n_clusters_en, n_clusters_bm),
                           NA_real_)
      ) |>
      dplyr::arrange(year)
  }

  # ----- Level 2: match rate and override diagnostics -----
  proposed_pairs <- candidates |>
    dplyr::filter(match_status == "proposed") |>
    nrow()

  curated_pairs <- nrow(curated_matches)

  level2 <- if (curated_pairs == 0L && proposed_pairs == 0L) {
    tibble::tibble(
      n_proposed = 0L, n_curated = 0L,
      match_rate = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
      n_human_overrides = NA_integer_
    )
  } else {
    overrides <- if (curated_pairs == 0L) NA_integer_ else {
      candidates |>
        dplyr::filter(match_status == "proposed") |>
        dplyr::anti_join(
          curated_matches |> dplyr::select(year, en_cluster_id, bm_cluster_id),
          by = c("year", "en_cluster_id", "bm_cluster_id")
        ) |>
        nrow()
    }
    rate <- if (proposed_pairs > 0L) curated_pairs / proposed_pairs else NA_real_
    binary <- c(rep(1L, curated_pairs),
                rep(0L, max(0L, proposed_pairs - curated_pairs)))
    ci <- .bootstrap_rate_ci(binary, n_boot = n_boot, seed = seed)
    tibble::tibble(
      n_proposed = proposed_pairs,
      n_curated = curated_pairs,
      match_rate = rate,
      ci_lo = ci[["lo"]], ci_hi = ci[["hi"]],
      n_human_overrides = overrides
    )
  }

  # ----- Level 3: per-pair classification agreement -----
  per_pair_empty <- tibble::tibble(
    pair_id = integer(0), year = integer(0),
    en_act_name = character(0), bm_act_name = character(0),
    en_label = character(0), bm_label = character(0),
    en_sign = character(0), bm_sign = character(0),
    en_confidence = character(0), bm_confidence = character(0),
    label_agree = logical(0), sign_agree = logical(0),
    both_high_confidence = logical(0)
  )

  if (nrow(c2b_results) == 0L) {
    level3_empty <- tibble::tibble(
      n_pairs = 0L,
      label_agreement = NA_real_, label_ci_lo = NA_real_, label_ci_hi = NA_real_,
      sign_agreement  = NA_real_, sign_ci_lo  = NA_real_, sign_ci_hi  = NA_real_
    )
    return(list(level1 = level1, level2 = level2,
                level3 = level3_empty, per_pair = per_pair_empty,
                confusion = tibble::tibble()))
  }

  en_rows <- c2b_results |> dplyr::filter(side == "EN") |>
    dplyr::select(pair_id, year, en_act_name = act_name,
                  en_label = pred_label, en_sign = pred_sign,
                  en_confidence = confidence)
  bm_rows <- c2b_results |> dplyr::filter(side == "BM") |>
    dplyr::select(pair_id, bm_act_name = act_name,
                  bm_label = pred_label, bm_sign = pred_sign,
                  bm_confidence = confidence)

  per_pair <- en_rows |>
    dplyr::inner_join(bm_rows, by = "pair_id") |>
    dplyr::mutate(
      label_agree = !is.na(en_label) & !is.na(bm_label) & en_label == bm_label,
      sign_agree  = !is.na(en_sign)  & !is.na(bm_sign)  & en_sign  == bm_sign,
      both_high_confidence = identical(en_confidence, "high") &
                             identical(bm_confidence, "high")
    )

  if (nrow(per_pair) == 0L) {
    return(list(level1 = level1, level2 = level2,
                level3 = tibble::tibble(n_pairs = 0L),
                per_pair = per_pair_empty,
                confusion = tibble::tibble()))
  }

  label_ci <- .bootstrap_rate_ci(per_pair$label_agree,
                                 n_boot = n_boot, seed = seed)
  sign_ci  <- .bootstrap_rate_ci(per_pair$sign_agree,
                                 n_boot = n_boot, seed = seed + 1L)

  level3 <- tibble::tibble(
    n_pairs = nrow(per_pair),
    label_agreement = mean(per_pair$label_agree),
    label_ci_lo = label_ci[["lo"]], label_ci_hi = label_ci[["hi"]],
    sign_agreement = mean(per_pair$sign_agree),
    sign_ci_lo = sign_ci[["lo"]], sign_ci_hi = sign_ci[["hi"]]
  )

  confusion <- per_pair |>
    dplyr::count(en_label, bm_label, name = "n") |>
    tidyr::complete(en_label = unique(en_rows$en_label),
                    bm_label = unique(bm_rows$bm_label),
                    fill = list(n = 0L))

  list(level1 = level1, level2 = level2, level3 = level3,
       per_pair = per_pair, confusion = confusion)
}
