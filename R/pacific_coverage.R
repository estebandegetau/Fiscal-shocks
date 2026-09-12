# Statutory-rate data coverage for Pacific Island Countries, for the
# replication pitch deck (slides/pacific_pitch.qmd).
#
# The deck's closing argument is a coverage gap, not an estimate: the Pacific
# appears in the macro aggregates every cross-country growth study uses, and is
# absent from the statutory-rate panel any fiscal-shock study would need. This
# reads the same compiled panel as the local-projection layer
# (docs/data_sources.md) and counts usable years per series per country.
#
# Following the project's figure/table split, the summary helper returns tidy
# data and the plot helper returns a ggplot; only the data gets a target.
# Reuses .deck_theme() from R/local_projections.R. Makes no API calls.

# The Pacific Island countries the deck speaks about, with the ISO3 codes the
# panel uses. Countries absent from the panel entirely are still listed: their
# absence is the point, and a figure that silently omitted them would understate
# the gap.
.pic_iso_set <- c("FJI", "PNG", "SLB", "VUT", "TON", "KIR", "FSM",
                  "MHL", "TUV", "TLS", "WSM", "PLW", "COK", "NRU")

.pic_names <- c(
  FJI = "Fiji",              PNG = "Papua New Guinea", SLB = "Solomon Islands",
  VUT = "Vanuatu",           TON = "Tonga",            KIR = "Kiribati",
  FSM = "Micronesia",        MHL = "Marshall Islands", TUV = "Tuvalu",
  TLS = "Timor-Leste",       WSM = "Samoa",            PLW = "Palau",
  COK = "Cook Islands",      NRU = "Nauru",            MYS = "Malaysia"
)

#' Statutory-rate coverage for the Pacific, against a reference country
#'
#' Counts non-missing years per series within the window. `rate_yrs` is the
#' number of years with *any* statutory rate (corporate, personal or VAT),
#' which is the series a narrative fiscal-shock study would be benchmarked
#' against. Countries not present in the panel at all are returned with zero
#' coverage and `in_panel = FALSE`.
#'
#' @param path Path to Full_sample_filtered.dta (the `macro_panel_file` target).
#' @param iso_set ISO3 codes to report.
#' @param reference_iso Comparison country shown alongside (the pilot).
#' @param year_min,year_max Inclusive year window.
#' @return Tibble with one row per country: `ccode`, `country`, `is_reference`,
#'   `in_panel`, `gdp_yrs`, `fdi_yrs`, `cit_yrs`, `pit_yrs`, `vat_yrs`,
#'   `rate_yrs`.
#' @export
summarise_pacific_coverage <- function(path, iso_set = .pic_iso_set,
                                       reference_iso = "MYS",
                                       year_min = 1990L, year_max = 2019L) {
  raw <- haven::read_dta(path)

  needed <- c("ccode", "year", "NGDP_R", "fdi_net_in",
              "corporate_tr", "individual_tr", "vat_tr")
  missing <- setdiff(needed, names(raw))
  if (length(missing) > 0) {
    stop("macro panel is missing expected columns: ",
         paste(missing, collapse = ", "))
  }

  wanted <- unique(c(iso_set, reference_iso))

  observed <- raw |>
    haven::zap_labels() |>
    haven::zap_label() |>
    dplyr::mutate(year = as.integer(.data$year)) |>
    dplyr::filter(.data$ccode %in% wanted,
                  .data$year >= year_min, .data$year <= year_max) |>
    dplyr::group_by(.data$ccode) |>
    dplyr::summarise(
      gdp_yrs = sum(!is.na(.data$NGDP_R)),
      fdi_yrs = sum(!is.na(.data$fdi_net_in)),
      cit_yrs = sum(!is.na(.data$corporate_tr)),
      pit_yrs = sum(!is.na(.data$individual_tr)),
      vat_yrs = sum(!is.na(.data$vat_tr)),
      rate_yrs = sum(!is.na(.data$corporate_tr) | !is.na(.data$individual_tr) |
                       !is.na(.data$vat_tr)),
      .groups = "drop"
    ) |>
    dplyr::mutate(in_panel = TRUE)

  tibble::tibble(ccode = wanted) |>
    dplyr::left_join(observed, by = "ccode") |>
    tidyr::replace_na(list(gdp_yrs = 0L, fdi_yrs = 0L, cit_yrs = 0L,
                           pit_yrs = 0L, vat_yrs = 0L, rate_yrs = 0L,
                           in_panel = FALSE)) |>
    dplyr::mutate(
      country      = unname(.pic_names[.data$ccode]),
      country      = dplyr::coalesce(.data$country, .data$ccode),
      is_reference = .data$ccode == reference_iso
    ) |>
    dplyr::select("ccode", "country", "is_reference", "in_panel",
                  "gdp_yrs", "fdi_yrs", "cit_yrs", "pit_yrs", "vat_yrs",
                  "rate_yrs") |>
    dplyr::arrange(dplyr::desc(.data$is_reference), .data$rate_yrs,
                   .data$country)
}

#' Coverage gap figure for slide 3
#'
#' One row per country, a segment running from years of statutory-rate data to
#' years of real GDP data. The gap is the argument: these countries are in every
#' cross-country growth dataset and in no fiscal-shock dataset.
#'
#' @param coverage `summarise_pacific_coverage()` output.
#' @param base_size,base_family Passed to the deck theme.
#' @return A ggplot, or NULL if there is nothing to show.
#' @export
plot_pacific_coverage <- function(coverage, base_size = 14,
                                  base_family = "sans") {
  if (nrow(coverage) == 0L) return(NULL)

  dat <- coverage |>
    dplyr::mutate(
      label = dplyr::case_when(
        .data$is_reference ~ paste0(.data$country, " (pilot)"),
        !.data$in_panel    ~ paste0(.data$country, " (not in panel)"),
        TRUE               ~ .data$country
      ),
    ) |>
    # Explicit level order rather than fct_reorder: ties at zero rate-years are
    # common here, and reorder() breaks them by input order, which scattered the
    # zero-coverage countries either side of the full-coverage ones. Bottom to
    # top: countries absent from the panel, then present-but-no-rate-data, then
    # full coverage.
    dplyr::arrange(.data$in_panel, .data$rate_yrs, .data$gdp_yrs,
                   dplyr::desc(.data$country)) |>
    dplyr::mutate(label = factor(.data$label, levels = .data$label))

  # Countries absent from the panel have no GDP series to connect to. Their
  # GDP/segment coordinates are set NA rather than the rows being filtered out:
  # passing a subset to the first layer lets that layer, not the factor, set the
  # discrete scale order, which silently scrambled the ranking.
  dat <- dat |>
    dplyr::mutate(gdp_plot = dplyr::if_else(.data$in_panel,
                                            as.numeric(.data$gdp_yrs),
                                            NA_real_))

  ggplot2::ggplot(dat, ggplot2::aes(y = .data$label)) +
    ggplot2::geom_segment(
      ggplot2::aes(x = .data$rate_yrs, xend = .data$gdp_plot, yend = .data$label),
      colour = "grey80", linewidth = 1.6, na.rm = TRUE
    ) +
    # GDP drawn first and larger so the two stay distinguishable where a
    # country has full coverage and the points coincide.
    ggplot2::geom_point(ggplot2::aes(x = .data$gdp_plot, colour = "Real GDP"),
                        size = 4, na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(x = .data$rate_yrs,
                                     colour = "Statutory tax rates (Vegh and Vuletin)"), size = 2.4) +
    ggplot2::scale_colour_manual(
      values = c("Real GDP" = "grey55",
                 "Statutory tax rates (Vegh and Vuletin)" = unname(.exo_palette[["Endogenous"]]))
    ) +
    ggplot2::labs(x = "Years of data available, 1990-2019", y = NULL) +
    .deck_theme(base_size, base_family)
}
