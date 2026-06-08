# Cross-country deployment report helpers.
#
# Report-side reshape + plotting for notebooks/deployment.qmd. The deployment
# analog of R/malay_consistency.R: it presents the SAME figures and tables as
# the EN/BM consistency report, but with the comparison axis swapped from
# language (the `side` column) to COUNTRY (`country` / `country_iso`).
#
# It reads the EXISTING per-country deployment targets (country_chunks,
# country_c1_predictions, country_c1_measures, country_c0_clusters,
# country_c0_acts, country_c2b, country_measure_pool) -- no new sub-pipeline.
# The deployment chain pools each country jointly (no language axis), so the
# joint cross-language merge-rate probe has no analog here; its slot is replaced
# by a per-country C0 cluster summary.
#
# Reuses pretty_motivation(), .malay_motivation_labels, and
# .malay_motivation_palette from R/malay_consistency.R (sourced alongside this
# file in the notebook). R/malay_consistency.R itself is NOT modified.

if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b


# ---------------------------------------------------------------------------
# Country binder: attach country identity to the country-less list targets
# ---------------------------------------------------------------------------

#' Attach country + country_iso to a deployment list target by positional zip
#'
#' The country-less deployment targets (country_measure_pool, country_c0_clusters,
#' country_c0_acts, country_c2b) carry no country column -- their country identity
#' is only the branch position. Every `country_*` list target descends from
#' `country_chunks` via single-input `map(..., iteration = "list")`, so branch
#' order is identical across the chain (the documented positional-zip invariant,
#' _targets.R). This zips the i-th branch to the i-th country of `country_chunks`.
#'
#' Country-carrying targets (country_c1_predictions/measures, country_c2a_evidence)
#' are stamped uniformly too: any existing `country`/`country_iso` columns are
#' dropped first, so the positional country is authoritative and the same call
#' applies to every target. Empty branches pass through (0-row, typed columns).
#'
#' @param target_list A deployment list target (iteration = "list"), one element
#'   per country branch.
#' @param country_chunks The `country_chunks` list target; element i carries the
#'   i-th country's `country` and `country_iso`.
#' @return One flat tibble: every branch row-bound, each stamped with `country`
#'   (human-readable) and `country_iso`.
#' @export
bind_country <- function(target_list, country_chunks) {
  stopifnot(length(target_list) == length(country_chunks))

  first_or_na <- function(x) if (length(x)) x[[1]] else NA_character_
  iso <- purrr::map_chr(country_chunks, ~ first_or_na(unique(.x$country_iso)))
  cty <- purrr::map_chr(country_chunks, ~ first_or_na(unique(.x$country)))

  purrr::map2(target_list, seq_along(target_list), function(df, i) {
    df |>
      dplyr::select(-dplyr::any_of(c("country", "country_iso"))) |>
      dplyr::mutate(country = cty[[i]], country_iso = iso[[i]], .before = 1)
  }) |>
    dplyr::bind_rows()
}


# ---------------------------------------------------------------------------
# Tally builder: per-country reshapes for the C0 / headline figures and tables
# ---------------------------------------------------------------------------

#' Per-country deployment tallies for the report figures and tables
#'
#' The deployment analog of `compute_malay_er_consistency_tallies()`, keyed on
#' country instead of language. Drops the joint cross-language merge probe (no
#' cross-country act merging is attempted) and adds a per-country C0 cluster
#' summary (`c0_summary`) in its place.
#'
#' All inputs are pre-bound flat tibbles (see `bind_country()`).
#'
#' @param c0_acts Bound `country_c0_acts` (year, doc_id, chunk_id, cluster_id,
#'   canonical_name, measure_name, ...).
#' @param c0_clusters Bound `country_c0_clusters` (cluster_id, canonical_name,
#'   measure_name, n_members, ...).
#' @param c2b Bound `country_c2b` (per-act inventory: pred_label, pred_sign,
#'   pred_exogenous, act_name_year, doc_year_modal, ...).
#' @param measure_pool Bound `country_measure_pool` (reserved for parity; not
#'   currently read).
#' @return list(per_doc, per_country = list(counts, labels, act_years),
#'   c0_summary, inventory).
#' @export
compute_deployment_tallies <- function(c0_acts, c0_clusters, c2b, measure_pool) {

  # ----- per_doc: measures/acts and compression per country x year x doc -----
  per_doc <- if (nrow(c0_acts) == 0L) {
    tibble::tibble(country = character(0), country_iso = character(0),
                   year = integer(0), doc_id = character(0),
                   n_measures = integer(0), n_acts = integer(0),
                   compression = double(0))
  } else {
    c0_acts |>
      dplyr::group_by(country, country_iso, year, doc_id) |>
      dplyr::summarize(
        n_measures = dplyr::n_distinct(measure_name),
        n_acts     = dplyr::n_distinct(cluster_id),
        .groups = "drop"
      ) |>
      dplyr::mutate(compression = n_measures / pmax(n_acts, 1L)) |>
      dplyr::arrange(country_iso, year, doc_id)
  }

  # ----- inventory: one row per (country, act) from the C2b output -----
  inventory <- if (nrow(c2b) == 0L) {
    tibble::tibble(
      country = character(0), country_iso = character(0),
      canonical_name = character(0), act_name = character(0),
      act_name_year = integer(0), doc_year_modal = integer(0),
      pred_label = character(0), pred_sign = character(0),
      pred_exogenous = logical(0), confidence = character(0)
    )
  } else {
    c2b |>
      dplyr::transmute(
        country, country_iso, canonical_name, act_name,
        act_name_year, doc_year_modal,
        pred_label, pred_sign, pred_exogenous, confidence
      )
  }

  # ----- per_country: act marginals (counts, labels, act-name years) -----
  per_country <- if (nrow(inventory) == 0L) {
    list(
      counts = tibble::tibble(country = character(0), country_iso = character(0),
                              n_acts = integer(0), n_exogenous = integer(0),
                              n_endogenous = integer(0)),
      labels = tibble::tibble(country = character(0), country_iso = character(0),
                              pred_label = character(0), n = integer(0)),
      act_years = tibble::tibble(country = character(0), country_iso = character(0),
                                 act_name_year = integer(0), n = integer(0))
    )
  } else {
    counts <- inventory |>
      dplyr::group_by(country, country_iso) |>
      dplyr::summarize(
        n_acts       = dplyr::n(),
        n_exogenous  = sum(pred_exogenous %in% TRUE),
        n_endogenous = sum(pred_exogenous %in% FALSE),
        .groups = "drop"
      )
    labels <- inventory |>
      dplyr::count(country, country_iso, pred_label, name = "n")
    act_years <- inventory |>
      dplyr::filter(!is.na(act_name_year)) |>
      dplyr::count(country, country_iso, act_name_year, name = "n")
    list(counts = counts, labels = labels, act_years = act_years)
  }

  # ----- c0_summary: per-country cluster summary (replaces joint merge rate) --
  c0_summary <- if (nrow(c0_clusters) == 0L) {
    tibble::tibble(country = character(0), country_iso = character(0),
                   n_clusters = integer(0), n_variants = integer(0),
                   mean_members = double(0), max_members = integer(0))
  } else {
    c0_clusters |>
      dplyr::group_by(country, country_iso) |>
      dplyr::summarize(
        n_clusters   = dplyr::n_distinct(cluster_id),
        n_variants   = dplyr::n(),
        mean_members = dplyr::n() / dplyr::n_distinct(cluster_id),
        max_members  = max(n_members),
        .groups = "drop"
      )
  }

  list(per_doc = per_doc, per_country = per_country,
       c0_summary = c0_summary, inventory = inventory)
}


# ---------------------------------------------------------------------------
# Plot helpers: country-keyed analogs of the plot_malay_* figures
# ---------------------------------------------------------------------------

# Title-cased country label for fills/facets (e.g. "malaysia" -> "Malaysia").
.country_label <- function(country) stringr::str_to_title(country)

# Shared dodged-bar styling for the country diagnostics. Country fill uses a
# colour-blind-safe qualitative palette (Dark2, 8 colours) rather than a fixed
# two-key palette, so it extends to N deployment countries automatically.
.deployment_country_bar <- function(p) {
  p +
    ggplot2::geom_col(position = ggplot2::position_dodge2(preserve = "single"),
                      width = 0.7) +
    ggplot2::scale_fill_brewer(palette = "Dark2", name = "Country") +
    ggplot2::theme_minimal(base_family = "Libertinus Serif", base_size = 10) +
    ggplot2::theme(panel.grid.major.x = ggplot2::element_blank())
}


#' Document scope: pages and chunks per country-year
#'
#' Pages and chunk counts of each country's corpus by year. Pages and chunks are
#' summed across the documents within a country-year. Empty-safe.
#'
#' @param chunks Bound `country_chunks` (see `bind_country()`).
#' @return A ggplot object, or NULL if the input is empty.
#' @export
plot_deployment_scope <- function(chunks) {
  if (nrow(chunks) == 0L) return(NULL)

  df <- chunks |>
    dplyr::group_by(country, country_iso, year, doc_id) |>
    dplyr::summarize(pages = max(end_page),
                     chunks = dplyr::n_distinct(chunk_id),
                     .groups = "drop") |>
    dplyr::group_by(country, year) |>
    dplyr::summarise(Pages = sum(pages), Chunks = sum(chunks), .groups = "drop") |>
    dplyr::mutate(country = .country_label(country)) |>
    tidyr::pivot_longer(c(Pages, Chunks), names_to = "metric",
                        values_to = "value") |>
    dplyr::mutate(metric = factor(metric, levels = c("Pages", "Chunks")))

  .deployment_country_bar(
    ggplot2::ggplot(df, ggplot2::aes(x = factor(year), y = value, fill = country))
  ) +
    ggplot2::facet_wrap(~ metric, ncol = 1, scales = "free_y") +
    ggplot2::labs(x = "Document year", y = NULL)
}


#' Distinct C1 measure names per year, by country (pre-aggregation)
#'
#' How many distinct fiscal measures C1 surfaces per country-year, before
#' act-level aggregation. Empty-safe.
#'
#' @param c1_measures Bound `country_c1_measures`.
#' @return A ggplot object, or NULL if the input is empty.
#' @export
plot_deployment_c1_comparability <- function(c1_measures) {
  if (nrow(c1_measures) == 0L) return(NULL)

  df <- c1_measures |>
    dplyr::distinct(country, year, measure_name) |>
    dplyr::count(country, year, name = "n_measures") |>
    dplyr::mutate(country = .country_label(country))
  if (nrow(df) == 0L) return(NULL)

  .deployment_country_bar(
    ggplot2::ggplot(df, ggplot2::aes(x = factor(year), y = n_measures, fill = country))
  ) +
    ggplot2::labs(x = "Document year", y = "Distinct fiscal measures")
}


#' Per-year C1 fiscal-measure density by country
#'
#' Raw count of motivated fiscal measures C1 surfaces per country-year, before
#' the rank-1 deployment filter. Measure-dense years carry several times the
#' typical load; density is what the rank-1 cut discards. Empty-safe.
#'
#' @param c1_raw Bound `country_c1_predictions` (long-form, pre-filter).
#' @return A ggplot object, or NULL if no motivated measures are present.
#' @export
plot_deployment_c1_density <- function(c1_raw) {
  if (nrow(c1_raw) == 0L) return(NULL)

  df <- c1_raw |>
    dplyr::filter(pred_label == "FISCAL_MEASURE", discusses_motivation %in% TRUE) |>
    dplyr::distinct(country, year, doc_id, chunk_id, measure_name) |>
    dplyr::count(country, year, name = "raw_measures") |>
    dplyr::mutate(country = .country_label(country))
  if (nrow(df) == 0L) return(NULL)

  .deployment_country_bar(
    ggplot2::ggplot(df, ggplot2::aes(x = factor(year), y = raw_measures, fill = country))
  ) +
    ggplot2::labs(x = "Document year",
                  y = "Motivated fiscal measures\n(before rank-1 filter)")
}


#' Per-year chunk-level fiscal-classification rate by country
#'
#' Share of each country-year's chunks whose most-prominent (rank-1) measure is a
#' motivated fiscal measure. Empty-safe.
#'
#' @param c1_raw Bound `country_c1_predictions` (long-form, pre-filter).
#' @param chunks Bound `country_chunks`.
#' @return A ggplot object, or NULL if either input is empty.
#' @export
plot_deployment_c1_fiscal_rate <- function(c1_raw, chunks) {
  if (nrow(c1_raw) == 0L || nrow(chunks) == 0L) return(NULL)

  tot <- chunks |>
    dplyr::distinct(country, year, doc_id, chunk_id) |>
    dplyr::count(country, year, name = "n_chunks")

  fc <- c1_raw |>
    dplyr::filter(pred_label == "FISCAL_MEASURE", discusses_motivation %in% TRUE,
                  measure_rank == 1L) |>
    dplyr::distinct(country, year, doc_id, chunk_id) |>
    dplyr::count(country, year, name = "fiscal_chunks")

  df <- tot |>
    dplyr::left_join(fc, by = c("country", "year")) |>
    dplyr::mutate(fiscal_chunks = dplyr::coalesce(fiscal_chunks, 0L),
                  fiscal_rate = fiscal_chunks / pmax(n_chunks, 1L),
                  country = .country_label(country))
  if (nrow(df) == 0L) return(NULL)

  .deployment_country_bar(
    ggplot2::ggplot(df, ggplot2::aes(x = factor(year), y = fiscal_rate, fill = country))
  ) +
    ggplot2::scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    ggplot2::labs(x = "Document year",
                  y = "Chunks with a motivated\nrank-1 fiscal measure")
}


#' C0 aggregation compression per year, by country
#'
#' Mean compression ratio (surfaced measures collapsed into distinct acts) per
#' country-year, averaged across that year's documents. Empty-safe.
#'
#' @param per_doc The `per_doc` tibble from `compute_deployment_tallies()`.
#' @return A ggplot object, or NULL if the input is empty.
#' @export
plot_deployment_c0_perdoc <- function(per_doc) {
  if (nrow(per_doc) == 0L) return(NULL)

  df <- per_doc |>
    dplyr::group_by(country, year) |>
    dplyr::summarize(compression = mean(compression), .groups = "drop") |>
    dplyr::mutate(country = .country_label(country))

  .deployment_country_bar(
    ggplot2::ggplot(df, ggplot2::aes(x = factor(year), y = compression, fill = country))
  ) +
    ggplot2::labs(x = "Document year", y = "Compression (measures → acts)")
}


#' Motivation-label marginal distribution by country
#'
#' How many acts each country assigns to each motivation category, with
#' human-readable motivation names. Empty-safe.
#'
#' @param labels The `per_country$labels` tibble from
#'   `compute_deployment_tallies()`.
#' @return A ggplot object, or NULL if the input is empty.
#' @export
plot_deployment_c0_labels <- function(labels) {
  if (nrow(labels) == 0L) return(NULL)

  df <- labels |>
    dplyr::mutate(country = .country_label(country),
                  motivation = pretty_motivation(pred_label))

  .deployment_country_bar(
    ggplot2::ggplot(df, ggplot2::aes(x = motivation, y = n, fill = country))
  ) +
    ggplot2::scale_x_discrete(drop = FALSE) +
    ggplot2::labs(x = "Motivation", y = "Acts")
}


#' Act-name-year multiset by country
#'
#' Count of acts carrying each name-embedded year, by country. Sparse in
#' deployment (most acts carry no name-embedded year). Empty-safe.
#'
#' @param act_years The `per_country$act_years` tibble from
#'   `compute_deployment_tallies()`.
#' @return A ggplot object, or NULL if the input is empty.
#' @export
plot_deployment_act_years <- function(act_years) {
  if (nrow(act_years) == 0L) return(NULL)

  df <- act_years |>
    dplyr::mutate(country = .country_label(country))

  .deployment_country_bar(
    ggplot2::ggplot(df, ggplot2::aes(x = factor(act_name_year), y = n, fill = country))
  ) +
    ggplot2::labs(x = "Act-name year", y = "Acts")
}


#' Timeline of acts as signed motivation counts, faceted by country
#'
#' For each country and year, counts the acts in every motivation × sign cell and
#' draws them as a diverging stacked bar: increases grow the bar upward, decreases
#' downward, no-change acts sit as a neutral band at the baseline. Faceted by
#' country. Colour = motivation label. Reuses `pretty_motivation()` and the shared
#' motivation palette from R/malay_consistency.R.
#'
#' @param inventory The `inventory` tibble from `compute_deployment_tallies()`.
#' @param timing One of "doc_year" (modal source-document year; primary, always
#'   present) or "act_name" (regex year from the act name; sparse in deployment).
#' @return A ggplot object, or NULL if no acts have a year on the chosen axis.
#' @export
plot_deployment_act_timeline <- function(inventory, timing = c("doc_year", "act_name")) {
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
                  country = .country_label(country)) |>
    dplyr::filter(!is.na(.year)) |>
    dplyr::mutate(
      sign = dplyr::case_when(pred_sign %in% c("+", "-") ~ pred_sign,
                              TRUE ~ "0"),
      motivation = dplyr::if_else(sign == "0", "No change",
                                  as.character(pretty_motivation(pred_label)))
    ) |>
    dplyr::count(country, .year, sign, motivation, name = "n") |>
    dplyr::mutate(
      signed_n   = dplyr::if_else(sign == "-", -n, n),
      motivation = factor(motivation,
                          levels = c(unname(.malay_motivation_labels), "No change"))
    )
  if (nrow(df) == 0L) return(NULL)

  ggplot2::ggplot(df, ggplot2::aes(x = factor(.year), y = signed_n,
                                   fill = motivation)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
    ggplot2::scale_fill_manual(values = .malay_motivation_palette,
                               name = "Motivation", drop = FALSE) +
    ggplot2::facet_wrap(~ country, ncol = 1) +
    ggplot2::labs(x = axis_lab, y = "Acts (increase ↑ / decrease ↓)") +
    ggplot2::theme_minimal(base_family = "Libertinus Serif", base_size = 10) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                   panel.grid.major.x = ggplot2::element_blank())
}
