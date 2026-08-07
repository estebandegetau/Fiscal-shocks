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
# tinytable Tables
#
# tinytable ports of the gt_* helpers above, following the project convention
# that newly-edited notebooks use tinytable (tt) + tt_theme_report(). The gt_*
# versions are retained for notebooks still on gt (e.g. iteration_summary.qmd).
# Requires tt_theme_report() from R/tt_theme.R to be sourced.
# =============================================================================

#' S2 metrics summary table (tinytable)
#'
#' @param s2_data tibble from iteration_logs$s2, pre-filtered to one iteration
#' @return tinytable object
tt_s2_metrics_table <- function(s2_data) {
  tbl <- s2_data |>
    dplyr::mutate(
      Estimate = dplyr::case_when(
        !is.na(ci_lower) & !is.na(ci_upper) ~
          sprintf("%.3f [%.3f, %.3f]", value, ci_lower, ci_upper),
        TRUE ~ sprintf("%.3f", value)
      ),
      Target = dplyr::if_else(is.na(target), "—",
                               sprintf("≥ %.2f", target)),
      Status = dplyr::case_when(
        is.na(pass) ~ "—",
        pass ~ "Pass",
        TRUE ~ "Fail"
      )
    ) |>
    dplyr::select(Metric = metric, Estimate, Target, Status)

  pass_rows <- which(tbl$Status == "Pass")
  fail_rows <- which(tbl$Status == "Fail")

  out <- tinytable::tt(tbl)
  if (length(pass_rows) > 0) {
    out <- tinytable::style_tt(out, i = pass_rows, background = "#E8F5E9")
  }
  if (length(fail_rows) > 0) {
    out <- tinytable::style_tt(out, i = fail_rows, background = "#FFEBEE")
  }
  tt_theme_report(out)
}

#' H&K Table 4-style ablation table (tinytable)
#'
#' @param ablation_data tibble from iteration_logs$s3_ablation, pre-filtered
#' @return tinytable object
tt_ablation_table <- function(ablation_data) {
  tbl <- ablation_data |>
    dplyr::mutate(
      condition = factor(condition,
        levels = c("full", "no_label_def", "no_clarifications", "all_removed"),
        labels = c("Full codebook", "No label definitions",
                    "No clarifications", "All removed")
      )
    ) |>
    dplyr::arrange(condition) |>
    dplyr::transmute(
      Condition    = as.character(condition),
      Accuracy     = sprintf("%.3f", accuracy),
      F1           = sprintf("%.3f", f1),
      `Δ Accuracy` = dplyr::if_else(is.na(accuracy_drop), "—",
                                          sprintf("%.3f", accuracy_drop)),
      `Δ F1`       = dplyr::if_else(is.na(f1_drop), "—",
                                          sprintf("%.3f", f1_drop))
    )

  full_rows <- which(tbl$Condition == "Full codebook")

  out <- tinytable::tt(tbl)
  if (length(full_rows) > 0) {
    out <- tinytable::style_tt(out, i = full_rows, background = "#E8F5E9")
  }
  tt_theme_report(out)
}

#' H&K Table 5-style manual error analysis table (tinytable)
#'
#' @param manual_data tibble from iteration_logs$s3_manual, pre-filtered to
#'   one iteration
#' @return tinytable object
tt_manual_analysis_table <- function(manual_data) {
  category_labels <- c(
    "A_llm_correct"              = "A: LLM correct",
    "B_incorrect_gold"           = "B: Incorrect gold standard",
    # C2b records the same category under a name reflecting why its gold is
    # wrong: the act is genuinely multi-motivation and the gold label follows a
    # tie-breaking convention rather than the codebook.
    "B_evaluation_framework_gap" = "B: Incorrect gold standard",
    "C_document_error"           = "C: Document error",
    "D_non_compliance"           = "D: LLM non-compliance",
    "E_semantics_reasoning"      = "E: Semantics/reasoning mistake",
    "F_other"                    = "F: Other"
  )

  tbl <- manual_data |>
    dplyr::mutate(
      Category = dplyr::coalesce(category_labels[category], category),
      Proportion = sprintf("%.2f", count / sum(count))
    ) |>
    dplyr::select(Category, Count = count, Proportion)

  a_rows <- which(grepl("^A:", tbl$Category))
  e_rows <- which(grepl("^E:", tbl$Category))
  f_rows <- which(grepl("^F:", tbl$Category))

  out <- tinytable::tt(tbl)
  if (length(a_rows) > 0) out <- tinytable::style_tt(out, i = a_rows, background = "#E8F5E9")
  if (length(e_rows) > 0) out <- tinytable::style_tt(out, i = e_rows, background = "#FFEBEE")
  if (length(f_rows) > 0) out <- tinytable::style_tt(out, i = f_rows, background = "#FFF3E0")
  tt_theme_report(out)
}

#' Bias-corrected manual-analysis metrics table (tinytable)
#'
#' Renders the label-noise-adjusted gate result (confusion matrix + metrics)
#' for one manual-analysis iteration. Rate metrics arrive as proportions
#' (the parser normalises the two log dialects).
#'
#' Superseded by the `tt_confusion_matrix()` / `tt_gate_metrics()` pair, which
#' separate the counts from the rates. Retained because the notebooks call it.
#'
#' @param bc_data one-row tibble from iteration_logs$s3_manual_bias_corrected
#' @return tinytable object
tt_bias_corrected_table <- function(bc_data) {
  bc <- bc_data[1, ]
  pct <- function(x) if (is.na(x)) "—" else sprintf("%.1f%%", 100 * x)
  int <- function(x) if (is.na(x)) "—" else as.character(x)

  tbl <- tibble::tibble(
    Quantity = c(
      "Effective N", "True positives", "True negatives",
      "False positives", "False negatives",
      "Accuracy", "Precision", "Recall",
      "Tier 1 recall", "Tier 2 recall", "Specificity"
    ),
    Value = c(
      int(bc$effective_n), int(bc$tp), int(bc$tn), int(bc$fp), int(bc$fn),
      pct(bc$accuracy), pct(bc$precision), pct(bc$recall),
      pct(bc$tier1_recall), pct(bc$tier2_recall), pct(bc$specificity)
    )
  )

  tinytable::tt(tbl) |> tt_theme_report()
}

#' Label-noise-adjusted confusion matrix (tinytable)
#'
#' The counts half of the bias-corrected gate result: a 2x2 predicted-by-actual
#' matrix with margins, after the chunks whose gold label the manual analysis
#' judged wrong (Category B, and Category C where present) have been excluded.
#'
#' @param bc_data one-row tibble from iteration_logs$s3_manual_bias_corrected
#' @return tinytable object, or NULL when the entry logged no confusion matrix
tt_confusion_matrix <- function(bc_data) {
  bc <- bc_data[1, ]
  if (is.na(bc$tp) || is.na(bc$tn) || is.na(bc$fp) || is.na(bc$fn)) return(NULL)

  tbl <- tibble::tibble(
    ` `                = c("Predicted positive", "Predicted negative", "Total"),
    `Actual positive`  = c(bc$tp, bc$fn, bc$tp + bc$fn),
    `Actual negative`  = c(bc$fp, bc$tn, bc$fp + bc$tn),
    Total              = c(bc$tp + bc$fp, bc$fn + bc$tn,
                           bc$tp + bc$fp + bc$fn + bc$tn)
  )

  tinytable::tt(tbl) |>
    tinytable::style_tt(i = 1:2, j = 2:3, bold = TRUE) |>
    tt_theme_report()
}

#' Label-noise-adjusted gate metrics (tinytable)
#'
#' The rates half of the bias-corrected gate result. Emits only the metrics the
#' iteration actually recorded, so the same function serves C1 (tier-level
#' recall) and C2b (exogenous precision, sign accuracy on true-exogenous).
#'
#' @param bc_data one-row tibble from iteration_logs$s3_manual_bias_corrected
#' @param targets Named numeric vector of gate thresholds, keyed by the column
#'   names of `bc_data` (e.g. `c(precision = 0.85, sign_accuracy = 0.90)`).
#'   Metrics with no entry render an em dash in the Target column.
#' @param labels Optional named character vector overriding the display name of
#'   a metric, keyed the same way. Use it to name what a generic column means in
#'   a given codebook (e.g. `c(precision = "Exogenous precision")`).
#' @return tinytable object
tt_gate_metrics <- function(bc_data, targets = NULL, labels = NULL) {
  bc <- bc_data[1, ]

  metric_labels <- c(
    accuracy       = "Accuracy",
    precision      = "Precision",
    recall         = "Recall",
    tier1_recall   = "Tier 1 recall",
    tier2_recall   = "Tier 2 recall",
    specificity    = "Specificity",
    sign_accuracy  = "Sign accuracy on true-exogenous",
    joint_accuracy = "Joint label-and-sign accuracy"
  )
  if (!is.null(labels)) metric_labels[names(labels)] <- unname(labels)

  present <- names(metric_labels)[
    names(metric_labels) %in% names(bc) &
      !vapply(names(metric_labels), function(nm) {
        !nm %in% names(bc) || is.na(bc[[nm]])
      }, logical(1))
  ]

  tbl <- tibble::tibble(
    Metric = unname(metric_labels[present]),
    value  = vapply(present, function(nm) as.numeric(bc[[nm]]), numeric(1)),
    target = vapply(present, function(nm) {
      if (is.null(targets) || !nm %in% names(targets)) NA_real_ else targets[[nm]]
    }, numeric(1))
  ) |>
    dplyr::mutate(
      Estimate = sprintf("%.1f%%", 100 * value),
      Target   = dplyr::if_else(is.na(target), "—",
                                sprintf("≥ %.0f%%", 100 * target)),
      Status   = dplyr::case_when(
        is.na(target)    ~ "—",
        value >= target  ~ "Pass",
        TRUE             ~ "Below gate"
      )
    ) |>
    dplyr::select(Metric, Estimate, Target, Status)

  pass_rows <- which(tbl$Status == "Pass")
  fail_rows <- which(tbl$Status == "Below gate")

  out <- tinytable::tt(tbl)
  if (length(pass_rows) > 0) {
    out <- tinytable::style_tt(out, i = pass_rows, background = "#E8F5E9")
  }
  if (length(fail_rows) > 0) {
    out <- tinytable::style_tt(out, i = fail_rows, background = "#FFEBEE")
  }
  tt_theme_report(out)
}

#' What each behavioural test probes (tinytable)
#'
#' A static reader's key to the H&K test battery. Tests I-IV run at S1 (before
#' any evaluation data is touched); Tests V-VII run at S3 alongside the ablation
#' and the manual error analysis.
#'
#' @return tinytable object
tt_hk_tests_table <- function() {
  tibble::tribble(
    ~Test,                   ~`What it probes`,                                                                          ~`Passing means`,
    "I. Legal outputs",      "Every response is one of the labels the codebook defines",                                 "The model can express itself in the codebook's vocabulary",
    "II. Memorisation",      "Whether the model can recite the codebook's own definitions and instructions unprompted",   "Agreement later on is not recall of a document the model already knows",
    "III. Example recovery", "Whether the model reproduces the codebook's worked examples verbatim",                      "The examples teach rather than leak",
    "IV. Order invariance",  "Whether shuffling or reversing the class order changes the label",                          "The label tracks the definition, not its position in the prompt",
    "V. Exclusion criteria", "Whether the codebook's stated exclusions are applied when the document or codebook is perturbed", "Exclusion rules are enforced, not decorative",
    "VI. Generic labels",    "Accuracy when informative label names are replaced by neutral ones",                        "The model reads the definitions, not the label names",
    "VII. Swapped labels",   "Whether the model follows the definition or the name when the two are put in conflict",     "The construct lives in the definition the researcher wrote"
  ) |>
    tinytable::tt(width = c(0.19, 0.45, 0.36)) |>
    tt_theme_report() |>
    tinytable::style_tt(j = 1:3, align = "l")
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

  # Separate Test IV (kappa scale) from Tests I-III (percent scale). Drop the
  # unused factor levels in each panel, or each draws a blank row for the tests
  # that belong to the other one.
  tests_pct <- plot_data |> dplyr::filter(!grepl("IV", test)) |> droplevels()
  test_iv   <- plot_data |> dplyr::filter(grepl("IV", test)) |>
    dplyr::filter(!is.na(fleiss_kappa)) |> droplevels()

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
      # A legend naming one codebook is noise; keep it only when comparing.
      legend.position = if (dplyr::n_distinct(plot_data$group_var) > 1) "top" else "none",
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


#' S2 zero-shot metrics with bootstrap intervals
#'
#' Point estimate and 95% bootstrap CI per metric, with the diagnostic
#' benchmark drawn as an open marker. Replaces the S2 metrics table where the
#' interval, not the third decimal, is the thing to read.
#'
#' @param s2_data tibble from iteration_logs$s2, pre-filtered to one iteration
#' @return ggplot object, or NULL when there is nothing to plot
plot_s2_metrics <- function(s2_data) {
  plot_data <- s2_data |>
    dplyr::filter(!is.na(value)) |>
    dplyr::mutate(
      metric_label = metric |>
        gsub("tier1", "tier 1", x = _) |>
        gsub("tier2", "tier 2", x = _) |>
        gsub("_", " ", x = _) |>
        stringr::str_to_sentence() |>
        gsub("f1", "F1", x = _),
      metric_label = factor(metric_label, levels = rev(unique(metric_label))),
      Status = dplyr::case_when(
        is.na(pass) ~ "No benchmark",
        pass        ~ "Meets benchmark",
        TRUE        ~ "Below benchmark"
      )
    )

  if (nrow(plot_data) == 0) return(NULL)

  p <- ggplot2::ggplot(plot_data,
    ggplot2::aes(x = value, y = metric_label, colour = Status))

  if (any(!is.na(plot_data$ci_lower))) {
    p <- p + ggplot2::geom_errorbar(
      ggplot2::aes(xmin = ci_lower, xmax = ci_upper),
      orientation = "y", width = 0.18, linewidth = 0.5, na.rm = TRUE
    )
  }

  p +
    ggplot2::geom_point(size = 3) +
    ggplot2::geom_point(
      ggplot2::aes(x = target), shape = 4, size = 2.6, stroke = 0.9,
      colour = "grey30", na.rm = TRUE
    ) +
    ggplot2::scale_x_continuous(
      labels = scales::percent_format(), limits = c(0, 1.05),
      breaks = c(0, 0.25, 0.5, 0.75, 1.0)
    ) +
    ggplot2::scale_colour_manual(values = c(
      "Meets benchmark" = "#2E7D32",
      "Below benchmark" = "#C62828",
      "No benchmark"    = "#607D8B"
    )) +
    ggplot2::labs(x = "Estimate (bars: 95% bootstrap CI; x: benchmark)",
                  y = NULL, colour = NULL) +
    ggplot2::theme_minimal(base_family = "Libertinus Serif") +
    ggplot2::theme(
      legend.position = "top",
      panel.grid.minor = ggplot2::element_blank()
    )
}


#' H&K Figure 4-style S3 behavioral test chart
#'
#' Lollipop chart of S3 Tests V-VII for one iteration, in the same idiom as
#' `plot_s1_behavioral()` so the two read as one battery.
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
      # Most specific first: "VI_" and "VII_" both start with "V", so testing
      # for "^V" ahead of them collapses all three groups into Test V.
      test_group = dplyr::case_when(
        grepl("^VII_", test) ~ "Test VII",
        grepl("^VI_",  test) ~ "Test VI",
        grepl("^V_",   test) ~ "Test V"
      ),
      test_group = factor(test_group, levels = c("Test V", "Test VI", "Test VII"))
    )

  p <- ggplot2::ggplot(plot_data,
    ggplot2::aes(x = value, y = field_label, colour = test_group)) +
    ggplot2::geom_segment(
      ggplot2::aes(xend = 0, yend = field_label),
      linewidth = 0.6, alpha = 0.5
    ) +
    ggplot2::geom_point(size = 3) +
    ggplot2::scale_x_continuous(
      labels = scales::percent_format(),
      limits = c(0, 1.05),
      breaks = c(0, 0.25, 0.5, 0.75, 1.0)
    ) +
    ggplot2::scale_colour_manual(values = c(
      "Test V"   = "#2E7D32",
      "Test VI"  = "#1565C0",
      "Test VII" = "#EF6C00"
    )) +
    ggplot2::labs(x = "Value", y = NULL, colour = NULL) +
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
