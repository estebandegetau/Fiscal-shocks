#' C2b evidence-record shuffle diagnostic
#'
#' Tests whether C2b classifications are stable under per-act shuffling of
#' the evidence-record array. A stable rule should produce the same
#' classification regardless of evidence order; instability indicates the
#' rule is firing on positional/surface features rather than substantive
#' content. Compares F-cluster (rule-priority-gap) acts against A-cluster
#' (correctly-classified) acts; the F-A median-stability gap is the key
#' overfit signal.
#'
#' Reuses extract_c2b_label() fingerprint logic (motivation multiset +
#' exogenous flag) from R/c2_behavioral_tests.R, format_c2b_input() and
#' call_codebook_generic() from the existing C2b stack, and fleiss_kappa()
#' from R/behavioral_tests.R.


#' Build S3 act clusters tibble from a manual-analysis iteration entry
#'
#' Reads the per-act review notes (act_judgments) from the specified
#' iteration in prompts/iterations/c2b.yml. The per-act entries are the
#' authoritative source for F/A classification — the affected_acts summary
#' list elsewhere in the iteration entry can disagree with the per-act
#' categories, per the iter-30 cluster-list resolution check.
#'
#' @param iterations_yaml Path to c2b.yml iteration log
#' @param iteration Integer iteration to read (default 30L, S3 manual analysis)
#' @param keep_clusters Character vector of cluster codes to retain
#'   (default c("F", "A"))
#' @return Tibble with columns act_id, act_name, true_label, pred_label, cluster
#' @export
build_s3_act_clusters <- function(iterations_yaml,
                                  iteration = 30L,
                                  keep_clusters = c("F", "A")) {
  parsed <- yaml::read_yaml(iterations_yaml)
  iters <- parsed$iterations %||% parsed
  iter_idx <- which(vapply(iters, function(x) {
    isTRUE(x$iteration == iteration)
  }, logical(1)))
  if (length(iter_idx) != 1L) {
    stop("Iteration ", iteration, " not found in ", iterations_yaml)
  }
  judgments <- iters[[iter_idx]]$results$act_judgments
  if (length(judgments) == 0L) {
    stop("No act_judgments under iteration ", iteration,
         " in ", iterations_yaml)
  }

  # YAML parses the bare "true:" key as logical TRUE, so the list element
  # is named "TRUE" (capitalised) — access via [["TRUE"]], not $true.
  get_id   <- function(j) as.integer(j$act_id)
  get_name <- function(j) j$act_name
  get_true <- function(j) j[["TRUE"]] %||% NA_character_
  get_pred <- function(j) j$pred %||% NA_character_
  get_cat  <- function(j) j$category

  out <- tibble::tibble(
    act_id     = vapply(judgments, get_id, integer(1)),
    act_name   = vapply(judgments, get_name, character(1)),
    true_label = vapply(judgments, get_true, character(1)),
    pred_label = vapply(judgments, get_pred, character(1)),
    cluster    = vapply(judgments, get_cat, character(1))
  )

  dplyr::filter(out, .data$cluster %in% keep_clusters)
}


#' Test C2b stability under per-act evidence-record shuffle
#'
#' For each act in target_acts: classify with the original evidence ordering
#' and with k_shuffles deterministic permutations. Per-act stability is the
#' fraction of permuted runs whose category|exogenous fingerprint matches
#' the original. Returns per-cluster medians, Fleiss kappa, F-A gap, and a
#' three-way verdict (pass / fail-overfit / structural_issue).
#'
#' @param c2b_codebook Parsed codebook from load_validate_codebook()
#' @param c2b_inputs Tibble of frozen C2a evidence (data/validated/c2a_evidence.qs);
#'   columns include act_name, year, evidence (list-col of {quote, signal}),
#'   enacted_signals (list-col)
#' @param target_acts Tibble with act_name and cluster ("F" or "A")
#' @param k_shuffles Number of permutations per act (default 3L)
#' @param model Anthropic model ID
#' @param max_tokens_c2b Token budget per call
#' @param seed Integer seed; per-act seed is seed + i
#' @param provider,base_url,api_key Standard API parameters
#' @return List with per_act tibble, summary_by_cluster tibble,
#'   f_minus_a_gap, verdict, plus run metadata
#' @export
test_c2b_evidence_shuffle <- function(c2b_codebook,
                                      c2b_inputs,
                                      target_acts,
                                      k_shuffles = 3L,
                                      model = "claude-haiku-4-5-20251001",
                                      max_tokens_c2b = 4096,
                                      seed = 42L,
                                      provider = "anthropic",
                                      base_url = NULL,
                                      api_key = NULL) {

  `%||%` <- function(x, y) if (is.null(x)) y else x

  stopifnot(
    is.data.frame(target_acts),
    all(c("act_name", "cluster") %in% names(target_acts)),
    is.numeric(k_shuffles),
    k_shuffles >= 1L
  )

  inputs_lookup <- c2b_inputs |>
    dplyr::filter(.data$act_name %in% target_acts$act_name) |>
    dplyr::distinct(.data$act_name, .keep_all = TRUE)

  missing_acts <- setdiff(target_acts$act_name, inputs_lookup$act_name)
  if (length(missing_acts) > 0L) {
    warning("Acts in target_acts not present in c2b_inputs: ",
            paste(missing_acts, collapse = "; "))
  }

  joined <- dplyr::inner_join(target_acts, inputs_lookup, by = "act_name")
  n_targets <- nrow(joined)
  if (n_targets == 0L) {
    stop("No target acts overlap with c2b_inputs.")
  }

  system_prompt <- construct_codebook_prompt(c2b_codebook)

  fingerprint <- function(parsed) {
    if (is.null(parsed)) return(NA_character_)
    cats <- vapply(
      parsed$motivations %||% list(),
      function(m) m$category %||% NA_character_,
      character(1)
    )
    cats <- sort(cats[!is.na(cats)])
    cat_str <- if (length(cats) == 0L) "NONE" else paste(cats, collapse = "+")
    exo_str <- as.character(parsed$exogenous %||% NA)
    paste(cat_str, exo_str, sep = "|")
  }

  classify_one <- function(act_name, year, evidence, enacted_signals) {
    user_msg <- format_c2b_input(act_name, year, evidence, enacted_signals)
    tryCatch({
      parsed <- call_codebook_generic(
        user_message  = user_msg,
        codebook      = c2b_codebook,
        model         = model,
        system_prompt = system_prompt,
        max_tokens    = max_tokens_c2b,
        temperature   = 0,
        provider      = provider,
        base_url      = base_url,
        api_key       = api_key
      )
      fingerprint(parsed)
    }, error = function(e) NA_character_)
  }

  per_act <- purrr::map_dfr(seq_len(n_targets), function(i) {
    row <- joined[i, ]
    evidence <- row$evidence[[1]]
    enacted_signals <- row$enacted_signals[[1]]
    n_records <- length(evidence)

    fp_orig <- classify_one(row$act_name, row$year, evidence, enacted_signals)

    set.seed(seed + i)
    perms <- if (n_records >= 2L) {
      replicate(k_shuffles, sample.int(n_records), simplify = FALSE)
    } else {
      replicate(k_shuffles, seq_len(n_records), simplify = FALSE)
    }

    fp_shuffles <- vapply(perms, function(p) {
      classify_one(row$act_name, row$year, evidence[p], enacted_signals)
    }, character(1))

    valid_shuffles <- !is.na(fp_shuffles)
    matches <- !is.na(fp_orig) & valid_shuffles & fp_shuffles == fp_orig
    stability <- if (any(valid_shuffles)) {
      sum(matches) / sum(valid_shuffles)
    } else {
      NA_real_
    }

    tibble::tibble(
      act_name             = row$act_name,
      cluster              = row$cluster,
      n_evidence           = n_records,
      fingerprint_original = fp_orig,
      fingerprint_shuffles = list(fp_shuffles),
      n_valid_shuffles     = sum(valid_shuffles),
      stability_rate       = stability
    )
  })

  ratings_matrix <- do.call(rbind, lapply(seq_len(nrow(per_act)), function(i) {
    c(per_act$fingerprint_original[i], per_act$fingerprint_shuffles[[i]])
  }))

  summary_by_cluster <- per_act |>
    dplyr::group_by(.data$cluster) |>
    dplyr::summarise(
      n_acts           = dplyr::n(),
      median_stability = stats::median(.data$stability_rate, na.rm = TRUE),
      mean_stability   = mean(.data$stability_rate, na.rm = TRUE),
      .groups          = "drop"
    )

  fk_per_cluster <- vapply(summary_by_cluster$cluster, function(g) {
    idx <- per_act$cluster == g
    if (sum(idx) < 2L) return(NA_real_)
    mat <- ratings_matrix[idx, , drop = FALSE]
    fleiss_kappa(mat)$kappa
  }, numeric(1))
  summary_by_cluster$fleiss_kappa <- fk_per_cluster

  pull_med <- function(g) {
    v <- summary_by_cluster$median_stability[summary_by_cluster$cluster == g]
    if (length(v) == 0L) NA_real_ else v
  }
  f_med <- pull_med("F")
  a_med <- pull_med("A")
  gap <- f_med - a_med

  verdict <- if (is.na(f_med) || is.na(a_med)) {
    "incomplete"
  } else if (gap < -0.10) {
    "fail (overfit)"
  } else if (f_med < 0.80 && a_med < 0.80) {
    "structural_issue"
  } else if (f_med >= 0.80 && a_med >= 0.80) {
    "pass"
  } else {
    "marginal"
  }

  list(
    per_act            = per_act,
    summary_by_cluster = summary_by_cluster,
    f_minus_a_gap      = gap,
    verdict            = verdict,
    n_acts_total       = nrow(per_act),
    k_shuffles         = as.integer(k_shuffles),
    seed               = as.integer(seed),
    model              = model,
    codebook_version   = c2b_codebook$version %||% NA_character_
  )
}
