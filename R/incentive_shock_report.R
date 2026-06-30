# Reporting helpers for the tax-incentive / holiday shock deliverable.
#
# Incentive-side analogue of R/tax_shock_report.R and R/spending_shock_report.R,
# sharing the same rendering layer for the reviewer-facing dataset page
# (notebooks/malaysia_dataset.qmd): a clean external inventory table, a
# diverging-bar timeline, a flat variable-labelled export (and its multi-format
# writer for a file target), and a Romer & Romer (2010, p. 772) "Exhibit"-style
# act write-up.
#
# Incentives are a HYBRID of the tax and spending cases: they carry the downstream
# C2b columns of tax shocks, the `direction` enum {Cut, Hike, Neutral} of tax
# shocks, AND -- unlike spending -- meaningful statutory rate fields for
# concessionary-rate cases (rate_from/rate_to/delta_pp populated for
# PREFERENTIAL_RATE, NA for holidays/allowances/credits). `incentive_category` (the
# Klemm & Van Parys mechanism families) replaces `tax_type` as the typology, while
# `tax_type` carries the underlying base (CIT/PIT/CONSUMPTION/NA), and
# `magnitude_note` (free text, e.g. "5-year holiday", "60% ITA") is the primary
# magnitude for non-rate incentives.
#
# Reuses pretty_motivation() + the motivation palette/labels from
# R/malay_consistency.R, tt_theme_report() from R/tt_theme.R, and the generic
# internal helpers `pretty_exogenous()`, `.exo_palette`, `.tax_signed_effect()`,
# `.tax_truthy()`, `.tax_sources_md()`, `.tax_shock_theme()` from
# R/tax_shock_report.R (not tax-specific in logic).

# ---- Incentive-category pretty labels --------------------------------------

.incentive_category_labels <- c(
  TAX_HOLIDAY          = "Tax holiday",
  INVESTMENT_ALLOWANCE = "Investment allowance",
  PREFERENTIAL_RATE    = "Preferential rate",
  ZONE                 = "Zone incentive",
  SECTORAL_RD          = "Sectoral / R&D",
  OTHER                = "Other"
)

#' Human-readable incentive category from the K&VP mechanism enum
#' @param x Character vector of `incentive_category` values.
#' @return Character vector of pretty labels (unmapped values passed through).
#' @export
pretty_incentive_category <- function(x) {
  out <- .incentive_category_labels[as.character(x)]
  out[is.na(out)] <- as.character(x)[is.na(out)]
  unname(out)
}

# ---- Clean inventory table (external reader) -------------------------------

#' Tax-incentive shock inventory as a styled tinytable
#'
#' Trimmed for an external audience: one row per shock, the act, its mechanism
#' category, the underlying tax base, its effective year, and the C2b exogeneity
#' verdict. Direction, rate detail, magnitude, motivation, the shock id, and the
#' preliminary narrative read are intentionally omitted here (they live in the
#' exhibit and the internal provenance notebook).
#'
#' @param incentive_shocks The `incentive_shocks` deliverable tibble.
#' @return A tinytable, or NULL if `incentive_shocks` is empty.
#' @export
incentive_inventory_table <- function(incentive_shocks) {
  if (nrow(incentive_shocks) == 0L) return(NULL)
  incentive_shocks |>
    dplyr::arrange(effective_year) |>
    dplyr::transmute(
      Act       = act_label,
      Category  = pretty_incentive_category(incentive_category),
      Base      = tax_type,
      Effective = effective_year,
      Exogenous = as.character(pretty_exogenous(c2b_exogenous))
    ) |>
    tinytable::tt() |>
    tt_theme_report()
}

# ---- Headline figure -------------------------------------------------------

#' Tax-incentive timeline as signed exogeneity counts
#'
#' Acts counted per year × exogeneity × direction as a diverging stacked bar:
#' new / expanded incentives (a `Cut` in the effective burden) grow the bar
#' downward, repeals / scale-backs (a `Hike`) upward, neutral acts sit at the
#' baseline. The sign convention matches the tax timeline (Hike +, Cut −). Colour
#' = C2b exogenous/endogenous classification. A single panel (unlike the tax
#' timeline's per-instrument facets): incentives are dominated by one base.
#'
#' @param incentive_shocks The `incentive_shocks` deliverable tibble.
#' @return A ggplot, or NULL if no shocks carry a year.
#' @export
plot_incentive_timeline <- function(incentive_shocks) {
  if (nrow(incentive_shocks) == 0L) return(NULL)
  tl <- incentive_shocks |>
    dplyr::filter(!is.na(effective_year)) |>
    dplyr::mutate(
      sign = dplyr::case_when(direction == "Hike" ~ "+",
                              direction == "Cut"  ~ "-",
                              TRUE                 ~ "0"),
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
    ggplot2::labs(x = NULL, y = "Acts (new/expanded ↓ / repealed ↑)") +
    .tax_shock_theme()
}

# ---- Clean export (flat, variable-labelled) --------------------------------

# Column -> (label, definition). Single source of truth for the export schema,
# the variable labels carried into the .dta, and the on-page data dictionary.
.incentive_export_dict <- tibble::tribble(
  ~variable,           ~label,                                       ~definition,
  "shock_id",          "Shock identifier",                           "Unique ID, one per announced incentive change (e.g. MY-INCENT-03).",
  "act_label",         "Act / measure name",                         "Human-readable name of the incentive scheme, change, or budget measure.",
  "tax_type",          "Underlying tax base",                        "Tax base the incentive sits on: CIT, PIT, CONSUMPTION, or NA.",
  "incentive_category","Incentive category",                         "Mechanism family: Tax holiday, Investment allowance, Preferential rate, Zone incentive, Sectoral/R&D, or Other.",
  "direction",         "Direction of change",                        "Cut (new/expanded incentive, lowers effective burden), Hike (repeal/scale-back), or Neutral.",
  "rate_from",         "Concessionary rate before (%)",              "Rate prior to the change for preferential-rate incentives; NA for non-rate incentives.",
  "rate_to",           "Concessionary rate after (%)",               "Rate after the change for preferential-rate incentives; NA for non-rate incentives.",
  "delta_pp",          "Rate change (pp)",                           "rate_to minus rate_from, in percentage points; NA for non-rate incentives.",
  "magnitude_note",    "Magnitude (free text)",                      "Non-rate magnitude: holiday duration, allowance rate, revenue estimate, or scope (e.g. '5-year holiday', '60% ITA').",
  "announced_year",    "Announcement year",                          "Year the change was announced (budget / statute year).",
  "effective_year",    "Effective year",                             "Year the change took effect / year of assessment.",
  "effective_quarter", "Effective quarter",                          "Effective quarter (e.g. 2019Q1) where known; NA when only year is known.",
  "motivation",        "Motivation (C2b)",                           "Validated C2b motivation: Spending-driven, Countercyclical, Deficit-driven, or Long-run.",
  "exogenous",         "Exogenous (C2b)",                            "C2b exogenous/endogenous classification (TRUE = exogenous). Preliminary input pending expert adjudication."
)

#' Flat, variable-labelled incentive export tibble
#'
#' One row per shock with the locked external column set (no list-cols, no
#' preliminary exogeneity). Variable labels from `.incentive_export_dict` are
#' attached via labelled::set_variable_labels() so they carry into the .dta export.
#'
#' @param incentive_shocks The `incentive_shocks` deliverable tibble.
#' @return A labelled tibble.
#' @export
clean_incentive_shocks_export <- function(incentive_shocks) {
  clean <- incentive_shocks |>
    dplyr::arrange(effective_year) |>
    dplyr::transmute(
      shock_id, act_label, tax_type,
      incentive_category = pretty_incentive_category(incentive_category),
      direction, rate_from, rate_to, delta_pp, magnitude_note,
      announced_year, effective_year, effective_quarter,
      motivation = as.character(pretty_motivation(c2b_label)),
      exogenous  = c2b_exogenous
    )
  labs <- stats::setNames(as.list(.incentive_export_dict$label), .incentive_export_dict$variable)
  labelled::set_variable_labels(clean, !!!labs)
}

#' The on-page incentive data dictionary table
#' @return A styled tinytable mapping variable -> label -> definition.
#' @export
incentive_export_dictionary_table <- function() {
  .incentive_export_dict |>
    dplyr::rename(Variable = variable, Label = label, Definition = definition) |>
    tinytable::tt() |>
    tt_theme_report()
}

#' Write the clean incentive dataset in CSV, XLSX (data + dictionary) and DTA
#'
#' Command behind the `incentive_shocks_clean_files` file target. Writes the three
#' files and returns their paths (project file-target convention). Empty-input
#' safe: still writes the (0-row) files so the target and download links exist.
#'
#' @param incentive_shocks The `incentive_shocks` deliverable tibble.
#' @param dir Output directory (default data/validated).
#' @param stem File stem (default MY_incentive_shocks_clean).
#' @return Character vector of the three written paths (csv, xlsx, dta).
#' @export
write_incentive_shocks_exports <- function(incentive_shocks,
                                           dir = here::here("data", "validated"),
                                           stem = "MY_incentive_shocks_clean") {
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  clean <- clean_incentive_shocks_export(incentive_shocks)

  csv_path  <- file.path(dir, paste0(stem, ".csv"))
  xlsx_path <- file.path(dir, paste0(stem, ".xlsx"))
  dta_path  <- file.path(dir, paste0(stem, ".dta"))

  readr::write_csv(clean, csv_path)
  writexl::write_xlsx(
    list(data = clean, dictionary = .incentive_export_dict),
    path = xlsx_path
  )
  haven::write_dta(clean, dta_path)

  c(csv_path, xlsx_path, dta_path)
}

# ---- R&R-style "Exhibit" write-up ------------------------------------------

#' Render one incentive shock as a Romer & Romer (2010, p. 772)-style Exhibit
#'
#' Emits an asis markdown callout: a boxed header (act, base, category, dates,
#' rate-or-magnitude change, C2b classification, signed effect), the
#' identification + motivation narrative, the diagnostic exogeneity quote as a
#' blockquote, a flag where the preliminary narrative read differs from C2b, and
#' clickable source links. Mirrors `tax_exhibit()` (reusing its generic internal
#' helpers): keeps the rate-aware change line for preferential-rate incentives and
#' adds a "Category" header field. Call inside a chunk with `#| output: asis`.
#'
#' @param incentive_shocks The `incentive_shocks` deliverable tibble.
#' @param shock_id The shock to render.
#' @param exhibit_label Optional prefix, e.g. "Exhibit 4".
#' @param note Optional extra markdown appended after the narrative.
#' @return Invisibly NULL; writes markdown to the output via cat().
#' @export
incentive_exhibit <- function(incentive_shocks, shock_id, exhibit_label = NULL, note = NULL) {
  row <- incentive_shocks[incentive_shocks$shock_id == shock_id, ]
  if (nrow(row) == 0L) {
    cat(sprintf("_Shock %s not found._\n\n", shock_id)); return(invisible(NULL))
  }
  row <- row[1, ]

  exo_lab <- if (isTRUE(row$c2b_exogenous)) "Exogenous" else "Endogenous"
  motiv   <- as.character(pretty_motivation(row$c2b_label))
  cat_lab <- pretty_incentive_category(row$incentive_category)
  base    <- ifelse(is.na(row$tax_type), "—", row$tax_type)
  title   <- if (is.null(exhibit_label)) row$act_label
             else sprintf("%s — %s", exhibit_label, row$act_label)

  change_line <- if (!is.na(row$rate_from) && !is.na(row$rate_to)) {
    sprintf("%g%% → %g%% (%s pp; %s)",
            row$rate_from, row$rate_to,
            ifelse(is.na(row$delta_pp), "—", sprintf("%+g", row$delta_pp)),
            row$direction)
  } else {
    sprintf("Non-rate incentive (%s)%s", row$direction,
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
    prelim_word <- if (tolower(as.character(prelim_exo)) %in% c("ambiguous", "mixed"))
      "ambiguous" else if (prelim_truthy) "exogenous" else "endogenous"
    sprintf(
      "*Preliminary narrative read:* %s%s",
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
    sprintf("**Shock ID:** %s &nbsp;|&nbsp; **Base:** %s &nbsp;|&nbsp; **Category:** %s &nbsp;|&nbsp; **Announced:** %s &nbsp;|&nbsp; **Effective:** %s  ",
            row$shock_id, base, cat_lab, row$announced_year,
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
