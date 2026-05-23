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


# %||% is from rlang via tidyverse but we may not have it loaded directly.
`%||%` <- function(a, b) if (is.null(a)) b else a
