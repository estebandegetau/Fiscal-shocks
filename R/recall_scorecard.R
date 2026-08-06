# Recall scorecards from the frozen component datasets
#
# Precision can be checked against the dataset by anyone holding it; recall
# cannot. The `identify-*` skills therefore stamp every frozen dataset with an
# audit of what was searched, what was found, and what was missed and then
# recovered. These helpers surface that audit, which is otherwise buried in a
# list-column, as a manuscript exhibit.
#
# The scorecard is an instrument-level record repeated on every row of its
# dataset, so it is de-duplicated to one block per instrument here.

#' Normalise scorecard prose for table display
#'
#' Collapses whitespace and rewrites the characters that table cells carry
#' straight into Typst, where they are markup rather than text: `~` is a
#' non-breaking space there, so a literal "~10 clusters" renders as " 10
#' clusters" and silently changes the claim.
#'
#' @param x Character vector
#' @return Character vector
.scorecard_text <- function(x) {
  x <- gsub("~(?=\\d)", "approx. ", x, perl = TRUE)
  x <- gsub("~", " ", x, fixed = TRUE)
  trimws(gsub("\\s+", " ", x))
}

#' Extract the per-instrument recall scorecards
#'
#' @param tax,spending,incentive Deliverable tibbles. Any may be empty or NULL.
#' @return Tidy tibble: instrument, stage, outcome
recall_scorecards <- function(tax = NULL, spending = NULL, incentive = NULL) {
  pull_one <- function(x, instrument_col, fallback) {
    if (is.null(x) || nrow(x) == 0) return(NULL)
    if (!"recall_scorecard" %in% names(x)) return(NULL)

    instrument <- if (!is.null(instrument_col) && instrument_col %in% names(x)) {
      x[[instrument_col]]
    } else {
      rep(fallback, nrow(x))
    }

    tibble::tibble(instrument = instrument, sc = x$recall_scorecard) |>
      dplyr::filter(!vapply(sc, is.null, logical(1))) |>
      # One scorecard per instrument: every row of an instrument carries the
      # same audit, so the first is the record.
      dplyr::group_by(instrument) |>
      dplyr::slice(1) |>
      dplyr::ungroup() |>
      dplyr::mutate(rows = purrr::map(sc, tibble::as_tibble)) |>
      dplyr::select(instrument, rows) |>
      tidyr::unnest(rows)
  }

  out <- dplyr::bind_rows(
    pull_one(tax,       "tax_type",       "TAX"),
    pull_one(spending,  NULL,             "SPENDING"),
    pull_one(incentive, NULL,             "INCENTIVE")
  )

  if (is.null(out) || nrow(out) == 0) return(tibble::tibble())

  instrument_labels <- c(
    CIT         = "Corporate income tax",
    PIT         = "Personal income tax",
    CONSUMPTION = "Consumption tax (GST/SST)",
    SPENDING    = "Spending",
    INCENTIVE   = "Tax incentives"
  )

  out |>
    dplyr::transmute(
      Instrument = dplyr::coalesce(instrument_labels[instrument], instrument),
      Stage      = .scorecard_text(stage),
      Outcome    = .scorecard_text(outcome)
    ) |>
    dplyr::mutate(
      Instrument = factor(Instrument, levels = unname(instrument_labels))
    ) |>
    dplyr::arrange(Instrument)
}

#' Recall scorecard table for one instrument
#'
#' Emitted one instrument at a time. A single table over all five instruments
#' runs to 33 rows of wrapped prose, which overflows a page in the manuscript's
#' Typst layout without breaking across it.
#'
#' @param tax,spending,incentive Deliverable tibbles
#' @param instrument Instrument label to render, matching the `Instrument`
#'   column of `recall_scorecards()`. `NULL` renders every instrument in one
#'   table, with an Instrument column.
#' @param max_chars Truncate outcome text at this many characters (the full
#'   text lives in the frozen datasets and the provenance notebooks)
#' @return tinytable object, or NULL when no scorecard is available
recall_scorecard_table <- function(tax = NULL, spending = NULL,
                                   incentive = NULL, instrument = NULL,
                                   max_chars = 210L) {
  sc <- recall_scorecards(tax, spending, incentive)
  if (nrow(sc) == 0) return(NULL)

  if (!is.null(instrument)) {
    sc <- sc |> dplyr::filter(Instrument == instrument)
    if (nrow(sc) == 0) return(NULL)
  }

  sc <- sc |>
    dplyr::mutate(
      Outcome = dplyr::if_else(
        nchar(Outcome) > max_chars,
        paste0(substr(Outcome, 1, max_chars - 1), "…"),
        Outcome
      )
    )

  out <- if (is.null(instrument)) {
    sc |>
      dplyr::mutate(Instrument = as.character(Instrument)) |>
      tinytable::tt(width = c(0.18, 0.24, 0.58))
  } else {
    sc |>
      dplyr::select(Stage, Outcome) |>
      tinytable::tt(width = c(0.30, 0.70))
  }

  out |>
    tt_theme_report() |>
    tinytable::style_tt(j = 1:ncol(out), align = "l")
}

#' Instrument labels present in the frozen scorecards
#'
#' @param tax,spending,incentive Deliverable tibbles
#' @return Character vector of instrument labels, in reporting order
recall_scorecard_instruments <- function(tax = NULL, spending = NULL,
                                         incentive = NULL) {
  sc <- recall_scorecards(tax, spending, incentive)
  if (nrow(sc) == 0) return(character(0))
  levels(droplevels(sc$Instrument))
}
