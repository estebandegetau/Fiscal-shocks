# Local projections of Malaysian macro outcomes on narrative statutory tax
# changes, for the Pacific-replication pitch deck (slides/pacific_pitch.qmd).
#
# The shock is measured in PERCENTAGE POINTS OF STATUTORY RATE, not percent of
# GDP. That is deliberate and it is the whole reason this layer can exist while
# wp.qmd still declines to run a local projection: the magnitude column carries
# no validation record beyond the headline statutory rate, and the headline
# statutory rate is exactly what this uses. Nothing here licenses a multiplier.
#
# Reads `tax_shocks` and macro_panel_file directly. It does NOT read the
# `macro_panel` target: clean_macro_panel() keeps only the 19 columns in
# .macro_panel_cols, and pvt_investment / fdi_net_in are not among them.
# Widening that vector would re-hash macro_panel and its six paper-bound
# descendants for no benefit to the paper (Workflow Convention #14), so this
# layer owns a narrow reader of its own. If the paper ever wants investment or
# FDI, that is the moment to widen .macro_panel_cols and retire
# load_lp_outcomes(). Makes no API calls.
#
# Following the project's figure/table split, the data helpers return tidy
# frames and the plot helpers return ggplot objects; only data and statistics
# get targets, the plot helpers are called from the deck's chunks. Reuses
# .exo_palette / pretty_exogenous() / .tax_shock_theme() from
# R/tax_shock_report.R.

# ---- Outcome panel ---------------------------------------------------------

# Outcome -> (source column, facet label, unit). Single source of truth for
# labels and facet order, mirroring .tax_export_dict in R/tax_shock_report.R.
.lp_outcome_defs <- tibble::tribble(
  ~outcome,         ~source_col,       ~outcome_label,       ~unit,
  "gdp_real",       "NGDP_R",          "Real GDP",           "%",
  "pvt_investment", "pvt_investment",  "Private investment", "pp of GDP",
  "fdi_net_in",     "fdi_net_in",      "FDI, net inflows",   "pp of GDP"
)

#' Malaysia annual outcome panel for the local projections
#'
#' Reads the compiled cross-country macro-fiscal panel directly (see
#' `docs/data_sources.md`) and returns the three deck outcomes in long form.
#' Real GDP enters as `100 * log()` so the projection coefficient reads as a
#' cumulative percent response; the other two are already ratios to GDP and
#' enter in levels, so their coefficients read in percentage points.
#'
#' The default `year_max` is 2019 because `pvt_investment` ends that year.
#' Because the projections take a **lead** of the outcome, an h=5 regression on
#' a 2019 window draws its last usable observation from 2014, so no pandemic
#' year enters any regression at any horizon.
#'
#' @param path Path to Full_sample_filtered.dta (the `macro_panel_file` target).
#' @param iso ISO3 country code (`ccode`).
#' @param year_min,year_max Inclusive year window.
#' @return Tibble with one row per outcome x year: `year`, `outcome`,
#'   `outcome_label`, `value`.
#' @export
load_lp_outcomes <- function(path, iso = "MYS",
                             year_min = 1980L, year_max = 2019L) {
  raw <- haven::read_dta(path)

  needed <- c("ccode", "year", .lp_outcome_defs$source_col)
  missing <- setdiff(needed, names(raw))
  if (length(missing) > 0) {
    stop("macro panel is missing expected columns: ",
         paste(missing, collapse = ", "))
  }

  wide <- raw |>
    haven::zap_labels() |>
    haven::zap_label() |>
    dplyr::filter(.data$ccode == iso) |>
    dplyr::transmute(
      year           = as.integer(.data$year),
      gdp_real       = 100 * log(as.numeric(.data$NGDP_R)),
      pvt_investment = as.numeric(.data$pvt_investment),
      fdi_net_in     = as.numeric(.data$fdi_net_in)
    ) |>
    dplyr::filter(.data$year >= year_min, .data$year <= year_max)

  if (nrow(wide) == 0L) return(tibble::tibble())

  wide |>
    tidyr::pivot_longer(-"year", names_to = "outcome", values_to = "value") |>
    dplyr::left_join(dplyr::select(.lp_outcome_defs, "outcome", "outcome_label"),
                     by = "outcome") |>
    dplyr::mutate(
      outcome = factor(.data$outcome, levels = .lp_outcome_defs$outcome),
      outcome_label = factor(.data$outcome_label,
                             levels = .lp_outcome_defs$outcome_label)
    ) |>
    dplyr::arrange(.data$outcome, .data$year)
}

# ---- Shock series ----------------------------------------------------------

#' Drop shocks held back from the deck's exhibits
#'
#' One place the deck's exclusion list is applied, so the shock series and the
#' slide-1 figure always describe the same set of events.
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @param exclude_ids Character vector of `shock_id`s to drop.
#' @return `tax_shocks` without those rows.
#' @export
filter_analysis_shocks <- function(tax_shocks, exclude_ids = character()) {
  if (nrow(tax_shocks) == 0L) return(tibble::tibble())
  dplyr::filter(tax_shocks, !.data$shock_id %in% exclude_ids)
}

#' Annual statutory tax-shock series
#'
#' Sums signed statutory rate changes to the year, **signed so that positive is
#' a tax cut**, which makes a positive projection coefficient an expansionary
#' response and keeps the IRF readable without a sign note. Non-rate acts
#' (`delta_pp` NA) and neutral acts (`delta_pp` zero) contribute nothing and are
#' dropped, so they appear on the inventory figure but not in the estimation.
#'
#' Two series are returned side by side: every rate-bearing act, and only those
#' C2b labelled exogenous. The contrast between them is the deck's argument.
#'
#' Years with no act are filled with zero rather than left absent. This is not
#' cosmetic: a join leaving NAs would silently drop most of the sample inside
#' `lm()`.
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @param timing `"effective"` keys on `effective_year`, `"announced"` on
#'   `announced_year`.
#' @param exclude_ids `shock_id`s to hold back (see `filter_analysis_shocks()`).
#' @param tax_types Optional character vector of `tax_type` values to keep
#'   (e.g. `"CIT"`). `NULL` keeps every instrument. Restricting to one
#'   instrument makes the percentage points comparable to one another, which
#'   pooling across CIT, PIT and consumption does not.
#' @param shock_form `"pp"` sums the signed percentage-point changes;
#'   `"indicator"` replaces that sum with its sign, so every event year counts
#'   the same. Use the indicator when cut sizes are few and may be collinear
#'   with the period they occurred in, which makes a continuous dose-response
#'   slope an era comparison rather than a tax effect.
#' @param year_min,year_max Inclusive year window for the returned grid.
#' @return Tibble with one row per year: `year`, `shock_all`, `shock_exo`,
#'   `n_events` (rate-bearing acts that year), `n_events_exo`.
#' @export
build_lp_shock_series <- function(tax_shocks,
                                  timing = c("effective", "announced"),
                                  exclude_ids = character(),
                                  tax_types = NULL,
                                  shock_form = c("pp", "indicator"),
                                  year_min = 1980L, year_max = 2019L) {
  timing <- match.arg(timing)
  shock_form <- match.arg(shock_form)
  year_col <- if (timing == "effective") "effective_year" else "announced_year"

  grid <- tibble::tibble(year = seq.int(year_min, year_max))
  if (nrow(tax_shocks) == 0L) {
    return(dplyr::mutate(grid, shock_all = 0, shock_exo = 0,
                         n_events = 0L, n_events_exo = 0L))
  }

  ev <- tax_shocks |>
    filter_analysis_shocks(exclude_ids)

  if (!is.null(tax_types)) {
    ev <- dplyr::filter(ev, .data$tax_type %in% tax_types)
  }

  ev <- ev |>
    dplyr::filter(!is.na(.data$delta_pp), .data$delta_pp != 0,
                  !is.na(.data[[year_col]])) |>
    dplyr::mutate(year = as.integer(.data[[year_col]]),
                  # Positive = tax cut.
                  impulse = -.data$delta_pp,
                  # `%in% TRUE` so an NA label never counts as exogenous.
                  is_exo = .data$c2b_exogenous %in% TRUE) |>
    dplyr::filter(.data$year >= year_min, .data$year <= year_max)

  out <- ev |>
    dplyr::group_by(.data$year) |>
    dplyr::summarise(
      shock_all    = sum(.data$impulse),
      shock_exo    = sum(.data$impulse[.data$is_exo]),
      n_events     = dplyr::n(),
      n_events_exo = sum(.data$is_exo),
      .groups = "drop"
    ) |>
    dplyr::right_join(grid, by = "year") |>
    tidyr::replace_na(list(shock_all = 0, shock_exo = 0,
                           n_events = 0L, n_events_exo = 0L)) |>
    dplyr::arrange(.data$year)

  # The indicator form replaces the summed size with its sign, so a net-cut year
  # counts +1 and a net-hike year -1 regardless of how many percentage points
  # moved. It exists because a continuous size is only informative when cut
  # sizes vary independently of when they happened; on a small, clumped
  # subsample they may not, and then the "dose-response" slope is really a
  # comparison of the eras the doses fell in.
  if (shock_form == "indicator") {
    out <- dplyr::mutate(out,
                         shock_all = sign(.data$shock_all),
                         shock_exo = sign(.data$shock_exo))
  }

  out
}

# ---- Estimation ------------------------------------------------------------

# One horizon of one outcome on one shock variant. Returns a one-row tibble
# rather than erroring when the cell is not estimable, so a thin sample degrades
# to a gap in the IRF instead of failing the target.
.lp_fit_one <- function(d, h, level, hac_adjust) {
  na_row <- tibble::tibble(horizon = h, beta = NA_real_, se = NA_real_,
                           t = NA_real_, n = NA_integer_, hac_lag = h + 1L)

  dd <- d |>
    dplyr::arrange(.data$year) |>
    dplyr::mutate(
      dy    = .data$value - dplyr::lag(.data$value),
      y_h   = dplyr::lead(.data$value, h) - dplyr::lag(.data$value, 1),
      dy_l1 = dplyr::lag(.data$dy, 1),
      s_l1  = dplyr::lag(.data$shock, 1)
    )

  if (stats::sd(dd$shock, na.rm = TRUE) == 0) return(na_row)

  fit <- stats::lm(y_h ~ shock + dy_l1 + s_l1, data = dd)
  if (stats::nobs(fit) < 10L || anyNA(stats::coef(fit))) return(na_row)

  vcov_hac <- sandwich::NeweyWest(fit, lag = h + 1L, prewhite = FALSE,
                                  adjust = hac_adjust)
  beta <- unname(stats::coef(fit)[["shock"]])
  se   <- sqrt(vcov_hac["shock", "shock"])

  tibble::tibble(horizon = h, beta = beta, se = se, t = beta / se,
                 n = as.integer(stats::nobs(fit)), hac_lag = h + 1L)
}

#' Jorda (2005) local projections of the deck outcomes on the tax shock
#'
#' Estimates, for each outcome and each shock variant, the sequence
#' `y_{t+h} - y_{t-1} = a + b_h * shock_t + c * dy_{t-1} + d * shock_{t-1} + e`,
#' with Newey-West HAC standard errors at lag `h + 1`. The dependent variable is
#' cumulative from the pre-period `t-1`, which is the standard construction and
#' is fixed here on a priori grounds: the sign pattern in this sample is not
#' robust to changing it, so it must not be chosen by inspection.
#'
#' `lmtest` is not a project dependency, so the coefficient row is assembled by
#' hand from the HAC variance matrix and the interval uses normal rather than
#' t critical values.
#'
#' @param outcomes `load_lp_outcomes()` output.
#' @param shocks `build_lp_shock_series()` output.
#' @param horizons Integer vector of projection horizons.
#' @param level Confidence level for the reported interval.
#' @param hac_adjust Passed to `sandwich::NeweyWest()`; `TRUE` applies the
#'   n/(n-k) finite-sample correction, which is not negligible at n ~ 35.
#' @return Tibble with one row per outcome x variant x horizon: `outcome`,
#'   `outcome_label`, `variant`, `variant_label`, `horizon`, `beta`, `se`, `t`,
#'   `n`, `hac_lag`, `ci_lo`, `ci_hi`.
#' @export
estimate_lp <- function(outcomes, shocks, horizons = 0:5,
                        level = 0.90, hac_adjust = TRUE) {
  if (nrow(outcomes) == 0L || nrow(shocks) == 0L) return(tibble::tibble())

  long_shocks <- shocks |>
    dplyr::select("year", "shock_all", "shock_exo") |>
    tidyr::pivot_longer(-"year", names_to = "variant", values_to = "shock") |>
    dplyr::mutate(variant = sub("^shock_", "", .data$variant))

  panel <- outcomes |>
    dplyr::inner_join(long_shocks, by = "year", relationship = "many-to-many")

  crit <- stats::qnorm(1 - (1 - level) / 2)

  panel |>
    dplyr::group_by(.data$outcome, .data$outcome_label, .data$variant) |>
    dplyr::group_modify(function(d, key) {
      purrr::map_dfr(horizons, \(h) .lp_fit_one(d, h, level, hac_adjust))
    }) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      variant_label = factor(
        dplyr::if_else(.data$variant == "all",
                       "All rate changes", "Narrative-exogenous only"),
        levels = c("All rate changes", "Narrative-exogenous only")
      ),
      ci_lo = .data$beta - crit * .data$se,
      ci_hi = .data$beta + crit * .data$se
    ) |>
    dplyr::arrange(.data$outcome, .data$variant, .data$horizon)
}

# ---- Presentation layer (no targets; called from the deck's chunks) --------

# Deck figures are projected, not printed in a text block, so they need a
# larger base size than .tax_shock_theme()'s 10pt and a family that matches the
# pptx template rather than the manuscript's serif.
.deck_theme <- function(base_size = 14, base_family = "sans") {
  ggplot2::theme_minimal(base_family = base_family, base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      legend.position  = "top",
      legend.title     = ggplot2::element_blank(),
      strip.text       = ggplot2::element_text(face = "bold", hjust = 0)
    )
}

#' Statutory tax-change inventory for slide 1
#'
#' One bar per act, height = the signed statutory rate change in percentage
#' points, faceted by tax type, filled by C2b exogeneity. Deliberately encodes
#' pp rather than act counts (which is what `plot_tax_timeline()` does for the
#' manuscript), because the deck's second slide is denominated in pp and the two
#' figures have to be read against each other. Acts with no rate change are
#' drawn as a short neutral tick at the baseline so they remain visible in the
#' inventory without implying a magnitude.
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @param exclude_ids `shock_id`s to hold back.
#' @param timing `"effective"` or `"announced"`; keys the x axis.
#' @param base_size,base_family Passed to the deck theme.
#' @return A ggplot, or NULL if there is nothing to show.
#' @export
plot_tax_events_slide <- function(tax_shocks, exclude_ids = character(),
                                  timing = c("effective", "announced"),
                                  base_size = 14, base_family = "sans") {
  timing <- match.arg(timing)
  year_col <- if (timing == "effective") "effective_year" else "announced_year"
  if (nrow(tax_shocks) == 0L) return(NULL)

  tl <- tax_shocks |>
    filter_analysis_shocks(exclude_ids) |>
    dplyr::filter(!is.na(.data[[year_col]])) |>
    dplyr::mutate(
      year       = as.integer(.data[[year_col]]),
      exogeneity = pretty_exogenous(.data$c2b_exogenous),
      change_pp  = dplyr::if_else(is.na(.data$delta_pp), 0, .data$delta_pp),
      has_rate   = !is.na(.data$delta_pp) & .data$delta_pp != 0,
      tax_label  = dplyr::recode(.data$tax_type,
                                 CIT = "Corporate income",
                                 PIT = "Personal income",
                                 CONSUMPTION = "Consumption (GST/SST)")
    )
  if (nrow(tl) == 0L) return(NULL)

  tl$tax_label <- factor(tl$tax_label,
                         levels = c("Corporate income", "Personal income",
                                    "Consumption (GST/SST)"))

  ggplot2::ggplot(tl, ggplot2::aes(.data$year, .data$change_pp,
                                   fill = .data$exogeneity)) +
    ggplot2::geom_col(width = 0.9) +
    # Non-rate acts: a short tick so the act is on the inventory without
    # claiming a size.
    ggplot2::geom_point(data = ~ dplyr::filter(.x, !.data$has_rate),
                        ggplot2::aes(y = 0), shape = 21, size = 2.4,
                        colour = "grey30", show.legend = FALSE) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
    # Free scales: a percentage point of GST and a percentage point of corporate
    # income tax are not comparable quantities (the same reason the projection's
    # pooled-pp shock carries a caveat), and a shared scale lets the 6 pp GST
    # introduction flatten every income-tax change into invisibility.
    ggplot2::facet_wrap(~ tax_label, ncol = 1, scales = "free_y") +
    ggplot2::scale_x_continuous(breaks = scales::breaks_width(5)) +
    ggplot2::scale_fill_manual(values = .exo_palette, drop = FALSE,
                               na.value = "grey75") +
    ggplot2::labs(x = NULL, y = "Statutory rate change (pp)") +
    .deck_theme(base_size, base_family)
}

#' Impulse responses for slide 2
#'
#' Two lines per outcome: every statutory rate change, and only the acts C2b
#' labelled exogenous. The band is drawn on the exogenous line only, so the
#' contrast between the two paths stays legible at projection size.
#'
#' @param lp_results `estimate_lp()` output.
#' @param band Draw the confidence ribbon (`"exo"`, `"both"`, or `"none"`).
#' @param variant_labels Named character vector overriding the legend text,
#'   with names `"all"` and `"exo"`. The default matches the generic labels
#'   `estimate_lp()` emits; pass instrument-specific ones when the series has
#'   been restricted, so the legend cannot overstate what is in the shock.
#' @param y_lab Y axis label. The default names the shock's unit; override it
#'   when the series is restricted to one instrument.
#' @param show_units Append each outcome's unit to its facet strip. The three
#'   outcomes are not in the same units -- real GDP is a cumulative percent
#'   deviation, the two ratios are in percentage points of GDP -- so a single
#'   shared axis label cannot describe all three panels correctly.
#' @param base_size,base_family Passed to the deck theme.
#' @return A ggplot, or NULL if there is nothing to show.
#' @export
plot_lp_irf <- function(lp_results, band = c("exo", "both", "none"),
                        variant_labels = c(all = "All rate changes",
                                           exo = "Narrative-exogenous only"),
                        y_lab = "Response to a 1 pp tax cut",
                        show_units = TRUE,
                        base_size = 14, base_family = "sans") {
  band <- match.arg(band)
  if (nrow(lp_results) == 0L) return(NULL)

  stopifnot(all(c("all", "exo") %in% names(variant_labels)))

  # Relabel from the generic `variant` key rather than editing `variant_label`,
  # so the target output stays instrument-agnostic and only the figure is
  # specialised.
  lp_results <- dplyr::mutate(
    lp_results,
    variant_label = factor(unname(variant_labels[.data$variant]),
                           levels = unname(variant_labels[c("all", "exo")]))
  )

  if (show_units) {
    units <- stats::setNames(
      dplyr::recode(.lp_outcome_defs$unit,
                    "%" = "cumulative %", "pp of GDP" = "pp of GDP"),
      .lp_outcome_defs$outcome_label
    )
    lev <- levels(lp_results$outcome_label)
    lab <- paste0(lev, "  (", unname(units[lev]), ")")
    lp_results <- dplyr::mutate(
      lp_results,
      outcome_label = factor(paste0(.data$outcome_label, "  (",
                                    unname(units[as.character(.data$outcome_label)]),
                                    ")"),
                             levels = lab)
    )
  }

  pal <- stats::setNames(c("grey55", unname(.exo_palette[["Exogenous"]])),
                         unname(variant_labels[c("all", "exo")]))
  lty <- stats::setNames(c("22", "solid"),
                         unname(variant_labels[c("all", "exo")]))

  ribbon_dat <- switch(
    band,
    exo  = dplyr::filter(lp_results, .data$variant == "exo"),
    both = lp_results,
    none = lp_results[0, ]
  )

  ggplot2::ggplot(lp_results,
                  ggplot2::aes(.data$horizon, .data$beta,
                               colour = .data$variant_label)) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
    ggplot2::geom_ribbon(
      data = ribbon_dat,
      ggplot2::aes(ymin = .data$ci_lo, ymax = .data$ci_hi,
                   fill = .data$variant_label),
      alpha = 0.13, colour = NA, show.legend = FALSE
    ) +
    ggplot2::geom_line(ggplot2::aes(linetype = .data$variant_label),
                       linewidth = 0.9) +
    ggplot2::geom_point(size = 1.7, show.legend = FALSE) +
    ggplot2::facet_wrap(~ outcome_label, nrow = 1, scales = "free_y") +
    ggplot2::scale_colour_manual(values = pal) +
    ggplot2::scale_fill_manual(values = pal) +
    ggplot2::scale_linetype_manual(values = lty) +
    ggplot2::scale_x_continuous(breaks = scales::breaks_width(1)) +
    ggplot2::labs(x = "Years after the change", y = y_lab) +
    .deck_theme(base_size, base_family)
}
