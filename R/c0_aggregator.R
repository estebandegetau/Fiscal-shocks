# C0 Act Aggregator — empirical design notebook support
#
# Builds the US measure-name pool and gold pairs from c1_s2_results, runs
# corpus-wide JW single-linkage clustering at a grid of thresholds (with and
# without ±year_window blocking), and evaluates predicted partitions against
# the gold standard with pairwise P/R/F1, Adjusted Rand Index, purity, and
# asymmetric over/under-merge counts (bootstrap 95% CIs resampled over gold
# act groups, not pairs, since pairs share names and are not iid).
#
# Phase A only: deterministic, no API cost. Phase B (embeddings, LLM judge,
# stateful builder) lives in separate files when added.


# ---------------------------------------------------------------------------
# Input shaping
# ---------------------------------------------------------------------------

#' Build the corpus-wide measure-name pool to cluster
#'
#' Pool is the deployment-realistic input: all FISCAL_MEASURE rows at any
#' measure_rank. Surface-form variance is what C0 has to canonicalize, so we
#' keep duplicates collapsed at (measure_name, year, doc_id) level.
#'
#' @param c1_s2_results Long-form C1 v0.7.0 output (one row per chunk x
#'   measure). Must include columns: measure_name, year, doc_id, chunk_id,
#'   pred_label, measure_rank.
#' @return Tibble: measure_name, year, doc_id, chunk_id, measure_rank,
#'   n_occurrences (per distinct measure_name across the pool).
#' @export
build_c0_measure_pool <- function(c1_s2_results) {
  base <- c1_s2_results |>
    dplyr::filter(pred_label == "FISCAL_MEASURE",
                  !is.na(measure_name),
                  nchar(measure_name) > 0L)

  occ <- base |>
    dplyr::count(measure_name, name = "n_occurrences")

  base |>
    dplyr::distinct(measure_name, year, doc_id, chunk_id, measure_rank) |>
    dplyr::left_join(occ, by = "measure_name") |>
    dplyr::arrange(measure_name, year, doc_id)
}


#' Build (measure_name, gold_act_name) evaluation pairs
#'
#' Two tiers of trust:
#'   - "tier1": rank == 1 chunks whose gold tag was a verbatim passage match.
#'             Cleanest signal but small (~60 rows).
#'   - "tier12": rank == 1 chunks for Tier 1 OR Tier 2. More noise (Tier 2
#'             tags can be mentions of an act other than the rank-1 measure)
#'             but more statistical power.
#'
#' Ambiguous names (one measure_name → multiple gold acts) are flagged in
#' the `ambiguous` column for the evaluator to drop or majority-vote.
#'
#' @param c1_s2_results See `build_c0_measure_pool()`.
#' @return Tibble: measure_name, gold_act_name, tier, eval_tier
#'   (factor: "tier1" or "tier12"), year, doc_id, chunk_id, ambiguous.
#' @export
build_c0_eval_gold_pairs <- function(c1_s2_results) {
  base <- c1_s2_results |>
    dplyr::filter(measure_rank == 1L,
                  pred_label == "FISCAL_MEASURE",
                  !is.na(act_name),
                  tier %in% c(1L, 2L),
                  !is.na(measure_name),
                  nchar(measure_name) > 0L) |>
    dplyr::transmute(measure_name, gold_act_name = act_name,
                     tier, year, doc_id, chunk_id)

  ambiguous_set <- base |>
    dplyr::distinct(measure_name, gold_act_name) |>
    dplyr::count(measure_name) |>
    dplyr::filter(n > 1L) |>
    dplyr::pull(measure_name)

  base |>
    dplyr::mutate(ambiguous = measure_name %in% ambiguous_set)
}


# ---------------------------------------------------------------------------
# JW single-linkage clustering (corpus-wide; optional year-window blocking)
# ---------------------------------------------------------------------------

#' Corpus-wide single-linkage clustering on Jaro-Winkler distance
#'
#' Generalizes the per-doc clustering pattern in
#' R/malay_consistency.R::cluster_measure_names_within_doc to a single
#' partition across the full pool. With `year_window = NULL` runs unblocked
#' hclust over the full distance matrix; with `year_window = k` builds a
#' sparse edge graph keeping only same-pair edges whose `|year_a - year_b| <= k`
#' AND `jw_distance <= threshold`, then takes `igraph::components()`.
#'
#' Canonical name per cluster: longest member (alphabetical tiebreak),
#' matching the malay_consistency convention.
#'
#' @param measure_pool Output of `build_c0_measure_pool()`. Year-blocking
#'   uses min(year) per measure_name; a single name appearing in multiple
#'   years is treated as belonging to its earliest year for blocking only.
#' @param threshold Numeric in (0, 1]; merge edges with JW <= threshold.
#' @param year_window Integer or NULL. If integer, only pairs within
#'   ±year_window are eligible to merge.
#' @return Tibble: measure_name, cluster_id (integer), canonical_name,
#'   threshold, year_window (NA when NULL), n_members.
#' @export
cluster_measure_names_corpus <- function(measure_pool,
                                         threshold,
                                         year_window = NULL) {

  stopifnot(is.numeric(threshold), threshold > 0, threshold <= 1)
  if (!is.null(year_window)) stopifnot(year_window >= 0L)

  name_year <- measure_pool |>
    dplyr::group_by(measure_name) |>
    dplyr::summarize(year_min = suppressWarnings(min(year, na.rm = TRUE)),
                     .groups = "drop") |>
    dplyr::mutate(year_min = dplyr::if_else(is.finite(year_min),
                                            as.integer(year_min),
                                            NA_integer_))

  names_vec <- name_year$measure_name
  n <- length(names_vec)

  if (n == 0L) {
    return(.empty_cluster_tibble(threshold, year_window))
  }
  if (n == 1L) {
    return(tibble::tibble(
      measure_name = names_vec,
      cluster_id = 1L,
      canonical_name = names_vec,
      threshold = threshold,
      year_window = year_window %||% NA_integer_,
      n_members = 1L
    ))
  }

  dmat <- stringdist::stringdistmatrix(names_vec, names_vec, method = "jw")

  if (is.null(year_window)) {
    cl <- stats::cutree(stats::hclust(stats::as.dist(dmat), method = "single"),
                        h = threshold)
  } else {
    # Sparse graph: edges with JW <= threshold AND |year_a - year_b| <= window
    years <- name_year$year_min
    edges <- which(dmat <= threshold & upper.tri(dmat), arr.ind = TRUE)
    if (nrow(edges) > 0L) {
      eligible <- abs(years[edges[, 1]] - years[edges[, 2]]) <= year_window
      eligible[is.na(eligible)] <- FALSE  # missing year => never merge
      edges <- edges[eligible, , drop = FALSE]
    }
    g <- igraph::make_empty_graph(n, directed = FALSE)
    if (nrow(edges) > 0L) {
      g <- igraph::add_edges(g, as.vector(t(edges)))
    }
    cl <- igraph::components(g)$membership
  }

  assignment <- tibble::tibble(measure_name = names_vec,
                               cluster_id = as.integer(cl))

  canonical <- assignment |>
    dplyr::mutate(nchar = nchar(measure_name)) |>
    dplyr::arrange(dplyr::desc(nchar), measure_name) |>
    dplyr::group_by(cluster_id) |>
    dplyr::summarize(canonical_name = dplyr::first(measure_name),
                     n_members = dplyr::n(),
                     .groups = "drop")

  assignment |>
    dplyr::left_join(canonical, by = "cluster_id") |>
    dplyr::mutate(threshold = threshold,
                  year_window = year_window %||% NA_integer_)
}

.empty_cluster_tibble <- function(threshold, year_window) {
  tibble::tibble(
    measure_name = character(0),
    cluster_id = integer(0),
    canonical_name = character(0),
    threshold = numeric(0),
    year_window = integer(0),
    n_members = integer(0)
  )
}


#' Run JW clustering across a (threshold x year_window) grid
#'
#' Returns one long tibble with grid columns so a single downstream evaluator
#' call can stratify.
#'
#' @param measure_pool See `cluster_measure_names_corpus()`.
#' @param thresholds Numeric vector of thresholds to sweep.
#' @param year_windows List of values for `year_window`; use `NULL` for no
#'   blocking. Example: `list(NULL, 2L)`.
#' @return Tibble with columns: variant_id (factor), threshold, year_window,
#'   measure_name, cluster_id, canonical_name, n_members.
#' @export
run_jw_clusters_grid <- function(measure_pool,
                                 thresholds = c(0.10, 0.15, 0.20, 0.25, 0.30),
                                 year_windows = list(NULL, 2L)) {

  grid <- tidyr::expand_grid(
    threshold = thresholds,
    year_window_idx = seq_along(year_windows)
  )

  purrr::pmap_dfr(grid, function(threshold, year_window_idx) {
    yw <- year_windows[[year_window_idx]]
    cl <- cluster_measure_names_corpus(measure_pool,
                                       threshold = threshold,
                                       year_window = yw)
    cl |>
      dplyr::mutate(
        variant_id = sprintf("jw_t%.2f_%s",
                             threshold,
                             if (is.null(yw)) "unblocked"
                             else sprintf("yw%d", yw))
      )
  })
}


# ---------------------------------------------------------------------------
# Cluster evaluation: pairwise P/R/F1, ARI, purity, over/under-merge
# ---------------------------------------------------------------------------

#' Evaluate a single predicted partition against gold pairs
#'
#' Resolves ambiguous gold by majority vote on (measure_name, gold_act_name)
#' frequency; drops names that have no gold mapping at all.
#'
#' Pairwise metrics are computed over the C(n, 2) pairs of gold-labeled names.
#' Bootstrap resamples the **gold rows** (chunks) with replacement; within
#' each resample, ambiguous-gold majority vote is re-resolved so the
#' contingency table operates on unique names (no double-counting inflation).
#' Variance reflects which chunks ended up in the eval set — the right
#' uncertainty to quantify for a sample of US documents.
#'
#' Pairs are not iid (they share names), so the resulting CI is approximate;
#' use as a noise floor, not a hypothesis test.
#'
#' @param predicted Tibble with (measure_name, cluster_id). Names not in
#'   `gold` are ignored.
#' @param gold Tibble from `build_c0_eval_gold_pairs()`. Filter to
#'   `eval_tier` upstream of this function (the function does not filter).
#' @param n_boot Integer, bootstrap replicates (default 1000).
#' @param seed Integer seed for the bootstrap (default 20260521).
#' @return List with scalar metrics (point + CI lo/hi):
#'   pairwise_precision, pairwise_recall, pairwise_f1, ari, purity,
#'   over_merge_count, under_merge_count, n_names, n_gold_acts,
#'   n_predicted_clusters.
#' @export
evaluate_clusters_vs_gold <- function(predicted, gold,
                                      n_boot = 1000L,
                                      seed = 20260521L) {

  predicted_distinct <- predicted |>
    dplyr::distinct(measure_name, cluster_id)

  resolve_join <- function(gold_rows) {
    resolved <- gold_rows |>
      dplyr::count(measure_name, gold_act_name, name = "freq") |>
      dplyr::group_by(measure_name) |>
      dplyr::slice_max(freq, n = 1L, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::select(measure_name, gold_act_name)
    resolved |>
      dplyr::inner_join(predicted_distinct, by = "measure_name")
  }

  joined <- resolve_join(gold)
  if (nrow(joined) < 2L) {
    return(.empty_metrics_list())
  }

  point <- .compute_partition_metrics(joined$cluster_id,
                                      joined$gold_act_name)

  boot <- withr::with_seed(seed, {
    n_rows <- nrow(gold)
    replicate(n_boot, {
      idx <- sample.int(n_rows, n_rows, replace = TRUE)
      resampled <- gold[idx, , drop = FALSE]
      j <- resolve_join(resampled)
      if (nrow(j) < 2L) return(.empty_metrics_point())
      .compute_partition_metrics(j$cluster_id, j$gold_act_name)
    }, simplify = FALSE)
  })

  ci <- .summarise_bootstrap(boot)

  c(point,
    list(ci = ci,
         n_names = nrow(joined),
         n_gold_acts = dplyr::n_distinct(joined$gold_act_name),
         n_predicted_clusters = dplyr::n_distinct(joined$cluster_id)))
}


# Worker: compute scalar metrics from two equal-length label vectors.
.compute_partition_metrics <- function(pred, gold) {

  pred <- as.character(pred)
  gold <- as.character(gold)
  n <- length(pred)
  if (n < 2L) return(.empty_metrics_point())

  ct <- table(pred, gold)

  pair_sum <- function(x) sum(choose(x, 2L))
  tp <- pair_sum(ct)
  pred_pairs <- pair_sum(rowSums(ct))
  gold_pairs <- pair_sum(colSums(ct))
  total_pairs <- choose(n, 2L)
  fp <- pred_pairs - tp
  fn <- gold_pairs - tp
  tn <- total_pairs - tp - fp - fn

  precision <- if (pred_pairs > 0L) tp / pred_pairs else NA_real_
  recall    <- if (gold_pairs > 0L) tp / gold_pairs else NA_real_
  f1 <- if (!is.na(precision) && !is.na(recall) && (precision + recall) > 0)
    2 * precision * recall / (precision + recall) else NA_real_

  # Adjusted Rand Index (Hubert-Arabie). Computed from the contingency table
  # without an extra package dependency.
  index <- tp
  expected <- pred_pairs * gold_pairs / total_pairs
  max_index <- (pred_pairs + gold_pairs) / 2
  ari <- if ((max_index - expected) != 0)
    (index - expected) / (max_index - expected) else NA_real_

  # Purity: per cluster, max-class share; weighted by cluster size.
  purity <- sum(apply(ct, 1L, max)) / n

  list(
    pairwise_precision = precision,
    pairwise_recall = recall,
    pairwise_f1 = f1,
    ari = ari,
    purity = purity,
    over_merge_count = fp,
    under_merge_count = fn,
    true_positive_pairs = tp,
    true_negative_pairs = tn
  )
}


.empty_metrics_point <- function() {
  list(pairwise_precision = NA_real_, pairwise_recall = NA_real_,
       pairwise_f1 = NA_real_, ari = NA_real_, purity = NA_real_,
       over_merge_count = NA_integer_, under_merge_count = NA_integer_,
       true_positive_pairs = NA_integer_, true_negative_pairs = NA_integer_)
}


.empty_metrics_list <- function() {
  c(.empty_metrics_point(),
    list(ci = NULL, n_names = 0L, n_gold_acts = 0L, n_predicted_clusters = 0L))
}


.summarise_bootstrap <- function(boot_list) {
  metric_names <- c("pairwise_precision", "pairwise_recall", "pairwise_f1",
                    "ari", "purity")
  out <- purrr::map(metric_names, function(m) {
    vals <- purrr::map_dbl(boot_list, ~ .x[[m]] %||% NA_real_)
    vals <- vals[is.finite(vals)]
    if (length(vals) == 0L) return(c(lo = NA_real_, hi = NA_real_))
    stats::quantile(vals, probs = c(0.025, 0.975), names = FALSE) |>
      stats::setNames(c("lo", "hi"))
  })
  stats::setNames(out, metric_names)
}


#' Evaluate a grid of predicted partitions
#'
#' Iterates `evaluate_clusters_vs_gold()` over grouping keys in `predicted_grid`
#' (e.g., variant_id, threshold, year_window). Returns one long tibble of
#' metrics suitable for direct tabling/plotting.
#'
#' Runs the evaluator separately under each `eval_tier` slice of `gold`:
#' "tier1" (clean signal) and "tier12" (more power). Both are returned in the
#' output, distinguished by an `eval_tier` column.
#'
#' @param predicted_grid Output of `run_jw_clusters_grid()` or analog with
#'   grouping columns and (measure_name, cluster_id).
#' @param gold Output of `build_c0_eval_gold_pairs()`.
#' @param group_keys Character vector of columns in `predicted_grid` to
#'   stratify over (defaults to "variant_id").
#' @param n_boot Bootstrap replicates per (group, eval_tier) cell.
#' @return Long tibble with columns: eval_tier, group_keys..., metric, value,
#'   ci_lo, ci_hi, plus counts (n_names, n_gold_acts, n_predicted_clusters,
#'   over_merge_count, under_merge_count).
#' @export
evaluate_clusters_grid <- function(predicted_grid, gold,
                                   group_keys = "variant_id",
                                   n_boot = 1000L,
                                   seed = 20260521L) {

  stopifnot(all(group_keys %in% names(predicted_grid)))

  gold_tier1 <- gold |> dplyr::filter(tier == 1L)
  gold_tier12 <- gold

  eval_one <- function(pred_df, gold_df, eval_tier) {
    res <- evaluate_clusters_vs_gold(pred_df, gold_df,
                                     n_boot = n_boot, seed = seed)
    ci <- res$ci %||% list()
    tibble::tibble(
      eval_tier = eval_tier,
      metric = c("pairwise_precision", "pairwise_recall", "pairwise_f1",
                 "ari", "purity"),
      value = c(res$pairwise_precision, res$pairwise_recall,
                res$pairwise_f1, res$ari, res$purity),
      ci_lo = purrr::map_dbl(metric, ~ ci[[.x]]["lo"] %||% NA_real_),
      ci_hi = purrr::map_dbl(metric, ~ ci[[.x]]["hi"] %||% NA_real_),
      n_names = res$n_names,
      n_gold_acts = res$n_gold_acts,
      n_predicted_clusters = res$n_predicted_clusters,
      over_merge_count = res$over_merge_count,
      under_merge_count = res$under_merge_count
    )
  }

  predicted_grid |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_keys))) |>
    dplyr::group_modify(function(pred_df, key) {
      dplyr::bind_rows(
        eval_one(pred_df, gold_tier1, "tier1"),
        eval_one(pred_df, gold_tier12, "tier12")
      )
    }) |>
    dplyr::ungroup()
}


# ---------------------------------------------------------------------------
# Method-comparison ladder helper
# ---------------------------------------------------------------------------

#' Format the headline comparison ladder for the notebook
#'
#' Takes the long metrics tibble produced by `evaluate_clusters_grid()` and
#' returns Precision, Recall, F1, ARI, Purity cells formatted as
#' `"%.3f [lo, hi]"` for each variant under a chosen `eval_tier`, plus an
#' Over:Under ratio summarising asymmetric failure cost.
#'
#' @param metrics_long Output of `evaluate_clusters_grid()`.
#' @param eval_tier "tier1" or "tier12".
#' @param group_keys Character vector of grouping columns.
#' @return Wide tibble: group_keys..., Precision, Recall, F1, ARI, Purity,
#'   Over:Under, n clusters.
#' @export
format_method_ladder <- function(metrics_long,
                                 eval_tier = "tier1",
                                 group_keys = "variant_id") {

  fmt <- function(v, lo, hi) {
    dplyr::if_else(
      is.na(v), "—",
      sprintf("%.3f [%.3f, %.3f]", v, lo, hi)
    )
  }

  fmt_ratio <- function(over, under) {
    dplyr::case_when(
      is.na(over) | is.na(under)       ~ "—",
      under == 0L & over == 0L         ~ "0 : 0",
      under == 0L                      ~ sprintf("%d : 0", over),
      TRUE                             ~ sprintf("%.2f", over / under)
    )
  }

  metrics_long |>
    dplyr::filter(eval_tier == .env$eval_tier,
                  metric %in% c("pairwise_precision", "pairwise_recall",
                                "pairwise_f1", "ari", "purity")) |>
    dplyr::mutate(cell = fmt(value, ci_lo, ci_hi)) |>
    dplyr::select(dplyr::all_of(group_keys), metric, cell,
                  over_merge_count, under_merge_count,
                  n_predicted_clusters) |>
    tidyr::pivot_wider(names_from = metric, values_from = cell) |>
    dplyr::mutate(
      `Over:Under` = fmt_ratio(over_merge_count, under_merge_count)
    ) |>
    dplyr::rename(Precision = pairwise_precision,
                  Recall    = pairwise_recall,
                  F1        = pairwise_f1,
                  ARI       = ari,
                  Purity    = purity,
                  `n clusters` = n_predicted_clusters) |>
    dplyr::select(dplyr::all_of(group_keys),
                  Precision, Recall, F1, ARI, Purity,
                  `Over:Under`, `n clusters`)
}


# ---------------------------------------------------------------------------
# Phase B — Multilingual embedding + HDBSCAN clustering (Methods 2 + 3)
# ---------------------------------------------------------------------------

#' Embed the C0 measure-name pool with an instruction-tuned model
#'
#' Wraps call_embedding_api() on the chosen rank subset of the pool and
#' L2-normalises the returned vectors so euclidean distance ranks the same
#' as cosine similarity (lets us reuse dbscan's euclidean-default machinery).
#'
#' @param measure_pool Output of build_c0_measure_pool().
#' @param model Character: Ollama/OpenAI model id.
#' @param instruction Character: instruction string for the E5-instruct prefix.
#'   Applied to every input — the symmetric/clustering convention from the
#'   intfloat/multilingual-e5-large-instruct HF model card.
#' @param rank_filter Integer: which measure_rank to keep (default 1L).
#' @param provider,base_url,api_key Passed through to call_embedding_api().
#' @return Numeric matrix N x D with rownames = unique measure_name strings,
#'   rows L2-normalised.
#' @export
embed_c0_measure_pool <- function(measure_pool,
                                  model,
                                  instruction,
                                  rank_filter = 1L,
                                  provider = "ollama",
                                  base_url = NULL,
                                  api_key = NULL) {

  names_vec <- measure_pool |>
    dplyr::filter(measure_rank == rank_filter,
                  !is.na(measure_name), nchar(measure_name) > 0L) |>
    dplyr::pull(measure_name) |>
    unique()

  if (length(names_vec) == 0L) {
    return(matrix(numeric(0), nrow = 0L, ncol = 0L))
  }

  emb <- call_embedding_api(
    texts = names_vec,
    model = model,
    instruction = instruction,
    provider = provider,
    base_url = base_url,
    api_key = api_key
  )

  row_norms <- sqrt(rowSums(emb^2))
  row_norms[row_norms == 0] <- 1
  emb / row_norms
}


#' Embed gold-act labels in the same space as the measure pool
#'
#' Pull unique `gold_act_name` strings from the eval pool and embed them
#' with the same model + instruction used for `embed_c0_measure_pool()`,
#' so cosine similarity between a surface measure_name embedding and a
#' gold-label embedding is well-defined. L2-normalised to match the
#' measure-pool convention.
#'
#' @param eval_gold_pairs Output of build_c0_eval_gold_pairs().
#' @param model,instruction,provider,base_url,api_key Same parameters as
#'   embed_c0_measure_pool(); pass the same values to keep the embedding
#'   space consistent.
#' @return Numeric matrix N x D with rownames = unique gold_act_name
#'   strings, rows L2-normalised.
#' @export
embed_c0_gold_labels <- function(eval_gold_pairs,
                                 model,
                                 instruction,
                                 provider = "ollama",
                                 base_url = NULL,
                                 api_key = NULL) {

  labels_vec <- eval_gold_pairs |>
    dplyr::filter(!is.na(gold_act_name), nchar(gold_act_name) > 0L) |>
    dplyr::pull(gold_act_name) |>
    unique()

  if (length(labels_vec) == 0L) {
    return(matrix(numeric(0), nrow = 0L, ncol = 0L))
  }

  emb <- call_embedding_api(
    texts = labels_vec,
    model = model,
    instruction = instruction,
    provider = provider,
    base_url = base_url,
    api_key = api_key
  )

  row_norms <- sqrt(rowSums(emb^2))
  row_norms[row_norms == 0] <- 1
  emb / row_norms
}


#' HDBSCAN clustering of measure names on cosine distance
#'
#' Builds a pairwise cosine-distance matrix from L2-normalised embedding
#' rows, optionally masks pairs outside a year window to 1.0 (max distance),
#' and runs dbscan::hdbscan on the resulting `dist`. HDBSCAN noise points
#' (cluster 0) are mapped to unique negative cluster IDs so downstream
#' pairwise scoring treats them as their own singleton — the correct
#' semantics for "model declined to merge it" (under-merge, not over-merge).
#'
#' Canonical name per cluster: longest member (alphabetical tiebreak),
#' matching cluster_measure_names_corpus() convention.
#'
#' @param embeddings Matrix from embed_c0_measure_pool(); rownames =
#'   measure_name strings.
#' @param measure_pool Used to resolve per-name min year for year-blocking.
#' @param min_cluster_size Integer >= 2; passed as `minPts` to hdbscan.
#' @param year_window Integer or NULL; if integer, mask pairs with
#'   `|year_a - year_b| > year_window` to distance 1.0.
#' @return Tibble: measure_name, cluster_id, canonical_name,
#'   min_cluster_size, year_window, n_members.
#' @export
cluster_measure_names_hdbscan <- function(embeddings,
                                          measure_pool,
                                          min_cluster_size,
                                          year_window = NULL) {

  stopifnot(is.matrix(embeddings),
            is.numeric(min_cluster_size), min_cluster_size >= 2L)
  if (!is.null(year_window)) stopifnot(year_window >= 0L)

  names_vec <- rownames(embeddings)
  n <- length(names_vec)

  if (n < 2L) {
    return(tibble::tibble(
      measure_name = names_vec %||% character(0),
      cluster_id = if (n == 0L) integer(0) else 1L,
      canonical_name = names_vec %||% character(0),
      min_cluster_size = as.integer(min_cluster_size),
      year_window = year_window %||% NA_integer_,
      n_members = if (n == 0L) integer(0) else 1L
    ))
  }

  # Cosine distance on L2-normalised vectors = 1 - dot product.
  d <- 1 - tcrossprod(embeddings)
  d[d < 0] <- 0  # floating-point safety

  if (!is.null(year_window)) {
    name_year <- measure_pool |>
      dplyr::group_by(measure_name) |>
      dplyr::summarize(year_min = suppressWarnings(min(year, na.rm = TRUE)),
                       .groups = "drop") |>
      dplyr::mutate(year_min = dplyr::if_else(is.finite(year_min),
                                              as.integer(year_min),
                                              NA_integer_))
    years <- name_year$year_min[match(names_vec, name_year$measure_name)]
    year_diff <- outer(years, years, FUN = \(a, b) abs(a - b))
    year_diff[is.na(year_diff)] <- year_window + 1L
    d[year_diff > year_window] <- 1.0
  }

  hd <- dbscan::hdbscan(stats::as.dist(d),
                        minPts = as.integer(min_cluster_size))
  cl <- hd$cluster

  noise_idx <- which(cl == 0L)
  if (length(noise_idx) > 0L) {
    cl[noise_idx] <- -seq_along(noise_idx)
  }

  assignment <- tibble::tibble(measure_name = names_vec,
                               cluster_id = as.integer(cl))

  canonical <- assignment |>
    dplyr::mutate(nchar = nchar(measure_name)) |>
    dplyr::arrange(dplyr::desc(nchar), measure_name) |>
    dplyr::group_by(cluster_id) |>
    dplyr::summarize(canonical_name = dplyr::first(measure_name),
                     n_members = dplyr::n(),
                     .groups = "drop")

  assignment |>
    dplyr::left_join(canonical, by = "cluster_id") |>
    dplyr::mutate(min_cluster_size = as.integer(min_cluster_size),
                  year_window = year_window %||% NA_integer_)
}


#' Run HDBSCAN clustering across a (min_cluster_size x year_window) grid
#'
#' Returns one long tibble with the same column shape as
#' run_jw_clusters_grid() so evaluate_clusters_grid() works unchanged.
#'
#' @param embeddings Output of embed_c0_measure_pool().
#' @param measure_pool Output of build_c0_measure_pool().
#' @param min_cluster_sizes Integer vector of HDBSCAN minPts values to sweep.
#' @param year_windows List of values for year_window; use NULL for unblocked.
#' @return Tibble with columns: variant_id (chr), min_cluster_size,
#'   year_window, measure_name, cluster_id, canonical_name, n_members.
#' @export
run_hdbscan_clusters_grid <- function(embeddings,
                                      measure_pool,
                                      min_cluster_sizes = c(2L, 3L, 5L),
                                      year_windows = list(NULL, 2L)) {

  grid <- tidyr::expand_grid(
    min_cluster_size = as.integer(min_cluster_sizes),
    year_window_idx  = seq_along(year_windows)
  )

  purrr::pmap_dfr(grid, function(min_cluster_size, year_window_idx) {
    yw <- year_windows[[year_window_idx]]
    cl <- cluster_measure_names_hdbscan(
      embeddings,
      measure_pool,
      min_cluster_size = min_cluster_size,
      year_window = yw
    )
    cl |>
      dplyr::mutate(
        variant_id = sprintf("hdb_m%d_%s",
                             min_cluster_size,
                             if (is.null(yw)) "unblocked"
                             else sprintf("yw%d", yw))
      )
  })
}


#' UMAP-reduce L2-normalised embeddings for downstream clustering
#'
#' Thin wrapper around `uwot::umap()` that fixes `metric = "cosine"` (the
#' input embeddings are L2-normalised, matching the F16/FP32 probes) and
#' restores rownames on the reduced matrix so downstream code can index by
#' `measure_name`. Sets the RNG seed before each call so that under a fixed
#' seed the reduction is deterministic across a grid sweep.
#'
#' @param embeddings Matrix from `embed_c0_measure_pool()`; rownames =
#'   measure_name strings; rows L2-normalised.
#' @param n_neighbors,n_components,min_dist UMAP hyperparameters; see
#'   `uwot::umap()`. The C0 sweep grid is built in `c0_umap_grid`.
#' @param seed Integer; passed to `set.seed()` immediately before the
#'   `uwot::umap()` call. Single source of stochasticity for Methods 2 + 3
#'   with UMAP — same seed across the grid means each UMAP cell is
#'   reproducible in isolation.
#' @return Numeric matrix N x n_components with rownames preserved from
#'   `embeddings`.
#' @export
umap_reduce_embeddings <- function(embeddings,
                                   n_neighbors,
                                   n_components,
                                   min_dist,
                                   seed) {

  stopifnot(is.matrix(embeddings),
            is.numeric(n_neighbors), n_neighbors >= 2L,
            is.numeric(n_components), n_components >= 1L,
            is.numeric(min_dist), min_dist >= 0,
            is.numeric(seed))

  set.seed(as.integer(seed))
  reduced <- uwot::umap(
    embeddings,
    n_neighbors  = as.integer(n_neighbors),
    n_components = as.integer(n_components),
    min_dist     = min_dist,
    metric       = "cosine",
    verbose      = FALSE
  )
  rownames(reduced) <- rownames(embeddings)
  reduced
}


#' HDBSCAN clustering on a UMAP-reduced embedding matrix
#'
#' Mirrors `cluster_measure_names_hdbscan()` but operates on the
#' UMAP-reduced space using Euclidean distance (the BERTopic-standard
#' choice — UMAP output is not L2-normalised so cosine on it is not
#' meaningful). The year-window mask uses a sentinel of
#' `max(d) + 1` because Euclidean distances on UMAP output are unbounded,
#' unlike cosine where the natural sentinel is 1.0.
#'
#' Noise handling, canonical-name selection, and output columns are
#' identical to `cluster_measure_names_hdbscan()`.
#'
#' @param reduced Matrix from `umap_reduce_embeddings()`; rownames =
#'   measure_name strings.
#' @param measure_pool Used to resolve per-name min year for year-blocking.
#' @param min_cluster_size Integer >= 2; passed as `minPts` to hdbscan.
#' @param year_window Integer or NULL; if integer, mask pairs with
#'   `|year_a - year_b| > year_window` to `max(d) + 1`.
#' @return Tibble: measure_name, cluster_id, canonical_name,
#'   min_cluster_size, year_window, n_members.
#' @export
cluster_reduced_embeddings_hdbscan <- function(reduced,
                                               measure_pool,
                                               min_cluster_size,
                                               year_window = NULL) {

  stopifnot(is.matrix(reduced),
            is.numeric(min_cluster_size), min_cluster_size >= 2L)
  if (!is.null(year_window)) stopifnot(year_window >= 0L)

  names_vec <- rownames(reduced)
  n <- length(names_vec)

  if (n < 2L) {
    return(tibble::tibble(
      measure_name = names_vec %||% character(0),
      cluster_id = if (n == 0L) integer(0) else 1L,
      canonical_name = names_vec %||% character(0),
      min_cluster_size = as.integer(min_cluster_size),
      year_window = year_window %||% NA_integer_,
      n_members = if (n == 0L) integer(0) else 1L
    ))
  }

  d <- as.matrix(stats::dist(reduced, method = "euclidean"))

  if (!is.null(year_window)) {
    name_year <- measure_pool |>
      dplyr::group_by(measure_name) |>
      dplyr::summarize(year_min = suppressWarnings(min(year, na.rm = TRUE)),
                       .groups = "drop") |>
      dplyr::mutate(year_min = dplyr::if_else(is.finite(year_min),
                                              as.integer(year_min),
                                              NA_integer_))
    years <- name_year$year_min[match(names_vec, name_year$measure_name)]
    year_diff <- outer(years, years, FUN = \(a, b) abs(a - b))
    year_diff[is.na(year_diff)] <- year_window + 1L
    sentinel <- max(d, na.rm = TRUE) + 1
    d[year_diff > year_window] <- sentinel
  }

  hd <- dbscan::hdbscan(stats::as.dist(d),
                        minPts = as.integer(min_cluster_size))
  cl <- hd$cluster

  noise_idx <- which(cl == 0L)
  if (length(noise_idx) > 0L) {
    cl[noise_idx] <- -seq_along(noise_idx)
  }

  assignment <- tibble::tibble(measure_name = names_vec,
                               cluster_id = as.integer(cl))

  canonical <- assignment |>
    dplyr::mutate(nchar = nchar(measure_name)) |>
    dplyr::arrange(dplyr::desc(nchar), measure_name) |>
    dplyr::group_by(cluster_id) |>
    dplyr::summarize(canonical_name = dplyr::first(measure_name),
                     n_members = dplyr::n(),
                     .groups = "drop")

  assignment |>
    dplyr::left_join(canonical, by = "cluster_id") |>
    dplyr::mutate(min_cluster_size = as.integer(min_cluster_size),
                  year_window = year_window %||% NA_integer_)
}


#' Run UMAP + HDBSCAN clustering for one UMAP cell
#'
#' UMAP-reduces the embeddings once with the supplied hyperparameters and
#' sweeps `(min_cluster_size, year_window)` on the reduced space. Returns a
#' long-form tibble with one row per (measure_name x HDBSCAN sub-cell) and
#' a `variant_id` encoding the full four-dimensional sweep cell:
#' `hdb_umap_nn{n_neighbors}_nc{n_components}_md{min_dist}_m{min_cluster_size}_{block}`.
#'
#' This is the per-branch unit of the dynamic-branched `c0_hdbscan_umap_*`
#' targets in `_targets.R`. `run_hdbscan_umap_clusters_grid()` is a thin
#' loop wrapper around this for the non-branched / interactive call path.
#'
#' @param embeddings Output of `embed_c0_measure_pool()` (L2-normalised).
#' @param measure_pool Output of `build_c0_measure_pool()`.
#' @param n_neighbors,n_components,min_dist Scalar UMAP hyperparameters.
#' @param min_cluster_sizes Integer vector of HDBSCAN minPts values to sweep.
#' @param year_windows List of values for year_window; use NULL for unblocked.
#' @param seed Integer; passed through to `umap_reduce_embeddings()`.
#' @return Tibble with columns: measure_name, cluster_id, canonical_name,
#'   min_cluster_size, year_window, n_members, variant_id.
#' @export
run_hdbscan_umap_clusters_one_cell <- function(embeddings,
                                               measure_pool,
                                               n_neighbors,
                                               n_components,
                                               min_dist,
                                               min_cluster_sizes = c(2L, 3L, 5L),
                                               year_windows = list(NULL, 2L),
                                               seed) {

  stopifnot(is.matrix(embeddings),
            length(n_neighbors) == 1L,
            length(n_components) == 1L,
            length(min_dist) == 1L,
            is.numeric(seed))

  reduced <- umap_reduce_embeddings(
    embeddings,
    n_neighbors  = n_neighbors,
    n_components = n_components,
    min_dist     = min_dist,
    seed         = seed
  )

  hdb_grid <- tidyr::expand_grid(
    min_cluster_size = as.integer(min_cluster_sizes),
    year_window_idx  = seq_along(year_windows)
  )

  purrr::pmap_dfr(hdb_grid,
    function(min_cluster_size, year_window_idx) {
      yw <- year_windows[[year_window_idx]]
      cl <- cluster_reduced_embeddings_hdbscan(
        reduced,
        measure_pool,
        min_cluster_size = min_cluster_size,
        year_window = yw
      )
      cl |>
        dplyr::mutate(
          variant_id = sprintf(
            "hdb_umap_nn%d_nc%d_md%.3f_m%d_%s",
            as.integer(n_neighbors),
            as.integer(n_components),
            min_dist,
            as.integer(min_cluster_size),
            if (is.null(yw)) "unblocked" else sprintf("yw%d", yw)
          )
        )
    })
}


#' Run UMAP + HDBSCAN clustering across a (UMAP x HDBSCAN) grid
#'
#' Thin loop calling `run_hdbscan_umap_clusters_one_cell()` once per row of
#' `umap_grid` and `bind_rows`'ing the results. Provided for interactive /
#' non-targets use; the production pipeline branches dynamically over
#' `c0_umap_grid` rows and calls the one-cell helper directly.
#'
#' @param embeddings Output of `embed_c0_measure_pool()` (L2-normalised).
#' @param measure_pool Output of `build_c0_measure_pool()`.
#' @param umap_grid Tibble with columns `n_neighbors`, `n_components`,
#'   `min_dist`; one row per UMAP cell.
#' @param min_cluster_sizes Integer vector of HDBSCAN minPts values to sweep.
#' @param year_windows List of values for year_window; use NULL for unblocked.
#' @param seed Integer; single seed applied per UMAP cell.
#' @return Tibble with columns: variant_id (chr), min_cluster_size,
#'   year_window, measure_name, cluster_id, canonical_name, n_members.
#' @export
run_hdbscan_umap_clusters_grid <- function(embeddings,
                                           measure_pool,
                                           umap_grid,
                                           min_cluster_sizes = c(2L, 3L, 5L),
                                           year_windows = list(NULL, 2L),
                                           seed) {

  stopifnot(is.matrix(embeddings),
            tibble::is_tibble(umap_grid) || is.data.frame(umap_grid),
            all(c("n_neighbors", "n_components", "min_dist") %in%
                  names(umap_grid)),
            nrow(umap_grid) >= 1L,
            is.numeric(seed))

  purrr::pmap_dfr(umap_grid,
    function(n_neighbors, n_components, min_dist) {
      run_hdbscan_umap_clusters_one_cell(
        embeddings, measure_pool,
        n_neighbors  = n_neighbors,
        n_components = n_components,
        min_dist     = min_dist,
        min_cluster_sizes = min_cluster_sizes,
        year_windows = year_windows,
        seed = seed
      )
    })
}


#' Sanity-probe the F16 embedding port against the eval gold pool
#'
#' Two diagnostic checks that don't require a reference FP32 host:
#'   - top1_nn_same_act_rate: for each eval name in an act with >= 2
#'     members, is its top-1 nearest neighbour (by cosine, excluding
#'     itself) tagged with the same gold act?
#'   - separation: median within-act pairwise cosine MINUS median
#'     between-act pairwise cosine. Positive = semantic structure
#'     preserved by the F16 port.
#'
#' Headline floors used by the notebook: separation >= 0.05 and
#' top1 >= 0.40 mean the F16 port isn't corrupting the model; below
#' either threshold, escalate to an FP32 cross-check.
#'
#' @param embeddings Output of embed_c0_measure_pool() (L2-normalised).
#' @param eval_gold_pairs Output of build_c0_eval_gold_pairs().
#' @return One-row tibble: top1_nn_same_act_rate,
#'   median_within_act_cosine, median_between_act_cosine, separation,
#'   n_eval_names, n_eval_acts.
#' @export
probe_f16_quantization <- function(embeddings, eval_gold_pairs) {

  unamb <- eval_gold_pairs |>
    dplyr::filter(!ambiguous) |>
    dplyr::distinct(measure_name, gold_act_name)

  shared <- intersect(rownames(embeddings), unamb$measure_name)
  if (length(shared) < 2L) {
    return(tibble::tibble(
      top1_nn_same_act_rate     = NA_real_,
      median_within_act_cosine  = NA_real_,
      median_between_act_cosine = NA_real_,
      separation                = NA_real_,
      n_eval_names              = length(shared),
      n_eval_acts               = 0L
    ))
  }

  E <- embeddings[shared, , drop = FALSE]
  cos <- tcrossprod(E)  # L2-normalised => dot product == cosine

  label_lookup <- stats::setNames(unamb$gold_act_name, unamb$measure_name)
  labels <- label_lookup[shared]

  # Top-1 NN restricted to names in acts with >= 2 members so the metric is
  # well-defined (a singleton act can never produce a same-act NN).
  act_sizes <- table(labels)
  evaluable <- labels %in% names(act_sizes)[act_sizes >= 2L]

  diag(cos) <- -Inf
  nn_idx <- apply(cos, 1L, which.max)
  nn_labels <- labels[nn_idx]
  top1_rate <- if (any(evaluable)) {
    mean(nn_labels[evaluable] == labels[evaluable])
  } else NA_real_

  # Restore diagonal for within/between accounting.
  diag(cos) <- 1
  upper <- upper.tri(cos)
  pair_cos <- cos[upper]
  pair_same_act <- outer(labels, labels, FUN = "==")[upper]

  within  <- pair_cos[pair_same_act]
  between <- pair_cos[!pair_same_act]

  median_within  <- if (length(within)  > 0L) stats::median(within)  else NA_real_
  median_between <- if (length(between) > 0L) stats::median(between) else NA_real_
  separation     <- median_within - median_between

  tibble::tibble(
    top1_nn_same_act_rate     = top1_rate,
    median_within_act_cosine  = median_within,
    median_between_act_cosine = median_between,
    separation                = separation,
    n_eval_names              = length(shared),
    n_eval_acts               = dplyr::n_distinct(labels)
  )
}


#' Probe UMAP-reduced embedding geometry on the gold eval pool
#'
#' Euclidean analog of `probe_f16_quantization()`. UMAP output is not
#' L2-normalised so cosine on it is not meaningful; Euclidean matches both
#' the inline notebook helper this replaces and how HDBSCAN consumes the
#' reduced space downstream via `cluster_reduced_embeddings_hdbscan()`.
#' Sign convention is flipped relative to the cosine probe so
#' "separation > 0" still means "act-level structure preserved".
#'
#' Metrics:
#'   - top1_nn_same_act_rate: for each eval name in an act with >= 2
#'     members, is its top-1 nearest neighbour (by Euclidean distance,
#'     excluding itself) tagged with the same gold act?
#'   - separation: median between-act pairwise distance MINUS median
#'     within-act pairwise distance. Positive = acts more compact within
#'     than between, i.e. structure preserved.
#'
#' Caller controls tier filtering (matching the existing
#' `c0_f16_quantization_probe_tier1` pattern in `_targets.R`); this
#' function filters `!ambiguous` internally to match
#' `probe_f16_quantization()`.
#'
#' @param reduced Numeric matrix from `umap_reduce_embeddings()`. Rownames
#'   must be measure_name strings.
#' @param eval_gold_pairs Output of `build_c0_eval_gold_pairs()`,
#'   optionally pre-filtered by tier.
#' @return One-row tibble: top1_nn_same_act_rate,
#'   median_within_act_distance, median_between_act_distance, separation,
#'   n_eval_names, n_eval_acts.
#' @export
probe_umap_geometry <- function(reduced, eval_gold_pairs) {

  unamb <- eval_gold_pairs |>
    dplyr::filter(!ambiguous) |>
    dplyr::distinct(measure_name, gold_act_name)

  shared <- intersect(rownames(reduced), unamb$measure_name)
  if (length(shared) < 2L) {
    return(tibble::tibble(
      top1_nn_same_act_rate       = NA_real_,
      median_within_act_distance  = NA_real_,
      median_between_act_distance = NA_real_,
      separation                  = NA_real_,
      n_eval_names                = length(shared),
      n_eval_acts                 = 0L
    ))
  }

  d <- as.matrix(stats::dist(reduced[shared, , drop = FALSE],
                             method = "euclidean"))

  label_lookup <- stats::setNames(unamb$gold_act_name, unamb$measure_name)
  labels <- label_lookup[shared]

  # Top-1 NN restricted to names in acts with >= 2 members so the metric is
  # well-defined (a singleton act can never produce a same-act NN).
  act_sizes <- table(labels)
  evaluable <- labels %in% names(act_sizes)[act_sizes >= 2L]

  diag(d) <- Inf
  nn_idx <- apply(d, 1L, which.min)
  nn_labels <- labels[nn_idx]
  top1_rate <- if (any(evaluable)) {
    mean(nn_labels[evaluable] == labels[evaluable])
  } else NA_real_

  # Restore diagonal for within/between accounting.
  diag(d) <- 0
  upper <- upper.tri(d)
  pair_d <- d[upper]
  pair_same_act <- outer(labels, labels, FUN = "==")[upper]

  within  <- pair_d[pair_same_act]
  between <- pair_d[!pair_same_act]

  median_within  <- if (length(within)  > 0L) stats::median(within)  else NA_real_
  median_between <- if (length(between) > 0L) stats::median(between) else NA_real_
  separation     <- median_between - median_within

  tibble::tibble(
    top1_nn_same_act_rate       = top1_rate,
    median_within_act_distance  = median_within,
    median_between_act_distance = median_between,
    separation                  = separation,
    n_eval_names                = length(shared),
    n_eval_acts                 = dplyr::n_distinct(labels)
  )
}


# =============================================================================
# Phase A — Evaluation against R&R's act list (us_shocks)
# =============================================================================
# Sibling of evaluate_clusters_grid() that scores predicted clusters against
# the 49-act canonical list in data/raw/us_shocks.csv instead of the noisy
# c0_eval_gold_pairs pool. Match gate = (name distance below threshold) AND
# (|cluster_year - act year_signed| ≤ year_window). Name distance reported
# under two complementary metrics:
#
#   - keyword: any cluster member contains any subcomponent term of the RR
#     act name (after `squish_for_matching()`), via `generate_subcomponents()`
#     reused from R/identify_chunk_tiers.R. Immune to name rewriting.
#   - jw:      `min over cluster members of stringdist(member, rr_act_name,
#     method = "jw") ≤ jw_threshold`. Sensitive to abbreviation.
#
# Headline metrics under the joint name + year gate:
#   - coverage           = |{rr_act with ≥1 matching cluster}| / 49
#   - spurious_rate      = |{cluster with no rr_act match}|    / n_clusters
#   - fragmentation_index= mean over matched acts of (# clusters claiming act)
#   - year_alignment     = of name-matched pairs, share with year_match too
#
# Bootstrap CI: resample the 49 acts with replacement (act-level perturbation).
# =============================================================================


#' Extract the first 4-digit year (19XX or 20XX) from a string
#'
#' Vectorised wrapper around the year regex used across the codebase.
#' Returns `NA_integer_` when no year is present.
#'
#' @param text Character vector.
#' @return Integer vector of the same length.
#' @export
extract_year_from_string <- function(text) {
  as.integer(stringr::str_extract(text, "\\b(19|20)\\d{2}\\b"))
}


#' Build the canonical R&R act list from `us_shocks.csv`
#'
#' Collapses `us_shocks` (one row per act × quarter × measure_type) to one row
#' per distinct act. Representative year is taken from `date_signed`, which is
#' constant within an act in us_shocks. Consumes the `us_shocks` pipeline
#' target (post-`clean_us_shocks()`, so columns are snake_cased).
#'
#' @param us_shocks Tibble from the `us_shocks` target with columns `act_name`
#'   and `date_signed`. (If you read the raw CSV directly, apply
#'   `clean_us_shocks()` first.)
#' @return Tibble `(act_id, act_name, year_signed)`, sorted by year_signed
#'   then act_name. Expected `nrow == 49`.
#' @export
build_us_rr_acts <- function(us_shocks) {
  us_shocks |>
    dplyr::group_by(act_name) |>
    dplyr::summarize(date_signed = dplyr::first(date_signed),
                     .groups = "drop") |>
    dplyr::mutate(
      year_signed = lubridate::year(lubridate::ymd(date_signed))
    ) |>
    dplyr::arrange(year_signed, act_name) |>
    dplyr::mutate(act_id = dplyr::row_number()) |>
    dplyr::select(act_id, act_name, year_signed)
}


#' Match predicted clusters against R&R's canonical act list
#'
#' For each (variant × cluster × rr_act) triple, computes name distance and
#' year distance and the gate booleans. Returns only triples where the keyword
#' OR JW name gate passes — clusters absent from the output are spurious under
#' both gates.
#'
#' Cluster representative year is the median of years extracted from cluster
#' members' surface forms via `extract_year_from_string()`. If no member has
#' an extractable year, falls back to the mode of `doc_year` from
#' `measure_pool`.
#'
#' @param clusters Long tibble from `run_*_clusters_grid()` containing
#'   `group_keys`, `cluster_id`, `measure_name`.
#' @param measure_pool Tibble from `build_c0_measure_pool()` carrying `year`
#'   (doc year) per measure_name × chunk row.
#' @param rr_acts Output of `build_us_rr_acts()`.
#' @param group_keys Character vector of variant-identifier columns (default
#'   "variant_id").
#' @param jw_threshold Numeric, JW-min ≤ this counts as a name match (default
#'   0.30).
#' @param year_window Integer, |cluster_year - year_signed| ≤ this counts as
#'   a year match (default 2L).
#' @return Long tibble: `group_keys..., cluster_id, act_id, act_name,
#'   year_signed, cluster_year, year_diff, jw_min_distance,
#'   name_match_keyword, name_match_jw, year_match, match_keyword, match_jw`.
#' @export
match_clusters_to_rr_acts <- function(clusters, measure_pool, rr_acts,
                                       group_keys = "variant_id",
                                       jw_threshold = 0.30,
                                       year_window = 2L) {

  stopifnot(all(group_keys %in% names(clusters)))
  stopifnot(all(c("cluster_id", "measure_name") %in% names(clusters)))
  stopifnot(all(c("act_id", "act_name", "year_signed") %in% names(rr_acts)))

  rr_terms <- purrr::map(rr_acts$act_name, function(n) {
    unique(tolower(generate_subcomponents(n)$term))
  })
  names(rr_terms) <- as.character(rr_acts$act_id)

  all_members <- unique(clusters$measure_name)
  all_members <- all_members[!is.na(all_members)]
  members_sq <- squish_for_matching(all_members)
  members_lc <- tolower(all_members)

  member_lookup <- tibble::tibble(
    measure_name = all_members,
    member_sq    = members_sq,
    member_lc    = members_lc
  )

  act_lookup <- rr_acts |>
    dplyr::transmute(act_id, act_name_lc = tolower(act_name))

  member_grid <- tidyr::expand_grid(
    measure_name = all_members,
    act_id = rr_acts$act_id
  ) |>
    dplyr::left_join(member_lookup, by = "measure_name") |>
    dplyr::left_join(act_lookup, by = "act_id") |>
    dplyr::mutate(
      jw = stringdist::stringdist(member_lc, act_name_lc, method = "jw"),
      any_term_match = purrr::map2_lgl(
        member_sq, as.character(act_id),
        function(ms, aid) {
          terms <- rr_terms[[aid]]
          if (length(terms) == 0L) return(FALSE)
          any(vapply(terms, function(t) {
            stringr::str_detect(ms, stringr::fixed(t))
          }, logical(1L)))
        }
      )
    ) |>
    dplyr::select(measure_name, act_id, jw, any_term_match)

  pool_year <- measure_pool |>
    dplyr::filter(!is.na(year)) |>
    dplyr::group_by(measure_name) |>
    dplyr::summarize(doc_year_mode = .mode_int(year), .groups = "drop")

  cluster_member_rows <- clusters |>
    dplyr::distinct(dplyr::across(dplyr::all_of(c(group_keys, "cluster_id",
                                                  "measure_name")))) |>
    dplyr::left_join(pool_year, by = "measure_name")

  cluster_year_tbl <- cluster_member_rows |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(group_keys, "cluster_id")))) |>
    dplyr::summarize(
      cluster_year = .derive_cluster_year(measure_name, doc_year_mode),
      .groups = "drop"
    )

  cluster_member_rows |>
    dplyr::select(dplyr::all_of(c(group_keys, "cluster_id", "measure_name"))) |>
    dplyr::inner_join(member_grid, by = "measure_name",
                       relationship = "many-to-many") |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(group_keys, "cluster_id",
                                                   "act_id")))) |>
    dplyr::summarize(
      jw_min_distance = suppressWarnings(min(jw, na.rm = TRUE)),
      keyword_hit     = any(any_term_match, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      jw_min_distance = dplyr::if_else(is.finite(jw_min_distance),
                                         jw_min_distance, NA_real_)
    ) |>
    dplyr::left_join(cluster_year_tbl,
                      by = c(group_keys, "cluster_id")) |>
    dplyr::left_join(
      rr_acts |> dplyr::select(act_id, act_name, year_signed),
      by = "act_id"
    ) |>
    dplyr::mutate(
      year_diff          = as.integer(abs(cluster_year - year_signed)),
      name_match_keyword = keyword_hit,
      name_match_jw      = !is.na(jw_min_distance) &
                            jw_min_distance <= jw_threshold,
      year_match         = !is.na(year_diff) & year_diff <= year_window,
      match_keyword      = name_match_keyword & year_match,
      match_jw           = name_match_jw      & year_match
    ) |>
    dplyr::filter(name_match_keyword | name_match_jw) |>
    dplyr::select(dplyr::all_of(group_keys), cluster_id, act_id, act_name,
                  year_signed, cluster_year, year_diff, jw_min_distance,
                  name_match_keyword, name_match_jw, year_match,
                  match_keyword, match_jw)
}


#' Aggregate precomputed RR matches into per-variant headline metrics
#'
#' Pure-aggregate sibling of `evaluate_clusters_vs_rr_grid()`. Takes a
#' precomputed matches tibble from `match_clusters_to_rr_acts()` plus the
#' originating clusters tibble (used only to count total clusters per
#' variant, denominator for spurious rate). Use this entry point when the
#' `c0_*_rr_matches` target is already built so the matching work is not
#' redone.
#'
#' @param matches Tibble from `match_clusters_to_rr_acts()`.
#' @param clusters Same `clusters` tibble passed to `match_clusters_to_rr_acts()`.
#' @param rr_acts Output of `build_us_rr_acts()`.
#' @param group_keys,n_boot,seed See `evaluate_clusters_vs_rr_grid()`.
#' @return Same long tibble shape as `evaluate_clusters_vs_rr_grid()`.
#' @export
evaluate_rr_matches_grid <- function(matches, clusters, rr_acts,
                                       group_keys = "variant_id",
                                       n_boot = 1000L,
                                       seed = 20260529L) {

  all_clusters <- clusters |>
    dplyr::distinct(dplyr::across(dplyr::all_of(c(group_keys, "cluster_id"))))

  cluster_counts <- all_clusters |>
    dplyr::count(dplyr::across(dplyr::all_of(group_keys)),
                  name = "n_clusters")

  n_rr <- nrow(rr_acts)
  rr_act_ids <- rr_acts$act_id

  metrics_for_subset <- function(matches_v, n_clusters_v,
                                   pass_col, name_col, act_subset_ids) {
    sub <- matches_v[matches_v$act_id %in% act_subset_ids, , drop = FALSE]
    pass_sub <- sub[sub[[pass_col]], , drop = FALSE]
    name_sub <- sub[sub[[name_col]], , drop = FALSE]

    acts_matched <- dplyr::n_distinct(pass_sub$act_id)
    clusters_matched <- dplyr::n_distinct(pass_sub$cluster_id)

    coverage_v <- if (length(act_subset_ids) == 0L) NA_real_
                  else sum(act_subset_ids %in% pass_sub$act_id) /
                        length(act_subset_ids)

    spurious_v <- if (n_clusters_v > 0L)
      (n_clusters_v - clusters_matched) / n_clusters_v else NA_real_

    frag_v <- if (acts_matched > 0L) {
      cl_per_act <- pass_sub |>
        dplyr::distinct(act_id, cluster_id) |>
        dplyr::count(act_id) |>
        dplyr::pull(n)
      mean(cl_per_act)
    } else NA_real_

    year_align_v <- if (nrow(name_sub) > 0L)
      mean(name_sub$year_match, na.rm = TRUE) else NA_real_

    c(coverage = coverage_v, spurious_rate = spurious_v,
      fragmentation_index = frag_v, year_alignment = year_align_v)
  }

  one_variant_one_gate <- function(matches_v, n_clusters_v, clusters_v, gate) {
    pass_col <- if (gate == "keyword") "match_keyword" else "match_jw"
    name_col <- if (gate == "keyword") "name_match_keyword" else "name_match_jw"

    point <- metrics_for_subset(matches_v, n_clusters_v,
                                  pass_col, name_col, rr_act_ids)

    # Dual sampling unit. Coverage / fragmentation / year_alignment are
    # act-indexed, so their CIs come from resampling the 49 RR acts. Spurious
    # rate is a proportion over the emitted *clusters* (denominator n_clusters
    # is independent of the act set), so resampling acts biases it strictly
    # upward and the CI fails to envelop the point. Its CI therefore comes from
    # a separate cluster-level bootstrap below (seed + 1L for a distinct stream).
    boot <- withr::with_seed(seed, {
      replicate(n_boot, {
        idx <- sample.int(n_rr, n_rr, replace = TRUE)
        metrics_for_subset(matches_v, n_clusters_v,
                             pass_col, name_col, rr_act_ids[idx])
      })
    })

    ci <- apply(boot, 1L, function(v) {
      v <- v[is.finite(v)]
      if (length(v) == 0L) return(c(NA_real_, NA_real_))
      stats::quantile(v, probs = c(0.025, 0.975), names = FALSE)
    })

    # Cluster bootstrap for spurious rate: flag each cluster matched/unmatched
    # against the full 49-act reference, then resample clusters with replacement.
    matched_ids  <- unique(matches_v$cluster_id[matches_v[[pass_col]]])
    matched_flag <- clusters_v %in% matched_ids
    sp_ci <- if (length(clusters_v) == 0L) c(NA_real_, NA_real_) else {
      sp_boot <- withr::with_seed(seed + 1L, {
        replicate(n_boot, {
          idxc <- sample.int(length(clusters_v), length(clusters_v),
                             replace = TRUE)
          mean(!matched_flag[idxc])
        })
      })
      stats::quantile(sp_boot, probs = c(0.025, 0.975), names = FALSE)
    }
    spur_col <- which(names(point) == "spurious_rate")
    ci[1L, spur_col] <- sp_ci[1L]
    ci[2L, spur_col] <- sp_ci[2L]

    pass_global <- matches_v[matches_v[[pass_col]], , drop = FALSE]

    tibble::tibble(
      gate               = gate,
      metric             = names(point),
      value              = unname(point),
      ci_lo              = ci[1L, ],
      ci_hi              = ci[2L, ],
      n_clusters         = n_clusters_v,
      n_clusters_matched = dplyr::n_distinct(pass_global$cluster_id),
      n_rr_acts_matched  = dplyr::n_distinct(pass_global$act_id),
      n_rr_acts          = n_rr
    )
  }

  variant_keys <- cluster_counts |>
    dplyr::select(dplyr::all_of(group_keys))

  out_list <- purrr::map(seq_len(nrow(variant_keys)), function(i) {
    key_row <- variant_keys[i, , drop = FALSE]
    n_v <- cluster_counts |>
      dplyr::semi_join(key_row, by = group_keys) |>
      dplyr::pull(n_clusters)
    m_v <- matches |>
      dplyr::semi_join(key_row, by = group_keys)
    clusters_v <- all_clusters |>
      dplyr::semi_join(key_row, by = group_keys) |>
      dplyr::pull(cluster_id)
    rows <- dplyr::bind_rows(
      one_variant_one_gate(m_v, n_v, clusters_v, "keyword"),
      one_variant_one_gate(m_v, n_v, clusters_v, "jw")
    )
    key_repeated <- key_row[rep(1L, nrow(rows)), , drop = FALSE]
    rownames(key_repeated) <- NULL
    dplyr::bind_cols(key_repeated, rows)
  })

  dplyr::bind_rows(out_list) |>
    dplyr::relocate(dplyr::all_of(group_keys))
}


#' Match clusters to R&R acts and evaluate, one-shot
#'
#' Convenience wrapper that chains `match_clusters_to_rr_acts()` and
#' `evaluate_rr_matches_grid()`. Useful for ad-hoc calls; the pipeline
#' prefers the split form (separate `c0_*_rr_matches` and `c0_*_rr_metrics`
#' targets) so the bootstrap CI doesn't re-run the matching.
#'
#' @param clusters Long tibble from `run_*_clusters_grid()`.
#' @param measure_pool Tibble from `build_c0_measure_pool()`.
#' @param rr_acts Output of `build_us_rr_acts()`.
#' @param group_keys,jw_threshold,year_window,n_boot,seed See the underlying
#'   functions.
#' @return Same long tibble shape as `evaluate_rr_matches_grid()`.
#' @export
evaluate_clusters_vs_rr_grid <- function(clusters, measure_pool, rr_acts,
                                           group_keys = "variant_id",
                                           jw_threshold = 0.30,
                                           year_window = 2L,
                                           n_boot = 1000L,
                                           seed = 20260529L) {
  matches <- match_clusters_to_rr_acts(
    clusters, measure_pool, rr_acts,
    group_keys = group_keys,
    jw_threshold = jw_threshold,
    year_window = year_window
  )
  evaluate_rr_matches_grid(matches, clusters, rr_acts,
                             group_keys = group_keys,
                             n_boot = n_boot, seed = seed)
}


#' Format the headline RR comparison ladder for the notebook
#'
#' Wide ladder analog of `format_method_ladder()`. Picks one name gate per
#' call so the notebook can render keyword and JW side-by-side.
#'
#' @param metrics_long Output of `evaluate_clusters_vs_rr_grid()`.
#' @param gate Either "keyword" or "jw".
#' @param group_keys Character vector (default "variant_id").
#' @return Wide tibble with cells formatted `"%.3f [lo, hi]"`.
#' @export
format_rr_method_ladder <- function(metrics_long,
                                      gate = c("keyword", "jw"),
                                      group_keys = "variant_id") {

  gate <- match.arg(gate)

  fmt <- function(v, lo, hi) {
    dplyr::if_else(
      is.na(v), "—",
      sprintf("%.3f [%.3f, %.3f]", v, lo, hi)
    )
  }

  metrics_long |>
    dplyr::filter(.data$gate == .env$gate,
                  metric %in% c("coverage", "spurious_rate",
                                "fragmentation_index", "year_alignment")) |>
    dplyr::mutate(cell = fmt(value, ci_lo, ci_hi)) |>
    dplyr::select(dplyr::all_of(group_keys), metric, cell,
                  n_clusters, n_clusters_matched, n_rr_acts_matched) |>
    tidyr::pivot_wider(names_from = metric, values_from = cell) |>
    dplyr::rename(
      Coverage           = coverage,
      Spurious           = spurious_rate,
      Fragmentation      = fragmentation_index,
      `Year alignment`   = year_alignment,
      `n clusters`       = n_clusters,
      `Clusters matched` = n_clusters_matched,
      `RR acts matched`  = n_rr_acts_matched
    ) |>
    dplyr::select(dplyr::all_of(group_keys),
                  Coverage, Spurious, Fragmentation, `Year alignment`,
                  `n clusters`, `Clusters matched`, `RR acts matched`)
}


# ---------------------------------------------------------------------------
# Private helpers for RR-aligned evaluation
# ---------------------------------------------------------------------------

.mode_int <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(NA_integer_)
  tab <- table(x)
  as.integer(names(tab)[which.max(tab)])
}

.derive_cluster_year <- function(members, doc_year_mode) {
  name_years <- extract_year_from_string(members)
  if (any(!is.na(name_years))) {
    return(as.integer(round(stats::median(name_years, na.rm = TRUE))))
  }
  .mode_int(doc_year_mode)
}


# %||% is from rlang via tidyverse but we may not have it loaded directly.
`%||%` <- function(a, b) if (is.null(a)) b else a
