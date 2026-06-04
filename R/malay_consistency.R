# Malaysia EN/BM cross-language consistency test.
#
# Self-contained sub-pipeline: slices country_chunks to ER documents that have
# parallel EN+BM versions, runs its own C1 -> C0 -> C2 chain on the slice, and
# compares the FULL pipeline outputs across languages with data/statistical
# evidence only (no auxiliary-API matching).
#
# C0 (the act aggregator, M5 LLM canonical clustering) replaces the old
# within-document Jaro-Winkler clusterer. It runs at three scopes:
#   - per_doc      : aggregate within each language x year document (granular)
#   - per_language : pool all EN docs / all BM docs (deployment-realistic; this
#                    is the scope that feeds C2 and the headline timeline)
#   - joint        : pool EN+BM together (probes cross-language aggregation)
#
# The Sonnet matcher + human-curation machinery is removed: it injected an
# unverified LLM judgment into the headline. Cross-language comparison is now
# distributional (tallies of act counts, exo/endo, label marginals, act-name
# year multisets) plus two timeline figures placing each side's acts by timing,
# direction, and exogeneity.
#
# Reuses run_c1_deployment(), filter_c1_measures(), run_c2a_deployment(),
# run_c2b_classification(), build_c0_measure_pool(), run_m5_llm_clusters(),
# extract_year_from_string().


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


# Integer mode (first modal value on ties). Used for the act-level
# representative document year.
.malay_mode_int <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(NA_integer_)
  tab <- table(x)
  as.integer(names(tab)[which.max(tab)])
}


# ---------------------------------------------------------------------------
# C0 act aggregation (M5 LLM canonical clustering) at three scopes
# ---------------------------------------------------------------------------

#' Build the Malaysia C0 measure pool from filtered C1 measures
#'
#' Malaysia analog of `build_c0_measure_pool()`. `malay_er_c1_measures` already
#' carries measure_name / measure_rank (== 1L) / year / doc_id / chunk_id /
#' doc_language; we add the constant `pred_label` the pool builder filters on,
#' reuse the pool logic, and carry `doc_language` through (the pool builder
#' drops it, so we re-derive it from doc_id).
#'
#' @param c1_measures Tibble from `filter_c1_measures()`.
#' @return Tibble: measure_name, year, doc_id, chunk_id, measure_rank,
#'   n_occurrences, doc_language.
#' @export
build_malay_er_measure_pool <- function(c1_measures) {
  prepared <- c1_measures |>
    dplyr::mutate(pred_label = "FISCAL_MEASURE")

  # `filter_c1_measures()` already restricts to the rank-1 measure; older
  # cached C1 output (pre-v0.7.0 flat schema) lacks the `measure_rank` column,
  # so default it here for robustness across schema vintages.
  if (!"measure_rank" %in% names(prepared)) {
    prepared <- dplyr::mutate(prepared, measure_rank = 1L)
  }

  build_c0_measure_pool(prepared) |>
    dplyr::mutate(doc_language = derive_doc_language(doc_id))
}


# Map a measure-pool row to its scope-partition key.
.malay_scope_group <- function(measure_pool, scope) {
  switch(scope,
    per_doc      = measure_pool$doc_id,
    per_language = measure_pool$doc_language,
    joint        = rep("joint", nrow(measure_pool)),
    stop("Unknown scope: ", scope)
  )
}


#' Run C0 (M5 LLM canonical clustering) at a given scope
#'
#' Partitions the measure pool by the scope key and runs `run_m5_llm_clusters()`
#' once per partition with a single deterministic seed (multi-seed order
#' sensitivity is characterised separately in `c0_aggregator.qmd`). Cluster ids
#' are unique only within a `scope_group`; downstream joins are within group.
#'
#' Empty-input safe.
#'
#' @param measure_pool Tibble from `build_malay_er_measure_pool()`.
#' @param scope One of "per_doc", "per_language", "joint".
#' @param model,instruction,max_tokens,provider,base_url,api_key Passed to
#'   `run_m5_llm_clusters()`. `instruction` is the c0_canonicalize system prompt.
#' @param seed Integer shuffle seed (single deterministic clustering).
#' @return Tibble: scope, scope_group, variant_id, measure_name, cluster_id,
#'   canonical_name, n_members.
#' @export
run_malay_er_c0 <- function(measure_pool,
                            scope = c("per_doc", "per_language", "joint"),
                            model = "claude-haiku-4-5-20251001",
                            instruction,
                            max_tokens = 8192L,
                            provider = "anthropic",
                            base_url = NULL,
                            api_key = NULL,
                            seed = 1L) {
  scope <- match.arg(scope)

  empty <- tibble::tibble(
    scope = character(0), scope_group = character(0),
    variant_id = character(0), measure_name = character(0),
    cluster_id = integer(0), canonical_name = character(0),
    n_members = integer(0)
  )
  if (nrow(measure_pool) == 0L) return(empty)

  pool <- measure_pool |>
    dplyr::mutate(.scope_group = .malay_scope_group(measure_pool, scope))

  groups <- split(pool, pool$.scope_group)

  purrr::imap_dfr(groups, function(sub, gname) {
    sub <- dplyr::select(sub, -dplyr::any_of(".scope_group"))
    cl <- run_m5_llm_clusters(
      sub,
      model = model, instruction = instruction,
      max_tokens = max_tokens, provider = provider,
      base_url = base_url, api_key = api_key, seeds = seed
    )
    if (nrow(cl) == 0L) return(tibble::tibble())
    cl |>
      dplyr::mutate(scope = scope, scope_group = gname, .before = 1)
  })
}


#' Expand C0 cluster assignments back to chunk-level rows
#'
#' `run_m5_llm_clusters()` returns one row per (measure_name, cluster) with no
#' document / chunk / year. Join back to the measure pool on
#' (scope_group, measure_name) to recover doc_id / chunk_id / year /
#' doc_language, yielding the chunk-level cluster table downstream needs.
#'
#' Empty-input safe.
#'
#' @param c0_clusters Tibble from `run_malay_er_c0()` (single scope).
#' @param measure_pool Tibble from `build_malay_er_measure_pool()`.
#' @return Tibble: scope, scope_group, doc_language, year, doc_id, chunk_id,
#'   cluster_id, canonical_name, measure_name, n_members.
#' @export
reshape_c0_clusters_to_chunks <- function(c0_clusters, measure_pool) {
  empty <- tibble::tibble(
    scope = character(0), scope_group = character(0),
    doc_language = character(0), year = integer(0), doc_id = character(0),
    chunk_id = integer(0), cluster_id = integer(0),
    canonical_name = character(0), measure_name = character(0),
    n_members = integer(0)
  )
  if (nrow(c0_clusters) == 0L) return(empty)

  scope <- unique(c0_clusters$scope)
  stopifnot(length(scope) == 1L)

  pool <- measure_pool |>
    dplyr::mutate(scope_group = .malay_scope_group(measure_pool, scope))

  c0_clusters |>
    dplyr::distinct(scope, scope_group, measure_name, cluster_id,
                    canonical_name, n_members) |>
    dplyr::inner_join(pool, by = c("scope_group", "measure_name"),
                      relationship = "many-to-many") |>
    dplyr::transmute(scope, scope_group, doc_language, year, doc_id, chunk_id,
                     cluster_id, canonical_name, measure_name, n_members)
}


# ---------------------------------------------------------------------------
# C2b inputs: every C0 act per language (no pairing)
# ---------------------------------------------------------------------------

#' Build C2b act inputs from C0 clusters (all acts, un-paired)
#'
#' Generalised replacement for the curated-pairs aggregator. One row per
#' (cluster x member chunk) per language, joining C2a evidence list-columns by
#' (chunk_id, doc_id). Each act is given a single act-level year (regex year
#' from the canonical name when present, else the modal contributing document
#' year) so `run_c2b_classification()`'s (act_name, year) grouping keeps an act
#' together even when it spans documents. Carries act_name_year and
#' doc_year_modal as act-level constants for the timeline.
#'
#' Empty-input safe.
#'
#' @param c0_clusters_chunks Tibble from `reshape_c0_clusters_to_chunks()`.
#' @param c2a_evidence Tibble from `run_c2a_deployment()`.
#' @return Tibble: side, act_name, year, act_name_year, doc_year_modal,
#'   doc_language, canonical_name, cluster_id, chunk_id, doc_id, measure_name,
#'   evidence, enacted_signals, timing_signals, c2a_valid.
#' @export
aggregate_c0_acts_for_c2b <- function(c0_clusters_chunks, c2a_evidence) {
  empty <- tibble::tibble(
    side = character(0), act_name = character(0), year = integer(0),
    act_name_year = integer(0), doc_year_modal = integer(0),
    doc_language = character(0), canonical_name = character(0),
    cluster_id = integer(0), chunk_id = integer(0), doc_id = character(0),
    measure_name = character(0),
    evidence = list(), enacted_signals = list(), timing_signals = list(),
    c2a_valid = logical(0)
  )
  if (nrow(c0_clusters_chunks) == 0L) return(empty)

  ev <- c2a_evidence |>
    dplyr::select(chunk_id, doc_id, evidence, enacted_signals,
                  timing_signals, c2a_valid)

  joined <- c0_clusters_chunks |>
    dplyr::inner_join(ev, by = c("chunk_id", "doc_id"))

  if (nrow(joined) == 0L) return(empty)

  act_year <- joined |>
    dplyr::group_by(doc_language, cluster_id) |>
    dplyr::summarize(
      canonical_name = dplyr::first(canonical_name),
      act_name_year  = extract_year_from_string(dplyr::first(canonical_name)),
      doc_year_modal = .malay_mode_int(year),
      .groups = "drop"
    ) |>
    dplyr::mutate(act_year = dplyr::coalesce(act_name_year, doc_year_modal))

  joined |>
    dplyr::left_join(
      dplyr::select(act_year, doc_language, cluster_id,
                    act_name_year, doc_year_modal, act_year),
      by = c("doc_language", "cluster_id")
    ) |>
    dplyr::mutate(
      side = toupper(doc_language),
      act_name = sprintf("%s [%s c%d]", canonical_name, doc_language, cluster_id),
      year = act_year
    ) |>
    dplyr::select(side, act_name, year, act_name_year, doc_year_modal,
                  doc_language, canonical_name, cluster_id, chunk_id, doc_id,
                  measure_name, evidence, enacted_signals, timing_signals,
                  c2a_valid)
}


#' Run C2b on the per-language C0 act inputs (every act scored)
#'
#' Thin wrapper around `run_c2b_classification()`. Builds the stub `test_set`
#' (all ground-truth NA — Malaysia has no labels) and threads act-level metadata
#' (side, language, canonical name, the two timing-year sources) back onto the
#' per-act results. Empty-input safe.
#'
#' @param act_inputs Tibble from `aggregate_c0_acts_for_c2b()`.
#' @param c2b_codebook Validated C2b codebook object.
#' @param model,max_tokens_c2b,provider,base_url,api_key Passed through.
#' @return `run_c2b_classification()` output plus side, doc_language,
#'   canonical_name, act_name_year, doc_year_modal columns.
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
      side = character(0), doc_language = character(0),
      canonical_name = character(0),
      act_name_year = integer(0), doc_year_modal = integer(0)
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

  act_meta <- act_inputs |>
    dplyr::distinct(act_name, side, doc_language, canonical_name,
                    act_name_year, doc_year_modal)

  c2b_results |>
    dplyr::left_join(act_meta, by = "act_name")
}


# ---------------------------------------------------------------------------
# Distributional consistency tallies + timeline inventory
# ---------------------------------------------------------------------------

#' Compute the distributional consistency tallies across the three C0 scopes
#'
#' No paired matching, no bootstrap CIs — pure tallies plus the timeline
#' inventory. Returns a list of tibbles:
#'   - per_doc      : per (doc, language) C1-measure count, C0-act count, and
#'                    compression ratio (granular aggregation symmetry).
#'   - per_language : EN-vs-BM act count, exo / endo counts, motivation-label
#'                    marginal distribution, and act-name-year multiset.
#'   - joint        : cross-language merge rate (mixed / EN-only / BM-only
#'                    clusters) — the probe of whether C0 bridges languages.
#'   - inventory    : one row per (language, act) with both timing-year sources,
#'                    motivation label, sign, exogeneity, confidence — the
#'                    source for `plot_malay_act_timeline()`.
#'
#' @param c0_perdoc,c0_perlang,c0_joint Tibbles from `run_malay_er_c0()`.
#' @param c2b Tibble from `run_malay_er_c2b()`.
#' @param measure_pool Tibble from `build_malay_er_measure_pool()` (joint scope
#'   needs it to attach a language to each measure_name).
#' @return List(per_doc, per_language, joint, inventory).
#' @export
compute_malay_er_consistency_tallies <- function(c0_perdoc, c0_perlang, c0_joint,
                                                 c2b, measure_pool) {

  # ----- per_doc: acts/doc + compression ratio -----
  per_doc <- if (nrow(c0_perdoc) == 0L) {
    tibble::tibble(year = integer(0), doc_language = character(0),
                   n_measures = integer(0), n_acts = integer(0),
                   compression = double(0))
  } else {
    c0_perdoc |>
      dplyr::mutate(doc_language = derive_doc_language(scope_group),
                    year = as.integer(stringr::str_extract(scope_group, "\\d{4}"))) |>
      dplyr::group_by(year, doc_language) |>
      dplyr::summarize(
        n_measures = dplyr::n_distinct(measure_name),
        n_acts     = dplyr::n_distinct(cluster_id),
        .groups = "drop"
      ) |>
      dplyr::mutate(compression = n_measures / pmax(n_acts, 1L)) |>
      dplyr::arrange(year, doc_language)
  }

  # ----- per_language: act inventory marginals (from C2b inventory) -----
  inventory <- if (nrow(c2b) == 0L) {
    tibble::tibble(
      side = character(0), doc_language = character(0),
      canonical_name = character(0), act_name = character(0),
      act_name_year = integer(0), doc_year_modal = integer(0),
      pred_label = character(0), pred_sign = character(0),
      pred_exogenous = logical(0), confidence = character(0)
    )
  } else {
    c2b |>
      dplyr::transmute(
        side, doc_language, canonical_name, act_name,
        act_name_year, doc_year_modal,
        pred_label, pred_sign, pred_exogenous, confidence
      )
  }

  per_language <- if (nrow(inventory) == 0L) {
    list(
      counts = tibble::tibble(side = character(0), n_acts = integer(0),
                              n_exogenous = integer(0), n_endogenous = integer(0)),
      labels = tibble::tibble(side = character(0), pred_label = character(0),
                              n = integer(0)),
      act_years = tibble::tibble(side = character(0), act_name_year = integer(0),
                                 n = integer(0))
    )
  } else {
    counts <- inventory |>
      dplyr::group_by(side) |>
      dplyr::summarize(
        n_acts       = dplyr::n(),
        n_exogenous  = sum(pred_exogenous %in% TRUE),
        n_endogenous = sum(pred_exogenous %in% FALSE),
        .groups = "drop"
      )
    labels <- inventory |>
      dplyr::count(side, pred_label, name = "n")
    act_years <- inventory |>
      dplyr::filter(!is.na(act_name_year)) |>
      dplyr::count(side, act_name_year, name = "n")
    list(counts = counts, labels = labels, act_years = act_years)
  }

  # ----- joint: cross-language merge rate -----
  joint <- if (nrow(c0_joint) == 0L) {
    tibble::tibble(n_clusters = 0L, n_mixed = 0L,
                   n_en_only = 0L, n_bm_only = 0L, merge_rate = NA_real_)
  } else {
    measure_lang <- measure_pool |>
      dplyr::distinct(measure_name, doc_language)
    joint_lang <- c0_joint |>
      dplyr::distinct(cluster_id, measure_name) |>
      dplyr::left_join(measure_lang, by = "measure_name",
                       relationship = "many-to-many")
    per_cluster <- joint_lang |>
      dplyr::group_by(cluster_id) |>
      dplyr::summarize(
        has_en = any(doc_language == "en"),
        has_bm = any(doc_language == "bm"),
        .groups = "drop"
      )
    n_clusters <- nrow(per_cluster)
    n_mixed <- sum(per_cluster$has_en & per_cluster$has_bm)
    tibble::tibble(
      n_clusters = n_clusters,
      n_mixed    = n_mixed,
      n_en_only  = sum(per_cluster$has_en & !per_cluster$has_bm),
      n_bm_only  = sum(!per_cluster$has_en & per_cluster$has_bm),
      merge_rate = if (n_clusters > 0L) n_mixed / n_clusters else NA_real_
    )
  }

  list(per_doc = per_doc, per_language = per_language,
       joint = joint, inventory = inventory)
}


#' Timeline of EN- and BM-side acts by timing, direction, and exogeneity
#'
#' One point per act, placed on the year axis by the chosen timing source.
#' Faceted by language (rows EN/BM) so the reader visually compares the two
#' full-pipeline runs. Colour = motivation label; shape = sign; exogenous acts
#' are drawn solid, endogenous hollow.
#'
#' @param inventory The `inventory` tibble from
#'   `compute_malay_er_consistency_tallies()`.
#' @param timing One of "act_name" (regex year from the act name) or "doc_year"
#'   (modal source-document year).
#' @return A ggplot object (NULL if no acts have a year on the chosen axis).
#' @export
plot_malay_act_timeline <- function(inventory, timing = c("act_name", "doc_year")) {
  timing <- match.arg(timing)
  if (nrow(inventory) == 0L) return(NULL)

  year_col <- if (timing == "act_name") "act_name_year" else "doc_year_modal"
  axis_lab <- if (timing == "act_name") {
    "Year (extracted from act name)"
  } else {
    "Year (source document)"
  }

  df <- inventory |>
    dplyr::mutate(.year = .data[[year_col]],
                  side = factor(toupper(side), levels = c("EN", "BM"))) |>
    dplyr::filter(!is.na(.year))
  if (nrow(df) == 0L) return(NULL)

  ggplot2::ggplot(df, ggplot2::aes(x = .year, y = canonical_name)) +
    ggplot2::geom_point(
      ggplot2::aes(fill = pred_label, shape = pred_sign,
                   alpha = pred_exogenous),
      colour = "grey30", size = 3
    ) +
    ggplot2::scale_shape_manual(
      values = c(`+` = 24, `-` = 25, `0` = 21),
      name = "Sign", na.value = 23
    ) +
    ggplot2::scale_alpha_manual(
      values = c(`TRUE` = 1, `FALSE` = 0.35),
      breaks = c(TRUE, FALSE),
      labels = c("exogenous", "endogenous"),
      name = "Exogeneity", na.value = 0.35
    ) +
    ggplot2::facet_wrap(~ side, ncol = 1, scales = "free_y") +
    ggplot2::labs(x = axis_lab, y = NULL, fill = "Motivation") +
    ggplot2::guides(
      fill = ggplot2::guide_legend(override.aes = list(shape = 21, alpha = 1))
    ) +
    ggplot2::theme_minimal(base_family = "Libertinus Serif", base_size = 10) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
}
