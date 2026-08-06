# Parse iteration log YAML files into tidy tibbles
#
# Reads prompts/iterations/{c1,c2a,c2b}.yml and produces structured tibbles
# for programmatic reporting of H&K evaluation metrics across codebook
# development iterations.

# -- Null-coalescing helper (if not already available) -------------------------
`%||%` <- function(x, y) if (is.null(x)) y else x

# -- Safe extraction helper ----------------------------------------------------
safe_pluck <- function(x, ..., .default = NA) {

tryCatch(purrr::pluck(x, ..., .default = .default), error = function(e) .default)
}

# =============================================================================
# Per-entry parsers (one per stage type)
# =============================================================================

#' Parse metadata from a single iteration entry
#' @param entry List — one element of the iterations array
#' @param codebook_id Character codebook identifier ("c1", "c2a", "c2b")
#' @return One-row tibble
parse_meta_entry <- function(entry, codebook_id) {
  tibble::tibble(
    codebook         = codebook_id,
    iteration        = entry$iteration %||% NA_integer_,
    codebook_version = entry$codebook_version %||% NA_character_,
    date             = as.Date(entry$date %||% NA_character_),
    git_commit       = entry$git_commit %||% NA_character_,
    model            = entry$model %||% NA_character_,
    provider         = entry$provider %||% NA_character_,
    stage            = entry$stage %||% NA_character_,
    overall_pass     = safe_pluck(entry, "results", "overall_pass", .default = NA),
    condition        = entry$condition %||% NA_character_,
    # Prose fields for programmatic narration of development history
    changes          = entry$changes %||% NA_character_,
    interpretation   = entry$interpretation %||% NA_character_,
    decision         = entry$decision %||% NA_character_
  )
}

#' Parse S1 behavioral test metrics from a single iteration entry
#' @param entry List — one element of the iterations array
#' @param codebook_id Character codebook identifier
#' @return tibble with one row per S1 test, or NULL if not an S1 stage
parse_s1_entry <- function(entry, codebook_id) {
  if (!identical(entry$stage, "s1")) return(NULL)

  metrics <- entry$results$metrics
  if (is.null(metrics)) return(NULL)

  # Two log dialects carry the Test IV order-invariance diagnostics: older
  # entries nest them inside the IV metric object, newer ones (c1 iters 29-30)
  # emit them as a `test_iv_diagnostics` sibling of `metrics`. Read the metric
  # first and fall back to the sibling, so both dialects yield a kappa.
  iv_diag <- entry$results$test_iv_diagnostics

  rows <- purrr::map(metrics, function(m) {
    is_iv <- grepl("IV", m$test %||% "", fixed = TRUE)
    iv_field <- function(nm, default) {
      m[[nm]] %||% (if (is_iv) iv_diag[[nm]] else NULL) %||% default
    }

    tibble::tibble(
      codebook              = codebook_id,
      iteration             = entry$iteration,
      model                 = entry$model %||% NA_character_,
      test                  = m$test %||% NA_character_,
      value                 = as.numeric(m$value %||% NA_real_),
      threshold             = as.numeric(m$threshold %||% NA_real_),
      pass                  = m$pass %||% NA,
      skipped               = m$skipped %||% FALSE,
      # Test IV extras
      change_rate_reversed  = as.numeric(iv_field("change_rate_reversed", NA_real_)),
      change_rate_shuffled  = as.numeric(iv_field("change_rate_shuffled", NA_real_)),
      fleiss_kappa          = as.numeric(iv_field("fleiss_kappa", NA_real_)),
      kappa_interpretation  = as.character(iv_field("kappa_interpretation", NA_character_))
    )
  })

  dplyr::bind_rows(rows)
}

#' Parse S2 zero-shot evaluation metrics from a single iteration entry
#' @param entry List — one element of the iterations array
#' @param codebook_id Character codebook identifier
#' @return Named list with $metrics tibble and $per_class tibble, or NULL
parse_s2_entry <- function(entry, codebook_id) {
  if (!identical(entry$stage, "s2")) return(NULL)

  # -- Primary metrics ---------------------------------------------------------
  metrics_raw <- entry$results$metrics
  if (is.null(metrics_raw)) return(NULL)

  # Some S2 entries have metrics as a list with a $note and no numeric data
  # (e.g., C2a extraction-only stages). Skip these.
  if (length(metrics_raw) == 1 && !is.null(metrics_raw$note)) return(NULL)
  # Also handle the case where metrics is a named list with just "note"
  if (is.list(metrics_raw) && !is.null(names(metrics_raw)) && "note" %in% names(metrics_raw) && length(metrics_raw) == 1) return(NULL)

  parse_metric_list <- function(metric_list) {
    purrr::map(metric_list, function(m) {
      # Skip non-metric entries (e.g., notes embedded in arrays)
      if (is.null(m$metric) && is.null(m$value)) return(NULL)
      tibble::tibble(
        codebook  = codebook_id,
        iteration = entry$iteration,
        model     = entry$model %||% NA_character_,
        condition = entry$condition %||% NA_character_,
        metric    = m$metric %||% NA_character_,
        value     = as.numeric(m$value %||% NA_real_),
        ci_lower  = as.numeric(m$ci_lower %||% NA_real_),
        ci_upper  = as.numeric(m$ci_upper %||% NA_real_),
        target    = as.numeric(m$target %||% NA_real_),
        pass      = m$pass %||% NA
      )
    }) |> purrr::compact() |> dplyr::bind_rows()
  }

  metrics_tbl <- parse_metric_list(metrics_raw)

  # Secondary metrics (C2b has a separate secondary_metrics array)
  secondary <- entry$results$secondary_metrics
  if (!is.null(secondary)) {
    sec_tbl <- parse_metric_list(secondary)
    metrics_tbl <- dplyr::bind_rows(metrics_tbl, sec_tbl)
  }

  # -- Per-class breakdown -----------------------------------------------------
  per_class_tbl <- NULL

  # Format 1: per_class array of objects with class/precision/recall/f1/support
  per_class_raw <- entry$results$per_class
  if (!is.null(per_class_raw) && is.list(per_class_raw) &&
      length(per_class_raw) > 0 && is.list(per_class_raw[[1]])) {
    per_class_tbl <- purrr::map(per_class_raw, function(pc) {
      tibble::tibble(
        codebook  = codebook_id,
        iteration = entry$iteration,
        class     = pc$class %||% NA_character_,
        precision = as.numeric(pc$precision %||% NA_real_),
        recall    = as.numeric(pc$recall %||% NA_real_),
        f1        = as.numeric(pc$f1 %||% NA_real_),
        support   = as.integer(pc$support %||% NA_integer_)
      )
    }) |> dplyr::bind_rows()
  }

  # Format 2: per_class_f1 as named list/vector (e.g., SPENDING_DRIVEN: 0.60)
  per_class_f1 <- entry$results$per_class_f1
  if (!is.null(per_class_f1) && is.null(per_class_tbl)) {
    f1_vals <- unlist(per_class_f1)
    per_class_tbl <- tibble::tibble(
      codebook  = codebook_id,
      iteration = entry$iteration,
      class     = names(f1_vals),
      precision = NA_real_,
      recall    = NA_real_,
      f1        = as.numeric(f1_vals),
      support   = NA_integer_
    )
  }

  # -- Confusion matrix (C1 only: structured tp/fp/fn/tn) ----------------------
  cm <- entry$results$confusion_matrix
  confusion_tbl <- NULL
  if (!is.null(cm) && !is.null(cm$tp)) {
    confusion_tbl <- tibble::tibble(
      codebook  = codebook_id,
      iteration = entry$iteration,
      tp = as.integer(cm$tp), fp = as.integer(cm$fp),
      fn = as.integer(cm$fn), tn = as.integer(cm$tn)
    )
  }

  list(
    metrics   = metrics_tbl,
    per_class = per_class_tbl,
    confusion = confusion_tbl
  )
}

#' Parse S3 error analysis metrics from a single iteration entry
#' @param entry List — one element of the iterations array
#' @param codebook_id Character codebook identifier
#' @return Named list with $tests tibble and $ablation tibble, or NULL
parse_s3_entry <- function(entry, codebook_id) {
  if (!identical(entry$stage, "s3")) return(NULL)

  metrics_raw <- entry$results$metrics
  if (is.null(metrics_raw)) return(NULL)

  # -- Tests V, VI, VII → long-format field/value tibble -----------------------
  test_rows <- list()

  for (m in metrics_raw) {
    test_name <- m$test %||% NA_character_
    if (is.na(test_name)) next

    # Extract all numeric/character fields as field/value pairs
    fields_to_extract <- switch(test_name,
      "V_exclusion_criteria" = {
        combo_fields <- list()
        if (!is.null(m$combos)) {
          combo_fields <- purrr::imap(m$combos, function(val, key) {
            tibble::tibble(
              codebook = codebook_id, iteration = entry$iteration,
              model = entry$model %||% NA_character_,
              test = test_name, field = paste0("combo_", key),
              value = as.numeric(val)
            )
          })
        }
        scalar_fields <- list()
        for (fname in c("overall_consistency", "all_combos_correct_rate",
                        "filtered_all_combos_correct_rate")) {
          fval <- m[[fname]]
          if (!is.null(fval) && !is.na(suppressWarnings(as.numeric(fval)))) {
            scalar_fields <- c(scalar_fields, list(tibble::tibble(
              codebook = codebook_id, iteration = entry$iteration,
              model = entry$model %||% NA_character_,
              test = test_name, field = fname,
              value = as.numeric(fval)
            )))
          }
        }
        c(combo_fields, scalar_fields)
      },
      "VI_generic_labels" = {
        vi_fields <- c("original_accuracy", "generic_accuracy",
                        "accuracy_difference", "change_rate",
                        "original_f1", "generic_f1", "f1_difference",
                        "original_weighted_f1", "generic_weighted_f1")
        purrr::compact(purrr::map(vi_fields, function(fname) {
          fval <- m[[fname]]
          if (is.null(fval)) return(NULL)
          tibble::tibble(
            codebook = codebook_id, iteration = entry$iteration,
            model = entry$model %||% NA_character_,
            test = test_name, field = fname,
            value = as.numeric(fval)
          )
        }))
      },
      "VII_swapped_labels" = {
        vii_fields <- c("follows_definitions_rate", "follows_names_rate",
                         "swapped_accuracy", "swapped_f1",
                         "swapped_weighted_f1")
        purrr::compact(purrr::map(vii_fields, function(fname) {
          fval <- m[[fname]]
          if (is.null(fval)) return(NULL)
          tibble::tibble(
            codebook = codebook_id, iteration = entry$iteration,
            model = entry$model %||% NA_character_,
            test = test_name, field = fname,
            value = as.numeric(fval)
          )
        }))
      },
      list() # unknown test — skip
    )
    test_rows <- c(test_rows, fields_to_extract)
  }

  tests_tbl <- if (length(test_rows) > 0) dplyr::bind_rows(test_rows) else NULL

  # -- Ablation ----------------------------------------------------------------
  ablation_raw <- entry$results$ablation
  ablation_tbl <- NULL
  if (!is.null(ablation_raw)) {
    ablation_tbl <- purrr::map(ablation_raw, function(a) {
      # Skip entries that are just notes
      if (!is.null(a$note) && is.null(a$accuracy)) return(NULL)

      # Canonical F1: use weighted_f1 if present (C2b), else f1 (C1)
      f1_val <- as.numeric(a$weighted_f1 %||% a$f1 %||% NA_real_)
      f1_drop <- as.numeric(a$weighted_f1_drop %||% a$f1_drop %||% NA_real_)

      tibble::tibble(
        codebook      = codebook_id,
        iteration     = entry$iteration,
        model         = entry$model %||% NA_character_,
        condition     = a$condition %||% NA_character_,
        accuracy      = as.numeric(a$accuracy %||% NA_real_),
        f1            = f1_val,
        accuracy_drop = as.numeric(a$accuracy_drop %||% NA_real_),
        f1_drop       = f1_drop,
        recall        = as.numeric(a$recall %||% NA_real_),
        precision     = as.numeric(a$precision %||% NA_real_),
        tier1_recall  = as.numeric(a$tier1_recall %||% NA_real_),
        tier2_recall  = as.numeric(a$tier2_recall %||% NA_real_)
      )
    }) |> purrr::compact() |> dplyr::bind_rows()
  }

  list(tests = tests_tbl, ablation = ablation_tbl)
}

#' Parse S3 manual analysis metrics from a single iteration entry
#' @param entry List — one element of the iterations array
#' @param codebook_id Character codebook identifier
#' @return tibble with one row per error category, or NULL
parse_s3_manual_entry <- function(entry, codebook_id) {
  if (!identical(entry$stage, "s3_manual_analysis")) return(NULL)

  cat_dist <- entry$results$category_distribution
  if (is.null(cat_dist)) return(NULL)

  cats_tbl <- purrr::map(cat_dist, function(c) {
    tibble::tibble(
      codebook  = codebook_id,
      iteration = entry$iteration,
      model     = entry$model %||% NA_character_,
      category  = c$category %||% NA_character_,
      count     = as.integer(c$count %||% NA_integer_),
      pct       = as.numeric(c$pct %||% NA_real_)
    )
  }) |> dplyr::bind_rows()

  # Bias-corrected metrics as additional rows (if present)
  bc <- entry$results$bias_corrected_metrics
  if (!is.null(bc)) {
    attr(cats_tbl, "bias_corrected") <- list(
      effective_n    = bc$effective_n %||% NA_integer_,
      accuracy       = as.numeric(bc$accuracy %||% NA_real_),
      precision      = as.numeric(bc$precision %||% NA_real_),
      recall         = as.numeric(bc$recall %||% NA_real_),
      tier1_recall   = as.numeric(bc$tier1_recall %||% NA_real_),
      tier2_recall   = as.numeric(bc$tier2_recall %||% NA_real_),
      specificity    = as.numeric(bc$specificity %||% NA_real_)
    )
  }

  cats_tbl
}

#' Parse bias-corrected metrics from a single manual-analysis iteration entry
#'
#' The manual-analysis stage records a `bias_corrected_metrics` block (the
#' label-noise-adjusted gate result). `parse_s3_manual_entry()` attaches these
#' as an attribute that `bind_rows()` drops, so they are surfaced here as their
#' own one-row tibble instead.
#'
#' Two schema dialects are in use and both are read here. C1 writes lowercase
#' `tp/fp/fn/tn` with rate metrics in **percent** units (81.8) and tier-level
#' recalls; C2b writes uppercase `TP/FP/FN/TN` with rate metrics in
#' **proportion** units (0.833) under the gate-specific names
#' `exogenous_precision` / `exogenous_recall` / `sign_accuracy_on_true_exo`.
#' Rates are normalised to proportions on the way out so a single downstream
#' formatter serves both.
#'
#' @param entry List — one element of the iterations array
#' @param codebook_id Character codebook identifier
#' @return One-row tibble, or NULL if not a manual stage / no bias-corrected block
parse_s3_bias_corrected_entry <- function(entry, codebook_id) {
  if (!identical(entry$stage, "s3_manual_analysis")) return(NULL)

  bc <- entry$results$bias_corrected_metrics
  if (is.null(bc)) return(NULL)

  cm <- bc$confusion_matrix

  # Case-insensitive cell lookup (c1 lowercase, c2b uppercase).
  cell <- function(nm) {
    v <- cm[[nm]] %||% cm[[toupper(nm)]] %||% NA
    as.integer(v)
  }

  # Rates are stored as percent by c1 and as proportions by c2b. Anything above
  # 1 is unambiguously percent (a rate metric cannot exceed 1 as a proportion).
  as_prop <- function(x) {
    x <- as.numeric(x %||% NA_real_)
    if (!is.na(x) && x > 1) x / 100 else x
  }

  tibble::tibble(
    codebook     = codebook_id,
    iteration    = entry$iteration,
    model        = entry$model %||% NA_character_,
    effective_n  = as.integer(bc$effective_n %||% NA_integer_),
    tp           = cell("tp"),
    tn           = cell("tn"),
    fp           = cell("fp"),
    fn           = cell("fn"),
    accuracy     = as_prop(bc$accuracy),
    # c2b names the gate metrics after the quantity they gate
    precision    = as_prop(bc$precision %||% bc$exogenous_precision),
    recall       = as_prop(bc$recall %||% bc$exogenous_recall),
    tier1_recall = as_prop(bc$tier1_recall %||% bc$tier_1_recall),
    tier2_recall = as_prop(bc$tier2_recall %||% bc$tier_2_recall),
    specificity  = as_prop(bc$specificity),
    sign_accuracy = as_prop(bc$sign_accuracy_on_true_exo),
    joint_accuracy = as_prop(bc$joint_label_and_sign_accuracy)
  )
}

# =============================================================================
# Top-level parsers
# =============================================================================

#' Parse a single iteration log YAML file into tidy tibbles
#'
#' @param path Character path to YAML iteration log file
#' @param codebook_id Character codebook identifier ("c1", "c2a", "c2b")
#' @return Named list of tibbles: meta, s1, s2, s2_per_class, s2_confusion,
#'         s3, s3_ablation, s3_manual
parse_iteration_log <- function(path, codebook_id) {
  raw <- yaml::read_yaml(path)
  entries <- raw$iterations
  if (is.null(entries)) {
    stop("YAML file missing 'iterations' key: ", path)
  }

  # Parse each entry through all stage-specific parsers
  meta_list       <- list()
  s1_list         <- list()
  s2_metrics_list <- list()
  s2_pc_list      <- list()
  s2_cm_list      <- list()
  s3_tests_list   <- list()
  s3_abl_list     <- list()
  s3_manual_list  <- list()
  s3_bc_list      <- list()


  for (entry in entries) {
    # Meta — always parse
    meta_list <- c(meta_list, list(parse_meta_entry(entry, codebook_id)))

    # S1
    s1 <- parse_s1_entry(entry, codebook_id)
    if (!is.null(s1)) s1_list <- c(s1_list, list(s1))

    # S2
    s2 <- parse_s2_entry(entry, codebook_id)
    if (!is.null(s2)) {
      if (!is.null(s2$metrics))   s2_metrics_list <- c(s2_metrics_list, list(s2$metrics))
      if (!is.null(s2$per_class)) s2_pc_list      <- c(s2_pc_list, list(s2$per_class))
      if (!is.null(s2$confusion)) s2_cm_list      <- c(s2_cm_list, list(s2$confusion))
    }

    # S3
    s3 <- parse_s3_entry(entry, codebook_id)
    if (!is.null(s3)) {
      if (!is.null(s3$tests))    s3_tests_list <- c(s3_tests_list, list(s3$tests))
      if (!is.null(s3$ablation)) s3_abl_list   <- c(s3_abl_list, list(s3$ablation))
    }

    # S3 manual analysis
    s3m <- parse_s3_manual_entry(entry, codebook_id)
    if (!is.null(s3m)) s3_manual_list <- c(s3_manual_list, list(s3m))

    # S3 manual analysis — bias-corrected metrics
    s3bc <- parse_s3_bias_corrected_entry(entry, codebook_id)
    if (!is.null(s3bc)) s3_bc_list <- c(s3_bc_list, list(s3bc))
  }

  list(
    meta                     = dplyr::bind_rows(meta_list),
    s1                       = dplyr::bind_rows(s1_list),
    s2                       = dplyr::bind_rows(s2_metrics_list),
    s2_per_class             = dplyr::bind_rows(s2_pc_list),
    s2_confusion             = dplyr::bind_rows(s2_cm_list),
    s3                       = dplyr::bind_rows(s3_tests_list),
    s3_ablation              = dplyr::bind_rows(s3_abl_list),
    s3_manual                = dplyr::bind_rows(s3_manual_list),
    s3_manual_bias_corrected = dplyr::bind_rows(s3_bc_list)
  )
}

#' Parse all iteration logs and combine into cross-codebook tibbles
#'
#' @param paths Named character vector of paths. Names are codebook IDs
#'   (e.g., c(c1 = "prompts/iterations/c1.yml", ...))
#' @return Named list of tibbles: meta, s1, s2, s2_per_class, s2_confusion,
#'         s3, s3_ablation, s3_manual
parse_all_iteration_logs <- function(paths) {
  results <- purrr::imap(paths, function(path, codebook_id) {
    parse_iteration_log(path, codebook_id)
  })

  # Combine each tibble type across codebooks
  tibble_names <- c("meta", "s1", "s2", "s2_per_class", "s2_confusion",
                    "s3", "s3_ablation", "s3_manual", "s3_manual_bias_corrected")

  combined <- purrr::set_names(purrr::map(tibble_names, function(nm) {
    tbls <- purrr::map(results, nm) |> purrr::compact()
    if (length(tbls) == 0) return(tibble::tibble())
    dplyr::bind_rows(tbls)
  }), tibble_names)

  combined
}
