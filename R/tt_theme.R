#' Project tinytable theme
#'
#' Applies booktabs-style formatting: centered, no row lines,
#' header separator and bottom rule only.
#'
#' @param tt_tbl A tinytable object.
#' @param breakable Allow the table to split across pages. Typst floats are
#'   unbreakable by default, so a table longer than a page runs off the bottom
#'   silently. `theme_tt("multipage")` emits the `breakable: true` show rule
#'   that fixes it, and is inert for short tables and for HTML.
#' @return A styled tinytable object.
tt_theme_report <- function(tt_tbl, breakable = TRUE) {
  n_col <- ncol(tt_tbl)
  n_row <- nrow(tt_tbl)
  if (breakable) tt_tbl <- tinytable::theme_tt(tt_tbl, "multipage")
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
