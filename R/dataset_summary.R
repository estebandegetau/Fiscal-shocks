# Cross-component summaries of the deliverable inventory
#
# The three component deliverables (statutory tax, spending, incentives) share
# a contract but differ in a few columns. These helpers bind them into one
# frame so the manuscript can show the dataset as a whole before it shows the
# schema.
#
# Following the project's figure/table split, the summary helpers return tidy
# data (the consuming chunk applies tt()) and the plot helpers return ggplot
# objects.

#' Bind the three component deliverables into one long frame
#'
#' Keeps only the columns common to all three, plus a `component` key and a
#' single `category` column carrying whichever component-specific taxonomy the
#' row belongs to.
#'
#' @param tax,spending,incentive Deliverable tibbles. Any may be empty.
#' @return Tibble with one row per event, or an empty tibble
bind_components <- function(tax = NULL, spending = NULL, incentive = NULL) {
  take <- function(x, component, category_col) {
    if (is.null(x) || nrow(x) == 0) return(NULL)
    x |>
      dplyr::mutate(
        component = component,
        category  = if (category_col %in% names(x)) .data[[category_col]] else NA_character_
      ) |>
      dplyr::select(
        component, category, shock_id, act_label,
        dplyr::any_of(c("tax_type", "direction", "delta_pp", "magnitude_note",
                        "announced_year", "effective_year",
                        "exogenous_preliminary", "c2b_label", "c2b_exogenous",
                        "c2b_sign", "n_chunks", "n_evidence_items")),
        member_chunks, sources
      )
  }

  out <- dplyr::bind_rows(
    take(tax,       "Statutory tax", "tax_type"),
    take(spending,  "Spending",      "spending_category"),
    take(incentive, "Incentives",    "incentive_category")
  )

  if (is.null(out) || nrow(out) == 0) return(tibble::tibble())

  out |>
    dplyr::mutate(
      component = factor(component,
                         levels = c("Statutory tax", "Spending", "Incentives")),
      year = dplyr::coalesce(as.integer(effective_year),
                             as.integer(announced_year))
    )
}

#' Headline summary statistics per component
#'
#' @param tax,spending,incentive Deliverable tibbles
#' @return Tidy tibble, one row per component plus an "All components" row
dataset_summary_stats <- function(tax = NULL, spending = NULL, incentive = NULL) {
  ev <- bind_components(tax, spending, incentive)
  if (nrow(ev) == 0) return(tibble::tibble())

  summarise_block <- function(d, label) {
    docs <- unique(unlist(lapply(d$sources, function(s) s$doc_id)))
    chunks <- sum(vapply(d$member_chunks,
                         function(m) if (is.null(m)) 0L else nrow(m), integer(1)))
    n_exo <- sum(d$c2b_exogenous %in% TRUE)
    tibble::tibble(
      Component   = label,
      Events      = nrow(d),
      Years       = sprintf("%d–%d", min(d$year, na.rm = TRUE),
                            max(d$year, na.rm = TRUE)),
      Documents   = length(docs),
      Chunks      = chunks,
      # One direction column suffices: `Events` carries the total, so the
      # complement (hikes and the handful of neutral restructurings) is
      # recoverable without a second column.
      Cuts        = sum(d$direction %in% c("Cut", "Decrease")),
      Exogenous   = sprintf("%d (%.0f%%)", n_exo, 100 * n_exo / nrow(d))
    )
  }

  per_component <- ev |>
    dplyr::group_split(component) |>
    lapply(function(d) summarise_block(d, as.character(d$component[1]))) |>
    dplyr::bind_rows()

  dplyr::bind_rows(per_component, summarise_block(ev, "All components"))
}

#' The whole inventory at a glance
#'
#' One mark per event on a year axis, split by component. Direction sets the
#' colour, the preliminary exogeneity read sets the shape, so the reader sees
#' the shape of the dataset — coverage, density, and the exogenous/endogenous
#' mix — before meeting the schema.
#'
#' @param tax,spending,incentive Deliverable tibbles
#' @return ggplot object, or NULL if there is nothing to plot
plot_dataset_overview <- function(tax = NULL, spending = NULL, incentive = NULL) {
  ev <- bind_components(tax, spending, incentive)
  if (nrow(ev) == 0) return(NULL)

  plot_data <- ev |>
    dplyr::filter(!is.na(year)) |>
    dplyr::mutate(
      Direction = dplyr::case_when(
        direction %in% c("Hike", "Increase") ~ "Raises liabilities / spending",
        direction %in% c("Cut", "Decrease")  ~ "Lowers liabilities / spending",
        TRUE                                  ~ "Neutral or restructuring"
      ),
      Exogeneity = dplyr::case_when(
        c2b_exogenous %in% TRUE  ~ "Exogenous (preliminary)",
        c2b_exogenous %in% FALSE ~ "Endogenous (preliminary)",
        TRUE                     ~ "Unclassified"
      )
    ) |>
    # Stack events sharing a year within a component so none is hidden.
    dplyr::group_by(component, year) |>
    dplyr::mutate(offset = dplyr::row_number() - (dplyr::n() + 1) / 2) |>
    dplyr::ungroup()

  ggplot2::ggplot(plot_data,
    ggplot2::aes(x = year, y = offset, colour = Direction, shape = Exogeneity)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey88", linewidth = 0.3) +
    ggplot2::geom_point(size = 2.4, stroke = 0.7) +
    ggplot2::facet_wrap(~component, ncol = 1, strip.position = "top") +
    ggplot2::scale_colour_manual(values = c(
      "Raises liabilities / spending" = "#C62828",
      "Lowers liabilities / spending" = "#1565C0",
      "Neutral or restructuring"      = "#757575"
    )) +
    ggplot2::scale_shape_manual(values = c(
      "Exogenous (preliminary)"  = 16,
      "Endogenous (preliminary)" = 1,
      "Unclassified"             = 4
    )) +
    ggplot2::scale_y_continuous(breaks = NULL, expand = ggplot2::expansion(add = 1)) +
    ggplot2::labs(x = "Year of effect", y = NULL, colour = NULL, shape = NULL) +
    ggplot2::guides(
      colour = ggplot2::guide_legend(order = 1, nrow = 1),
      shape  = ggplot2::guide_legend(
        order = 2, nrow = 1,
        override.aes = list(colour = "grey30")
      )
    ) +
    ggplot2::theme(
      legend.position = "top",
      # Stacked, not side-by-side: two horizontal legend blocks overflow the
      # single-column page width and clip their last entry.
      legend.box = "vertical",
      legend.margin = ggplot2::margin(0, 0, 0, 0),
      legend.spacing.y = ggplot2::unit(1, "pt"),
      panel.grid.major.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank()
    )
}

#' Normalise the corpus frame to one row per document with a display series
#'
#' Shared by the corpus table and the coverage figure so the two never disagree
#' about which document belongs to which series.
#'
#' @param country_body Extracted-document tibble, or the list the branched
#'   target returns, with body, doc_language, year and n_pages
#' @return Tibble with `Series` and `Language` added, or an empty tibble
corpus_series_frame <- function(country_body) {
  docs <- if (is.list(country_body) && !is.data.frame(country_body)) {
    dplyr::bind_rows(country_body)
  } else {
    country_body
  }
  if (is.null(docs) || nrow(docs) == 0) return(tibble::tibble())

  docs |>
    dplyr::mutate(
      Series = dplyr::case_when(
        grepl("economic_report", body, ignore.case = TRUE) ~
          "Economic Report / Tinjauan Ekonomi",
        TRUE ~ body
      ),
      Language = dplyr::if_else(tolower(doc_language) == "bm",
                                "Bahasa Malaysia", "English")
    )
}

#' Corpus coverage across the deployment window
#'
#' Pages available per year, stacked by document series. Where the corpus table
#' reports totals, this shows the shape of the record over time: which years
#' rest on a single series, where the bilingual overlap sits, and the gaps no
#' series covers.
#'
#' @param country_body Extracted-document tibble or branched list
#' @return ggplot object, or NULL if there is nothing to plot
plot_corpus_coverage <- function(country_body) {
  tidy <- corpus_series_frame(country_body)
  if (nrow(tidy) == 0) return(NULL)

  per_year <- tidy |>
    # Documents catalogued but not yet acquired carry zero pages; they are
    # absent from the corpus, so they are absent from the coverage picture.
    dplyr::filter(!is.na(year), n_pages > 0) |>
    dplyr::mutate(
      # Split the one series that exists in both languages, so the bilingual
      # decade the cross-language test depends on is visible in the figure.
      key = dplyr::if_else(Language == "Bahasa Malaysia",
                           paste0(Series, " (BM)"), Series),
      key = stringr::str_wrap(key, width = 26)
    ) |>
    dplyr::group_by(key, year) |>
    dplyr::summarise(Pages = sum(n_pages, na.rm = TRUE), .groups = "drop")

  if (nrow(per_year) == 0) return(NULL)

  ggplot2::ggplot(per_year, ggplot2::aes(x = year, y = Pages, fill = key)) +
    ggplot2::geom_col(width = 0.85) +
    ggplot2::scale_fill_brewer(palette = "Set2") +
    ggplot2::scale_x_continuous(breaks = scales::breaks_width(5)) +
    ggplot2::scale_y_continuous(labels = scales::comma,
                                expand = ggplot2::expansion(mult = c(0, 0.05))) +
    ggplot2::labs(x = NULL, y = "Extracted pages", fill = NULL) +
    ggplot2::guides(fill = ggplot2::guide_legend(ncol = 2)) +
    ggplot2::theme(
      legend.position = "top",
      legend.text = ggplot2::element_text(size = ggplot2::rel(0.75)),
      legend.key.size = ggplot2::unit(0.8, "lines"),
      legend.margin = ggplot2::margin(0, 0, 0, 0),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank()
    )
}

#' Corpus scope behind the deliverable
#'
#' What was actually read: documents, pages and year coverage per series. Sits
#' at the head of the dataset-construction section.
#'
#' @param country_body Extracted-document tibble (or the list the branched
#'   target returns) with body, doc_language, year and n_pages
#' @return Tidy tibble, one row per document series plus a total
#'
#' @details The corpus target catalogues every document the acquisition pass
#'   identified, including those whose PDF has not been obtained yet
#'   (`n_pages == 0`, `access_status == "manual_pending"`). Counting those as
#'   corpus would overstate what the codebooks actually read, so `Documents`,
#'   `Pages` and `Year span` describe only the extracted documents, and the
#'   outstanding ones are reported separately in `Pending`.
corpus_scope_stats <- function(country_body) {
  tidy <- corpus_series_frame(country_body)
  if (nrow(tidy) == 0) return(tibble::tibble())

  read  <- dplyr::filter(tidy, n_pages > 0)
  if (nrow(read) == 0) return(tibble::tibble())

  pending <- tidy |>
    dplyr::filter(n_pages == 0 | is.na(n_pages)) |>
    dplyr::count(Series, Language, name = "Pending")

  per_series <- read |>
    dplyr::group_by(Series, Language) |>
    dplyr::summarise(
      Documents   = dplyr::n(),
      Pages       = sum(n_pages, na.rm = TRUE),
      `Year span` = sprintf("%d–%d", min(year, na.rm = TRUE), max(year, na.rm = TRUE)),
      .groups = "drop"
    ) |>
    dplyr::left_join(pending, by = c("Series", "Language")) |>
    dplyr::mutate(Pending = tidyr::replace_na(Pending, 0L)) |>
    dplyr::arrange(Series, Language) |>
    dplyr::relocate(Pending, .after = Documents)

  dplyr::bind_rows(
    per_series,
    tibble::tibble(
      Series      = "All series",
      Language    = "—",
      Documents   = nrow(read),
      Pending     = nrow(tidy) - nrow(read),
      Pages       = sum(read$n_pages, na.rm = TRUE),
      `Year span` = sprintf("%d–%d", min(read$year, na.rm = TRUE),
                            max(read$year, na.rm = TRUE))
    )
  )
}
