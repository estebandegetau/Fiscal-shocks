#' Project tinytable theme
#'
#' Applies booktabs-style formatting: centered, no row lines,
#' header separator and bottom rule only.
#'
#' @param tt_tbl A tinytable object.
#' @return A styled tinytable object.
tt_theme_report <- function(tt_tbl) {
  n_col <- ncol(tt_tbl)
  n_row <- nrow(tt_tbl)
  tt_tbl |>
    # Start from a borderless base so no interior row rules survive (matters in
    # Typst/PDF, where the default draws per-row borders). Then add only the
    # three booktabs rules below. theme_empty() is tinytable's non-deprecated
    # replacement for the old theme_tt("void").
    tinytable::theme_empty() |>
    tinytable::style_tt(i = 0, line = "tb", line_width = 0.1) |>
    tinytable::style_tt(i = n_row, line = "b", line_width = 0.1) |>
    tinytable::style_tt(j = 1:n_col, align = "c")
}
