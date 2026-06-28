# Reporting helpers for the statutory tax-change deliverable.
#
# Shared rendering layer for the reviewer-facing dataset page
# (notebooks/malaysia_dataset.qmd) and, optionally, the internal
# notebooks/tax_shocks.qmd. Pure helpers: build a clean external inventory
# table, the two headline figures (rate paths + diverging-bar timeline), a
# flat variable-labelled export (and its multi-format writer for a file
# target), and Romer & Romer (2010, p. 772) "Exhibit"-style act write-ups.
#
# Reuses pretty_motivation() + the motivation palette/labels from
# R/malay_consistency.R and tt_theme_report() from R/tt_theme.R. The export
# writer is the command behind the `tax_shocks_clean_files` file target; it
# writes the files and returns their paths (project file-target convention).

# ---- Clean inventory table (external reader) -------------------------------

#' Statutory tax-change inventory as a styled tinytable
#'
#' Trimmed for an external audience: one row per shock, the headline analytic
#' columns plus the C2b motivation + exogeneity verdict. The preliminary
#' narrative read is intentionally omitted here (it lives in the exhibits and
#' the internal notebook).
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @return A tinytable, or NULL if `tax_shocks` is empty.
#' @export
tax_inventory_table <- function(tax_shocks) {
  if (nrow(tax_shocks) == 0L) return(NULL)
  tax_shocks |>
    dplyr::arrange(tax_type, effective_year) |>
    dplyr::transmute(
      Shock        = shock_id,
      Act          = act_label,
      Tax          = tax_type,
      Direction    = direction,
      `Δpp`        = delta_pp,
      Effective    = effective_year,
      Motivation   = as.character(pretty_motivation(c2b_label)),
      `Exogenous (C2b)` = c2b_exogenous
    ) |>
    tinytable::tt() |>
    tt_theme_report()
}

# ---- Headline figures ------------------------------------------------------

.tax_shock_theme <- function() {
  ggplot2::theme_minimal(base_family = "Libertinus Serif", base_size = 10) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
}

#' Statutory rate paths by tax type
#'
#' Step path of the headline statutory rate implied by the rate-bearing shocks,
#' faceted by tax type. Non-rate shocks (one-off levies, regime introductions
#' without a standing rate) are dropped.
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @return A ggplot, or NULL if there are no rate-bearing shocks.
#' @export
plot_tax_rate_paths <- function(tax_shocks) {
  if (nrow(tax_shocks) == 0L) return(NULL)
  rate_path <- tax_shocks |>
    dplyr::filter(!is.na(rate_to), !is.na(effective_year)) |>
    dplyr::arrange(tax_type, effective_year)
  if (nrow(rate_path) == 0L) return(NULL)

  ggplot2::ggplot(rate_path, ggplot2::aes(effective_year, rate_to)) +
    ggplot2::geom_step(direction = "hv", linewidth = 0.8, colour = "grey20") +
    ggplot2::geom_point(size = 2) +
    ggplot2::facet_wrap(~ tax_type, ncol = 1, scales = "free_y") +
    ggplot2::scale_y_continuous(labels = scales::label_percent(scale = 1)) +
    ggplot2::scale_x_continuous(breaks = scales::breaks_width(5)) +
    ggplot2::labs(x = NULL, y = "Statutory rate") +
    .tax_shock_theme()
}

#' Tax-change timeline as signed motivation counts, faceted by tax type
#'
#' Acts counted per year × tax type × motivation × direction as a diverging
#' stacked bar: hikes grow the bar upward, cuts downward, neutral acts sit at
#' the baseline. Colour = C2b motivation. Reuses `pretty_motivation()` and the
#' shared motivation palette.
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @return A ggplot, or NULL if no shocks carry a year.
#' @export
plot_tax_timeline <- function(tax_shocks) {
  if (nrow(tax_shocks) == 0L) return(NULL)
  tl <- tax_shocks |>
    dplyr::filter(!is.na(effective_year)) |>
    dplyr::mutate(
      sign = dplyr::case_when(direction == "Hike" ~ "+",
                              direction == "Cut"  ~ "-",
                              TRUE                 ~ "0"),
      motivation = dplyr::if_else(sign == "0", "No change",
                                  as.character(pretty_motivation(c2b_label)))
    ) |>
    dplyr::count(tax_type, effective_year, sign, motivation, name = "n") |>
    dplyr::mutate(
      signed_n   = dplyr::if_else(sign == "-", -n, n),
      motivation = factor(motivation,
                          levels = c(unname(.malay_motivation_labels), "No change"))
    )
  if (nrow(tl) == 0L) return(NULL)

  ggplot2::ggplot(tl, ggplot2::aes(effective_year, signed_n, fill = motivation)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
    ggplot2::scale_x_continuous(breaks = scales::breaks_width(5)) +
    ggplot2::scale_fill_manual(values = .malay_motivation_palette, name = "Motivation",
                               drop = FALSE) +
    ggplot2::facet_wrap(~ tax_type, ncol = 1) +
    ggplot2::labs(x = NULL, y = "Acts (hike ↑ / cut ↓)") +
    .tax_shock_theme()
}

# ---- Clean export (flat, variable-labelled) --------------------------------

# Column -> (label, definition). Single source of truth for the export schema,
# the variable labels carried into the .dta, and the on-page data dictionary.
.tax_export_dict <- tibble::tribble(
  ~variable,          ~label,                                        ~definition,
  "shock_id",         "Shock identifier",                            "Unique ID, one per announced act x tax type (e.g. MY-CIT-03).",
  "act_label",        "Act / event name",                            "Human-readable name of the announced act or budget measure.",
  "tax_type",         "Tax instrument",                              "CIT (corporate income), PIT (personal income), or CONSUMPTION (VAT/GST/SST).",
  "direction",        "Direction of change",                         "Cut, Hike, or Neutral; consistent with the sign of delta_pp.",
  "rate_from",        "Statutory rate before (%)",                   "Headline statutory rate prior to the change; NA if not a rate change.",
  "rate_to",          "Statutory rate after (%)",                    "Headline statutory rate after the change; NA if not a rate change.",
  "delta_pp",         "Rate change (pp)",                            "rate_to minus rate_from, in percentage points; NA if non-rate.",
  "announced_year",   "Announcement year",                           "Year the act was announced (budget year).",
  "effective_year",   "Effective year",                              "Year of assessment / year the change took effect.",
  "effective_quarter","Effective quarter",                           "Effective quarter (e.g. 2016Q1) where known; NA when only year is known.",
  "motivation",       "Motivation (C2b)",                            "Validated C2b motivation: Spending-driven, Countercyclical, Deficit-driven, or Long-run.",
  "exogenous",        "Exogenous (C2b)",                             "C2b exogenous/endogenous classification (TRUE = exogenous). Preliminary input pending expert adjudication."
)

#' Flat, variable-labelled export tibble
#'
#' One row per shock with the locked external column set (no list-cols, no
#' preliminary exogeneity). Variable labels from `.tax_export_dict` are attached
#' via labelled::set_variable_labels() so they carry into the .dta export.
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @return A labelled tibble.
#' @export
clean_tax_shocks_export <- function(tax_shocks) {
  clean <- tax_shocks |>
    dplyr::arrange(tax_type, effective_year) |>
    dplyr::transmute(
      shock_id, act_label, tax_type, direction,
      rate_from, rate_to, delta_pp,
      announced_year, effective_year, effective_quarter,
      motivation = as.character(pretty_motivation(c2b_label)),
      exogenous  = c2b_exogenous
    )
  labs <- stats::setNames(as.list(.tax_export_dict$label), .tax_export_dict$variable)
  labelled::set_variable_labels(clean, !!!labs)
}

#' The on-page data dictionary table
#' @return A styled tinytable mapping variable -> label -> definition.
#' @export
tax_export_dictionary_table <- function() {
  .tax_export_dict |>
    dplyr::rename(Variable = variable, Label = label, Definition = definition) |>
    tinytable::tt() |>
    tt_theme_report()
}

#' Write the clean dataset in CSV, XLSX (data + dictionary sheets) and DTA
#'
#' Command behind the `tax_shocks_clean_files` file target. Writes the three
#' files and returns their paths (project file-target convention). Empty-input
#' safe: still writes the (0-row) files so the target and download links exist.
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @param dir Output directory (default data/validated).
#' @param stem File stem (default MY_tax_shocks_clean).
#' @return Character vector of the three written paths (csv, xlsx, dta).
#' @export
write_tax_shocks_exports <- function(tax_shocks,
                                     dir = here::here("data", "validated"),
                                     stem = "MY_tax_shocks_clean") {
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  clean <- clean_tax_shocks_export(tax_shocks)

  csv_path  <- file.path(dir, paste0(stem, ".csv"))
  xlsx_path <- file.path(dir, paste0(stem, ".xlsx"))
  dta_path  <- file.path(dir, paste0(stem, ".dta"))

  readr::write_csv(clean, csv_path)
  writexl::write_xlsx(
    list(data = clean, dictionary = .tax_export_dict),
    path = xlsx_path
  )
  haven::write_dta(clean, dta_path)

  c(csv_path, xlsx_path, dta_path)
}

# ---- R&R-style "Exhibit" write-ups -----------------------------------------

# Render the signed-effect line. The sign enum is {+, -}; an out-of-enum model
# sign (e.g. "mixed" for an omnibus act) degrades to NA and is shown explicitly.
.tax_signed_effect <- function(row) {
  if (!is.na(row$c2b_sign) && row$c2b_sign == "+") return("increase (+)")
  if (!is.na(row$c2b_sign) && row$c2b_sign == "-") return("decrease (−)")
  raw <- row$c2b_sign_raw
  if (is.na(raw) || !nzchar(raw)) return("NA")
  sprintf("NA  *(no single sign; raw model output: “%s”)*", raw)
}

.tax_truthy <- function(x) {
  if (is.logical(x)) return(isTRUE(x))
  tolower(as.character(x)) %in% c("true", "t", "yes", "1")
}

.tax_sources_md <- function(sources) {
  if (is.null(sources) || nrow(sources) == 0L) return("_No source documents recorded._")
  links <- vapply(seq_len(nrow(sources)), function(i) {
    s <- sources[i, ]
    label <- sprintf("%s (%s, %s)", s$body, s$year, s$doc_language)
    if (is.na(s$pdf_url) || !nzchar(s$pdf_url)) label
    else sprintf("[%s](%s)", label, s$pdf_url)
  }, character(1))
  paste(links, collapse = "; ")
}

#' Render one shock as a Romer & Romer (2010, p. 772)-style Exhibit
#'
#' Emits an asis markdown callout: a boxed header (act, dates, rate change,
#' C2b classification, signed effect), the identification + motivation
#' narrative, the diagnostic exogeneity quote as a blockquote, a flag where the
#' preliminary narrative read differs from C2b, and clickable source links.
#' Call inside a chunk with `#| output: asis`.
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @param shock_id The shock to render.
#' @param exhibit_label Optional prefix, e.g. "Exhibit 1".
#' @param note Optional extra markdown appended after the narrative (used to
#'   explain the MY-CIT-03 NA sign).
#' @return Invisibly NULL; writes markdown to the output via cat().
#' @export
tax_exhibit <- function(tax_shocks, shock_id, exhibit_label = NULL, note = NULL) {
  row <- tax_shocks[tax_shocks$shock_id == shock_id, ]
  if (nrow(row) == 0L) {
    cat(sprintf("_Shock %s not found._\n\n", shock_id)); return(invisible(NULL))
  }
  row <- row[1, ]

  exo_lab <- if (isTRUE(row$c2b_exogenous)) "Exogenous" else "Endogenous"
  motiv   <- as.character(pretty_motivation(row$c2b_label))
  title   <- if (is.null(exhibit_label)) row$act_label
             else sprintf("%s — %s", exhibit_label, row$act_label)

  rate_line <- if (!is.na(row$rate_from) && !is.na(row$rate_to)) {
    sprintf("%g%% → %g%% (%s pp; %s)",
            row$rate_from, row$rate_to,
            ifelse(is.na(row$delta_pp), "—", sprintf("%+g", row$delta_pp)),
            row$direction)
  } else {
    sprintf("Non-rate change (%s)%s", row$direction,
            if (!is.na(row$magnitude_note) && nzchar(row$magnitude_note))
              paste0(" — ", row$magnitude_note) else "")
  }

  prelim_exo <- row$exogenous_preliminary
  prelim_line <- if (is.na(prelim_exo) || !nzchar(prelim_exo)) {
    NULL
  } else {
    prelim_truthy <- .tax_truthy(prelim_exo)
    differs <- !is.na(row$c2b_exogenous) &&
      prelim_exo %in% c("TRUE", "true", "FALSE", "false") &&
      (prelim_truthy != isTRUE(row$c2b_exogenous))
    sprintf(
      "*Preliminary narrative read:* %s%s",
      ifelse(prelim_truthy, "exogenous", "endogenous"),
      if (differs) " — **differs from the C2b verdict; this is exactly the kind of call an expert must adjudicate.**"
      else " (consistent with C2b)."
    )
  }

  out <- c(
    sprintf("::: {.callout-note appearance=\"default\" icon=\"false\"}"),
    sprintf("## %s {.unnumbered}", title),
    "",
    sprintf("**Shock ID:** %s &nbsp;|&nbsp; **Tax:** %s &nbsp;|&nbsp; **Announced:** %s &nbsp;|&nbsp; **Effective:** %s  ",
            row$shock_id, row$tax_type, row$announced_year,
            ifelse(is.na(row$effective_quarter), as.character(row$effective_year), row$effective_quarter)),
    sprintf("**Rate change:** %s  ", rate_line),
    sprintf("**Classification (C2b):** %s — %s  ", exo_lab, motiv),
    sprintf("**Signed effect on liabilities:** %s", .tax_signed_effect(row)),
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
