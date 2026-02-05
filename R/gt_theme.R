#' Project gt table theme
#'
#' Applies booktabs-style formatting: centered, no row lines,
#' header separator and bottom rule only.
#'
#' @param gt_tbl A gt table object.
#' @return A styled gt table object.
gt_theme_report <- function(gt_tbl) {
  gt_tbl %>%
    gt::opt_table_lines(extent = "none") %>%
    gt::tab_options(
      table.align = "center",
      column_labels.border.top.style = "solid",
      column_labels.border.top.width = gt::px(2),
      column_labels.border.bottom.style = "solid",
      column_labels.border.bottom.width = gt::px(2),
      table_body.border.bottom.style = "solid"
    )
}
