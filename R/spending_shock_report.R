# Reporting helpers for the government spending-shock deliverable.
#
# Spending-side analogue of R/tax_shock_report.R, sharing the same rendering
# layer for the reviewer-facing dataset page (notebooks/malaysia_dataset.qmd):
# a clean external inventory table, a diverging-bar timeline, a flat
# variable-labelled export (and its multi-format writer for a file target), and
# a Romer & Romer (2010, p. 772) "Exhibit"-style act write-up.
#
# Spending shocks share the downstream C2b columns of tax shocks but carry no
# statutory rate: rate_from/rate_to/delta_pp are NA, the instrument is always
# "Expenditure", `spending_category` (Das component families) replaces
# `tax_type`, `direction` is {Increase, Decrease, Neutral}, and `magnitude_note`
# (free text, e.g. "RM60 bn") is the primary magnitude. So there is no rate-path
# figure analogue, and the rate column / rate line are dropped.
#
# Reuses pretty_motivation() + the motivation palette/labels from
# R/malay_consistency.R, tt_theme_report() from R/tt_theme.R, and the generic
# internal helpers `.tax_signed_effect()`, `.tax_truthy()`, `.tax_sources_md()`,
# `.tax_shock_theme()` from R/tax_shock_report.R (not tax-specific in logic).

# ---- Spending-category pretty labels ---------------------------------------

.spending_category_labels <- c(
  INFRASTRUCTURE_INVESTMENT = "Infrastructure investment",
  SOCIAL_TRANSFERS          = "Social transfers",
  SUBSIDIES                 = "Subsidies",
  PUBLIC_WAGES              = "Public wages",
  CONSOLIDATION_RESTRAINT   = "Consolidation / restraint",
  OTHER                     = "Other"
)

#' Human-readable spending category from the Das-family enum
#' @param x Character vector of `spending_category` values.
#' @return Character vector of pretty labels (unmapped values passed through).
#' @export
pretty_spending_category <- function(x) {
  out <- .spending_category_labels[as.character(x)]
  out[is.na(out)] <- as.character(x)[is.na(out)]
  unname(out)
}

# Compact a long free-text magnitude note for a table cell.
.spending_truncate <- function(x, n = 48L) {
  x <- as.character(x)
  ifelse(is.na(x) | nchar(x) <= n, x, paste0(substr(x, 1L, n - 1L), "…"))
}

# ---- Clean inventory table (external reader) -------------------------------

#' Government spending-shock inventory as a styled tinytable
#'
#' Trimmed for an external audience: one row per shock, the act, its effective
#' year, and the C2b exogeneity verdict. Category, direction, magnitude,
#' motivation, the shock id, and the preliminary narrative read are
#' intentionally omitted here (they live in the exhibit and the internal
#' provenance notebook).
#'
#' @param spending_shocks The `spending_shocks` deliverable tibble.
#' @return A tinytable, or NULL if `spending_shocks` is empty.
#' @export
spending_inventory_table <- function(spending_shocks) {
  if (nrow(spending_shocks) == 0L) return(NULL)
  spending_shocks |>
    dplyr::arrange(effective_year) |>
    dplyr::transmute(
      Act       = act_label,
      Effective = effective_year,
      Exogenous = as.character(pretty_exogenous(c2b_exogenous))
    ) |>
    tinytable::tt() |>
    tt_theme_report()
}

# ---- Headline figure -------------------------------------------------------

#' Spending-shock timeline as signed exogeneity counts
#'
#' Acts counted per year × exogeneity × direction as a diverging stacked bar:
#' spending increases grow the bar upward, decreases downward, neutral acts sit
#' at the baseline. Colour = C2b exogenous/endogenous classification. A single
#' panel (unlike the tax timeline's per-instrument facets): the spending-category
#' mix is dominated by one family, so faceting would be lopsided.
#'
#' @param spending_shocks The `spending_shocks` deliverable tibble.
#' @return A ggplot, or NULL if no shocks carry a year.
#' @export
plot_spending_timeline <- function(spending_shocks) {
  if (nrow(spending_shocks) == 0L) return(NULL)
  tl <- spending_shocks |>
    dplyr::filter(!is.na(effective_year)) |>
    dplyr::mutate(
      sign = dplyr::case_when(direction == "Increase" ~ "+",
                              direction == "Decrease" ~ "-",
                              TRUE                     ~ "0"),
      exogeneity = pretty_exogenous(c2b_exogenous)
    ) |>
    dplyr::count(effective_year, sign, exogeneity, name = "n") |>
    dplyr::mutate(signed_n = dplyr::if_else(sign == "-", -n, n))
  if (nrow(tl) == 0L) return(NULL)

  ggplot2::ggplot(tl, ggplot2::aes(effective_year, signed_n, fill = exogeneity)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
    ggplot2::scale_x_continuous(breaks = scales::breaks_width(5)) +
    ggplot2::scale_fill_manual(values = .exo_palette, name = "Exogeneity",
                               na.value = "grey70", drop = FALSE) +
    ggplot2::labs(x = NULL, y = "Acts (increase ↑ / decrease ↓)") +
    .tax_shock_theme()
}

# ---- Clean export (flat, variable-labelled) --------------------------------

# Column -> (label, definition). Single source of truth for the export schema,
# the variable labels carried into the .dta, and the on-page data dictionary.
.spending_export_dict <- tibble::tribble(
  ~variable,          ~label,                                        ~definition,
  "shock_id",         "Shock identifier",                            "Unique ID, one per announced spending act (e.g. MY-SPEND-04).",
  "act_label",        "Act / package name",                          "Human-readable name of the spending act, package, or policy change.",
  "spending_category","Spending category",                           "Das component family: Infrastructure investment, Social transfers, Subsidies, Public wages, Consolidation/restraint, or Other.",
  "direction",        "Direction of change",                         "Increase (expansionary), Decrease (contractionary), or Neutral.",
  "magnitude_note",   "Magnitude (free text)",                       "Headline magnitude in RM or percent terms (e.g. RM60 bn); spending has no statutory rate.",
  "announced_year",   "Announcement year",                           "Year the act / package was announced.",
  "effective_year",   "Effective year",                              "Year the spending change took effect.",
  "effective_quarter","Effective quarter",                           "Effective quarter (e.g. 2020Q1) where known; NA when only year is known.",
  "motivation",       "Motivation (C2b)",                            "Validated C2b motivation: Spending-driven, Countercyclical, Deficit-driven, or Long-run.",
  "exogenous",        "Exogenous (C2b)",                             "C2b exogenous/endogenous classification (TRUE = exogenous). Preliminary input pending expert adjudication."
)

#' Flat, variable-labelled spending export tibble
#'
#' One row per shock with the locked external column set (no list-cols, no
#' preliminary exogeneity, no NA rate fields). Variable labels from
#' `.spending_export_dict` are attached via labelled::set_variable_labels() so
#' they carry into the .dta export.
#'
#' @param spending_shocks The `spending_shocks` deliverable tibble.
#' @return A labelled tibble.
#' @export
clean_spending_shocks_export <- function(spending_shocks) {
  clean <- spending_shocks |>
    dplyr::arrange(effective_year) |>
    dplyr::transmute(
      shock_id, act_label,
      spending_category = pretty_spending_category(spending_category),
      direction, magnitude_note,
      announced_year, effective_year, effective_quarter,
      motivation = as.character(pretty_motivation(c2b_label)),
      exogenous  = c2b_exogenous
    )
  labs <- stats::setNames(as.list(.spending_export_dict$label), .spending_export_dict$variable)
  labelled::set_variable_labels(clean, !!!labs)
}

#' The on-page spending data dictionary table
#' @return A styled tinytable mapping variable -> label -> definition.
#' @export
spending_export_dictionary_table <- function() {
  .spending_export_dict |>
    dplyr::rename(Variable = variable, Label = label, Definition = definition) |>
    tinytable::tt() |>
    tt_theme_report()
}

#' Write the clean spending dataset in CSV, XLSX (data + dictionary) and DTA
#'
#' Command behind the `spending_shocks_clean_files` file target. Writes the
#' three files and returns their paths (project file-target convention).
#' Empty-input safe: still writes the (0-row) files so the target and download
#' links exist.
#'
#' @param spending_shocks The `spending_shocks` deliverable tibble.
#' @param dir Output directory (default data/validated).
#' @param stem File stem (default MY_spending_shocks_clean).
#' @return Character vector of the three written paths (csv, xlsx, dta).
#' @export
write_spending_shocks_exports <- function(spending_shocks,
                                          dir = here::here("data", "validated"),
                                          stem = "MY_spending_shocks_clean") {
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  clean <- clean_spending_shocks_export(spending_shocks)

  csv_path  <- file.path(dir, paste0(stem, ".csv"))
  xlsx_path <- file.path(dir, paste0(stem, ".xlsx"))
  dta_path  <- file.path(dir, paste0(stem, ".dta"))

  readr::write_csv(clean, csv_path)
  writexl::write_xlsx(
    list(data = clean, dictionary = .spending_export_dict),
    path = xlsx_path
  )
  haven::write_dta(clean, dta_path)

  c(csv_path, xlsx_path, dta_path)
}

# ---- R&R-style "Exhibit" write-up ------------------------------------------

#' Render one spending shock as a Romer & Romer (2010, p. 772)-style Exhibit
#'
#' Emits an asis markdown callout: a boxed header (act, category, dates,
#' direction + magnitude, C2b classification, signed effect), the
#' identification + motivation narrative, the diagnostic exogeneity quote as a
#' blockquote, a flag where the preliminary narrative read differs from C2b, and
#' clickable source links. Mirrors `tax_exhibit()` (reusing its generic internal
#' helpers); the rate line is replaced by a direction + magnitude line and the
#' "Tax" header field by "Category". Call inside a chunk with `#| output: asis`.
#'
#' @param spending_shocks The `spending_shocks` deliverable tibble.
#' @param shock_id The shock to render.
#' @param exhibit_label Optional prefix, e.g. "Exhibit 3".
#' @param note Optional extra markdown appended after the narrative.
#' @return Invisibly NULL; writes markdown to the output via cat().
#' @export
spending_exhibit <- function(spending_shocks, shock_id, exhibit_label = NULL, note = NULL) {
  row <- spending_shocks[spending_shocks$shock_id == shock_id, ]
  if (nrow(row) == 0L) {
    cat(sprintf("_Shock %s not found._\n\n", shock_id)); return(invisible(NULL))
  }
  row <- row[1, ]

  exo_lab <- if (isTRUE(row$c2b_exogenous)) "Exogenous" else "Endogenous"
  motiv   <- as.character(pretty_motivation(row$c2b_label))
  cat_lab <- pretty_spending_category(row$spending_category)
  title   <- if (is.null(exhibit_label)) row$act_label
             else sprintf("%s — %s", exhibit_label, row$act_label)

  change_line <- sprintf("%s%s", row$direction,
    if (!is.na(row$magnitude_note) && nzchar(row$magnitude_note))
      paste0(" — ", row$magnitude_note) else "")

  prelim_exo <- row$exogenous_preliminary
  prelim_line <- if (is.na(prelim_exo) || !nzchar(prelim_exo)) {
    NULL
  } else {
    prelim_truthy <- .tax_truthy(prelim_exo)
    differs <- !is.na(row$c2b_exogenous) &&
      prelim_exo %in% c("TRUE", "true", "FALSE", "false") &&
      (prelim_truthy != isTRUE(row$c2b_exogenous))
    prelim_word <- if (tolower(as.character(prelim_exo)) %in% c("ambiguous", "mixed"))
      "ambiguous" else if (prelim_truthy) "exogenous" else "endogenous"
    sprintf(
      "*Preliminary narrative read (Das screen):* %s%s",
      prelim_word,
      if (differs) " — **differs from the C2b verdict; this is exactly the kind of call an expert must adjudicate.**"
      else if (prelim_word == "ambiguous") " — left for expert adjudication."
      else " (consistent with C2b)."
    )
  }

  out <- c(
    sprintf("::: {.callout-note appearance=\"default\" icon=\"false\"}"),
    sprintf("## %s {.unnumbered}", title),
    "",
    sprintf("**Shock ID:** %s &nbsp;|&nbsp; **Category:** %s &nbsp;|&nbsp; **Announced:** %s &nbsp;|&nbsp; **Effective:** %s  ",
            row$shock_id, cat_lab, row$announced_year,
            ifelse(is.na(row$effective_quarter), as.character(row$effective_year), row$effective_quarter)),
    sprintf("**Change:** %s  ", change_line),
    sprintf("**Classification (C2b):** %s — %s  ", exo_lab, motiv),
    sprintf("**Signed effect (C2b):** %s", .tax_signed_effect(row)),
    "",
    sprintf("*Identification.* %s", row$id_reasoning),
    "",
    sprintf("*Motivation (C2b).* %s", row$c2b_reasoning),
    ""
  )
  if (!is.na(row$exogeneity_quote) && nzchar(row$exogeneity_quote)) {
    out <- c(out, sprintf("> %s", row$exogeneity_quote), "")
  }
  if (!is.null(prelim_line)) out <- c(out, prelim_line, "")
  if (!is.null(note)) out <- c(out, note, "")
  out <- c(out,
           sprintf("**Sources:** %s", .tax_sources_md(row$sources[[1]])),
           ":::", "", "")

  cat(paste(out, collapse = "\n"))
  invisible(NULL)
}
