#' C0 figure builders
#'
#' Pure functions that return ggplot objects for graduated C0 figures.
#' Each takes a single tidy data frame and returns a ggplot; captions and
#' labels are owned by the consuming chunk (notebook or index.qmd).

#' Surface-form variance per gold act
#'
#' Distinct C1 rank-1 surface forms per gold act (top `top_n` most fragmented).
#' Faithful graduation of the inline figure in `notebooks/c0_aggregator.qmd`.
#'
#' @param c0_eval_gold_pairs Gold (measure_name, gold_act_name) pairs.
#' @param top_n Number of most-fragmented acts to show.
#' @return A ggplot object.
plot_variance_per_act <- function(c0_eval_gold_pairs, top_n = 25) {
  c0_eval_gold_pairs |>
    dplyr::distinct(measure_name, gold_act_name) |>
    dplyr::count(gold_act_name, name = "n_surface_forms") |>
    dplyr::arrange(dplyr::desc(n_surface_forms)) |>
    utils::head(top_n) |>
    dplyr::mutate(
      gold_act_name = forcats::fct_reorder(
        stringr::str_trunc(gold_act_name, 60), n_surface_forms
      )
    ) |>
    ggplot2::ggplot(ggplot2::aes(n_surface_forms, gold_act_name)) +
    ggplot2::geom_col(fill = "#4477AA") +
    ggplot2::geom_text(
      ggplot2::aes(label = n_surface_forms),
      hjust = -0.2, size = 3
    ) +
    ggplot2::scale_x_continuous(
      expand = ggplot2::expansion(mult = c(0, 0.1))
    ) +
    ggplot2::labs(x = "Distinct rank-1 surface forms", y = NULL)
}
