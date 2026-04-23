# Reporting functions for iteration log data
#
# Produces H&K-style gt tables and ggplot2 plots from parsed iteration logs.
# All functions are pure (no side effects) and follow project conventions.

# =============================================================================
# gt Tables
# =============================================================================

#' S2 metrics summary table
#'
#' Shows value [CI], target, and pass/fail for a single iteration.
#'
#' @param s2_data tibble from iteration_logs$s2, pre-filtered to one iteration
#' @param title Optional subtitle for the table
#' @return gt table object
gt_s2_metrics_table <- function(s2_data, title = NULL) {
  tbl <- s2_data |>
    dplyr::mutate(
      estimate = dplyr::case_when(
        !is.na(ci_lower) & !is.na(ci_upper) ~
          sprintf("%.3f [%.3f, %.3f]", value, ci_lower, ci_upper),
        TRUE ~ sprintf("%.3f", value)
      ),
      target_fmt = dplyr::if_else(is.na(target), "\u2014",
                                   sprintf("\u2265 %.2f", target)),
      status = dplyr::case_when(
        is.na(pass) ~ "\u2014",
        pass ~ "Pass",
        TRUE ~ "Fail"
      )
    ) |>
    dplyr::select(metric, estimate, target_fmt, status)

  gt_tbl <- tbl |>
    gt::gt() |>
    gt::cols_label(
      metric = "Metric",
      estimate = "Estimate [95% CI]",
      target_fmt = "Target",
      status = "Status"
    )

  if (!is.null(title)) {
    gt_tbl <- gt_tbl |> gt::tab_header(title = "", subtitle = title)
  }

  gt_tbl |>
    gt::tab_style(
      style = gt::cell_fill(color = "#E8F5E9"),
      locations = gt::cells_body(rows = status == "Pass")
    ) |>
    gt::tab_style(
      style = gt::cell_fill(color = "#FFEBEE"),
      locations = gt::cells_body(rows = status == "Fail")
    ) |>
    gt_theme_report()
}

#' H&K Table 4-style ablation table
#'
#' @param ablation_data tibble from iteration_logs$s3_ablation, pre-filtered
#' @return gt table object
gt_ablation_table <- function(ablation_data) {
  tbl <- ablation_data |>
    dplyr::mutate(
      condition = factor(condition,
        levels = c("full", "no_label_def", "no_clarifications", "all_removed"),
        labels = c("Full codebook", "No label definitions",
                    "No clarifications", "All removed")
      )
    ) |>
    dplyr::select(condition, accuracy, f1, accuracy_drop, f1_drop) |>
    dplyr::arrange(condition)

  tbl |>
    gt::gt() |>
    gt::cols_label(
      condition = "Condition",
      accuracy = "Accuracy",
      f1 = "F1",
      accuracy_drop = "\u0394 Accuracy",
      f1_drop = "\u0394 F1"
    ) |>
    gt::fmt_number(columns = c(accuracy, f1), decimals = 3) |>
    gt::fmt_number(columns = c(accuracy_drop, f1_drop), decimals = 3) |>
    gt::sub_missing(missing_text = "\u2014") |>
    gt::tab_style(
      style = gt::cell_fill(color = "#E8F5E9"),
      locations = gt::cells_body(rows = condition == "Full codebook")
    ) |>
    gt_theme_report()
}

#' H&K Table 5-style manual error analysis table
#'
#' @param manual_data tibble from iteration_logs$s3_manual, pre-filtered to
#'   one iteration
#' @return gt table object
gt_manual_analysis_table <- function(manual_data) {
  # Ensure category labels are reader-friendly
  category_labels <- c(
    "A_llm_correct"         = "A: LLM correct",
    "B_incorrect_gold"      = "B: Incorrect gold standard",
    "C_document_error"      = "C: Document error",
    "D_non_compliance"      = "D: LLM non-compliance",
    "E_semantics_reasoning" = "E: Semantics/reasoning mistake",
    "F_other"               = "F: Other"
  )

  tbl <- manual_data |>
    dplyr::mutate(
      category_label = dplyr::coalesce(
        category_labels[category], category
      ),
      proportion = count / sum(count)
    ) |>
    dplyr::select(category_label, count, proportion)

  tbl |>
    gt::gt() |>
    gt::cols_label(
      category_label = "Category",
      count = "Count",
      proportion = "Proportion"
    ) |>
    gt::fmt_number(columns = proportion, decimals = 2) |>
    gt::tab_style(
      style = gt::cell_fill(color = "#E8F5E9"),
      locations = gt::cells_body(rows = grepl("^A:", category_label))
    ) |>
    gt::tab_style(
      style = gt::cell_fill(color = "#FFEBEE"),
      locations = gt::cells_body(rows = grepl("^E:", category_label))
    ) |>
    gt::tab_style(
      style = gt::cell_fill(color = "#FFF3E0"),
      locations = gt::cells_body(rows = grepl("^F:", category_label))
    ) |>
    gt_theme_report()
}

# =============================================================================
# ggplot2 Plots
# =============================================================================

#' H&K Figure 3-style S1 behavioral test lollipop chart
#'
#' Horizontal lollipop chart showing Tests I-IV results. Each row is a
#' codebook-iteration pair; x-axis is the test metric value.
#'
#' @param s1_data tibble from iteration_logs$s1, pre-filtered to desired iterations
#' @param group_by Character: "codebook" (default) or "model" for color grouping
#' @return ggplot object
plot_s1_behavioral <- function(s1_data, group_by = "codebook") {
  # Create readable test labels
  test_labels <- c(
    "I_legal_outputs"        = "Test I: Legal Labels",
    "II_definition_recovery" = "Test II: Definition\nRecovery",
    "II_instruction_recovery"= "Test II: Instruction\nRecovery",
    "III_example_recovery"   = "Test III: Example\nRecovery",
    "IV_order_invariance"    = "Test IV: Order\nInvariance"
  )

  plot_data <- s1_data |>
    dplyr::filter(!is.na(value)) |>
    dplyr::mutate(
      test_label = factor(
        dplyr::coalesce(test_labels[test], test),
        levels = rev(unname(test_labels))
      ),
      group_var = .data[[group_by]],
      iteration_label = sprintf("%s (iter %d)", codebook, iteration)
    )

  # Separate Test IV (kappa scale) from Tests I-III (percent scale)
  tests_pct <- plot_data |> dplyr::filter(!grepl("IV", test))
  test_iv   <- plot_data |> dplyr::filter(grepl("IV", test))

  # Top panel: Tests I-III (Percent Correct)
  p_top <- ggplot2::ggplot(tests_pct,
    ggplot2::aes(x = value, y = test_label, color = group_var)) +
    ggplot2::geom_segment(
      ggplot2::aes(xend = 0, yend = test_label),
      linewidth = 0.6, alpha = 0.5
    ) +
    ggplot2::geom_point(size = 3) +
    ggplot2::geom_vline(xintercept = 1.0, linetype = "dashed", alpha = 0.4) +
    ggplot2::scale_x_continuous(
      labels = scales::percent_format(),
      limits = c(0, 1.05),
      breaks = c(0, 0.25, 0.5, 0.75, 1.0)
    ) +
    ggplot2::labs(x = "Percent Correct", y = NULL, color = NULL) +
    ggplot2::theme_minimal(base_family = "Libertinus Serif") +
    ggplot2::theme(
      legend.position = "top",
      panel.grid.minor = ggplot2::element_blank()
    )

  if (nrow(test_iv) == 0) return(p_top)

  # Bottom panel: Test IV (Fleiss Kappa)
  p_bot <- ggplot2::ggplot(test_iv,
    ggplot2::aes(x = fleiss_kappa, y = test_label, color = group_var)) +
    ggplot2::geom_segment(
      ggplot2::aes(xend = 0, yend = test_label),
      linewidth = 0.6, alpha = 0.5
    ) +
    ggplot2::geom_point(size = 3) +
    ggplot2::geom_vline(
      xintercept = c(0.41, 0.61, 0.81),
      linetype = "dashed", alpha = 0.3
    ) +
    ggplot2::annotate("text", x = c(0.51, 0.71, 0.91), y = 0.6,
      label = c("Moderate", "Substantial", "Near Perfect"),
      size = 2.5, alpha = 0.5, family = "Libertinus Serif"
    ) +
    ggplot2::scale_x_continuous(limits = c(0, 1.05)) +
    ggplot2::labs(x = "Fleiss' Kappa", y = NULL, color = NULL) +
    ggplot2::theme_minimal(base_family = "Libertinus Serif") +
    ggplot2::theme(
      legend.position = "none",
      panel.grid.minor = ggplot2::element_blank()
    )

  patchwork::wrap_plots(p_top, p_bot, ncol = 1, heights = c(3, 1))
}


#' H&K Figure 4-style S3 behavioral test chart
#'
#' Horizontal bars showing S3 Tests V-VII results for one iteration.
#'
#' @param s3_data tibble from iteration_logs$s3, pre-filtered to one iteration
#' @param ablation_data tibble from iteration_logs$s3_ablation, pre-filtered
#' @return ggplot object
plot_s3_behavioral <- function(s3_data, ablation_data = NULL) {
  # Get baseline F1 from ablation (full condition)
  baseline_f1 <- NA_real_
  if (!is.null(ablation_data) && nrow(ablation_data) > 0) {
    full_row <- ablation_data |> dplyr::filter(condition == "full")
    if (nrow(full_row) > 0) baseline_f1 <- full_row$f1[1]
  }

  # Select key fields for the plot
  plot_fields <- c(
    "combo_normal_doc_normal_cb", "combo_normal_ev_normal_cb",
    "all_combos_correct_rate",
    "original_accuracy", "generic_accuracy", "change_rate",
    "follows_definitions_rate", "follows_names_rate", "swapped_accuracy"
  )

  field_labels <- c(
    "combo_normal_doc_normal_cb" = "Test V (baseline):\nnormal doc, normal cb",
    "combo_normal_ev_normal_cb"  = "Test V (baseline):\nnormal ev, normal cb",
    "all_combos_correct_rate"    = "Test V: All combos\ncorrect",
    "original_accuracy"          = "Test VI: Original\naccuracy",
    "generic_accuracy"           = "Test VI: Generic\nlabel accuracy",
    "change_rate"                = "Test VI: Label\nchange rate",
    "follows_definitions_rate"   = "Test VII: Follows\ndefinitions",
    "follows_names_rate"         = "Test VII: Follows\nlabel names",
    "swapped_accuracy"           = "Test VII: Swapped\naccuracy"
  )

  plot_data <- s3_data |>
    dplyr::filter(field %in% plot_fields) |>
    dplyr::mutate(
      field_label = factor(
        dplyr::coalesce(field_labels[field], field),
        levels = rev(unname(field_labels))
      ),
      test_group = dplyr::case_when(
        grepl("^V", test) ~ "Test V",
        grepl("^VI", test) ~ "Test VI",
        grepl("^VII", test) ~ "Test VII"
      )
    )

  p <- ggplot2::ggplot(plot_data,
    ggplot2::aes(x = value, y = field_label, fill = test_group)) +
    ggplot2::geom_col(width = 0.6, alpha = 0.8) +
    ggplot2::scale_x_continuous(
      labels = scales::percent_format(),
      limits = c(0, 1.05)
    ) +
    ggplot2::scale_fill_manual(values = c(
      "Test V"   = "#66BB6A",
      "Test VI"  = "#42A5F5",
      "Test VII" = "#FFA726"
    )) +
    ggplot2::labs(x = "Value", y = NULL, fill = NULL) +
    ggplot2::theme_minimal(base_family = "Libertinus Serif") +
    ggplot2::theme(
      legend.position = "top",
      panel.grid.minor = ggplot2::element_blank()
    )

  # Add baseline F1 as a vertical reference line if available
  if (!is.na(baseline_f1)) {
    p <- p + ggplot2::geom_vline(
      xintercept = baseline_f1, linetype = "dashed", alpha = 0.5
    ) +
    ggplot2::annotate("text", x = baseline_f1 + 0.02, y = 0.5,
      label = sprintf("Baseline F1 = %.2f", baseline_f1),
      size = 2.8, hjust = 0, family = "Libertinus Serif"
    )
  }

  p
}


#' Metric trajectory plot across iterations
#'
#' Line plot showing how a metric evolves across formal iterations.
#'
#' @param s2_data tibble from iteration_logs$s2
#' @param metric_name Character name of metric to plot
#' @param codebook_filter Optional character vector of codebook_ids to include
#' @param formal_only Logical: filter to Claude models only (default TRUE)
#' @return ggplot object
plot_metric_trajectory <- function(s2_data, metric_name,
                                    codebook_filter = NULL,
                                    formal_only = TRUE) {
  plot_data <- s2_data |>
    dplyr::filter(metric == metric_name)

  if (!is.null(codebook_filter)) {
    plot_data <- plot_data |> dplyr::filter(codebook %in% codebook_filter)
  }

  if (formal_only) {
    plot_data <- plot_data |>
      dplyr::filter(grepl("^claude-", model))
  }

  # Add target line
  target_val <- plot_data |>
    dplyr::filter(!is.na(target)) |>
    dplyr::pull(target) |>
    unique()
  target_val <- if (length(target_val) == 1) target_val else NA_real_

  p <- ggplot2::ggplot(plot_data,
    ggplot2::aes(x = iteration, y = value, color = codebook)) +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::geom_point(size = 2.5)

  # CI ribbon if available
  if (any(!is.na(plot_data$ci_lower))) {
    p <- p + ggplot2::geom_ribbon(
      ggplot2::aes(ymin = ci_lower, ymax = ci_upper, fill = codebook),
      alpha = 0.15, color = NA
    )
  }

  # Target line
  if (!is.na(target_val)) {
    p <- p + ggplot2::geom_hline(
      yintercept = target_val,
      linetype = "dashed", color = "grey40", alpha = 0.6
    ) +
    ggplot2::annotate("text",
      x = min(plot_data$iteration), y = target_val + 0.02,
      label = sprintf("Target: %.2f", target_val),
      size = 3, hjust = 0, family = "Libertinus Serif", color = "grey40"
    )
  }

  p +
    ggplot2::scale_y_continuous(limits = c(0, 1)) +
    ggplot2::labs(
      x = "Iteration", y = metric_name,
      color = "Codebook", fill = "Codebook"
    ) +
    ggplot2::theme_minimal(base_family = "Libertinus Serif") +
    ggplot2::theme(
      legend.position = "top",
      panel.grid.minor = ggplot2::element_blank()
    )
}
