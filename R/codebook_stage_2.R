# Codebook Stage 2: Chunk-Based LOOCV Evaluation
# Generic functions reusable for C1-C4
#
# Redesigned for chunk-level evaluation with tier-stratified metrics.
# Each LOOCV fold: hold out one act, classify its Tier 1+2 chunks and
# a sample of negative chunks.

#' Run Leave-One-Out Cross-Validation for a binary codebook (chunk-based)
#'
#' For each act i in aligned_data:
#' 1. Hold out act i
#' 2. Collect Tier 1+2 chunks for act i (positive test set)
#' 3. Sample negative chunks (negative test set)
#' 4. Generate passage-level few-shot from remaining 43 acts + negatives
#' 5. Classify each test chunk
#'
#' @param codebook A validated codebook object (binary classification)
#' @param aligned_data Tibble with aligned labels (act-level, with passages_text)
#' @param c1_chunk_data List from prepare_c1_chunk_data() with tier1, tier2, negatives
#' @param codebook_type Character codebook identifier ("C1", "C2", etc.)
#' @param model Character model ID (default: "claude-haiku-4-5-20251001")
#' @param n_few_shot Integer few-shot examples per class per fold (default 5)
#' @param n_neg_per_fold Integer negative test chunks per fold (default 10)
#' @param seed Integer base random seed (default 20251206)
#' @param use_self_consistency Logical (default FALSE for LOOCV)
#' @param show_progress Logical show progress bar (default TRUE)
#' @return Tibble with prediction results for all folds
#' @export
run_loocv <- function(codebook,
                      aligned_data,
                      c1_chunk_data,
                      codebook_type = "C1",
                      model = "claude-haiku-4-5-20251001",
                      n_few_shot = 5,
                      n_neg_per_fold = 10,
                      seed = 20251206,
                      use_self_consistency = FALSE,
                      show_progress = TRUE) {

  n_acts <- nrow(aligned_data)
  message(sprintf("Running %s chunk-based LOOCV on %d acts...",
                  codebook_type, n_acts))

  system_prompt <- construct_codebook_prompt(codebook)
  valid_labels <- get_valid_labels(codebook)

  positive_label <- valid_labels[1]
  negative_label <- valid_labels[length(valid_labels)]

  tier1_chunks <- c1_chunk_data$tier1
  tier2_chunks <- c1_chunk_data$tier2
  negative_chunks <- c1_chunk_data$negatives

  if (show_progress) {
    pb <- progress::progress_bar$new(
      format = "  LOOCV [:bar] :current/:total (:percent) eta: :eta",
      total = n_acts,
      clear = FALSE
    )
  }

  results <- purrr::map(seq_len(n_acts), function(i) {
    if (show_progress) pb$tick()

    fold_seed <- seed + i
    set.seed(fold_seed)

    test_act <- aligned_data[i, ]
    train_data <- aligned_data[-i, ]

    # Positive test set: Tier 1+2 chunks for this act
    act_tier1 <- tier1_chunks |>
      dplyr::filter(act_name == test_act$act_name)
    act_tier2 <- tier2_chunks |>
      dplyr::filter(act_name == test_act$act_name)

    # Generate passage-level few-shot examples from training data
    fold_examples <- generate_c1_loocv_fold_examples(
      train_data = train_data,
      negative_chunks = negative_chunks,
      n_per_class = n_few_shot,
      codebook = codebook,
      seed = fold_seed
    )

    # Classify Tier 1 chunks
    tier1_results <- classify_chunks_for_fold(
      chunks = act_tier1,
      tier = 1L,
      fold = i,
      act_name = test_act$act_name,
      year = test_act$year,
      true_label = positive_label,
      text_type = "positive",
      codebook = codebook,
      fold_examples = fold_examples,
      model = model,
      use_self_consistency = use_self_consistency,
      system_prompt = system_prompt
    )

    # Classify Tier 2 chunks
    tier2_results <- classify_chunks_for_fold(
      chunks = act_tier2,
      tier = 2L,
      fold = i,
      act_name = test_act$act_name,
      year = test_act$year,
      true_label = positive_label,
      text_type = "positive",
      codebook = codebook,
      fold_examples = fold_examples,
      model = model,
      use_self_consistency = use_self_consistency,
      system_prompt = system_prompt
    )

    # Classify negative chunk sample
    neg_sample <- negative_chunks |>
      dplyr::slice_sample(n = min(n_neg_per_fold, nrow(negative_chunks)))

    neg_results <- classify_chunks_for_fold(
      chunks = neg_sample,
      tier = NA_integer_,
      fold = i,
      act_name = NA_character_,
      year = neg_sample$year,
      true_label = negative_label,
      text_type = "negative",
      codebook = codebook,
      fold_examples = fold_examples,
      model = model,
      use_self_consistency = use_self_consistency,
      system_prompt = system_prompt
    )

    dplyr::bind_rows(tier1_results, tier2_results, neg_results)
  })

  all_results <- dplyr::bind_rows(results)

  # Summary
  pos_results <- all_results |> dplyr::filter(text_type == "positive")
  neg_results <- all_results |> dplyr::filter(text_type == "negative")

  message(sprintf("\nLOOCV complete:"))
  message(sprintf("  Positive chunks: %d (%.1f%% correct) [Tier1: %d, Tier2: %d]",
                  nrow(pos_results),
                  mean(pos_results$correct, na.rm = TRUE) * 100,
                  sum(pos_results$tier == 1, na.rm = TRUE),
                  sum(pos_results$tier == 2, na.rm = TRUE)))
  message(sprintf("  Negative chunks: %d (%.1f%% correct)",
                  nrow(neg_results),
                  mean(neg_results$correct, na.rm = TRUE) * 100))

  all_results
}


#' Classify chunks for one LOOCV fold
#'
#' Internal helper that classifies a set of chunks and returns structured results.
#'
#' @param chunks Tibble of chunks to classify (must have text column)
#' @param tier Integer tier value (1, 2, or NA for negatives)
#' @param fold Integer fold number
#' @param act_name Character act name (or NA for negatives)
#' @param year Integer or vector of years
#' @param true_label Character true label
#' @param text_type Character "positive" or "negative"
#' @param codebook Codebook object
#' @param fold_examples List of few-shot examples
#' @param model Character model ID
#' @param use_self_consistency Logical
#' @param system_prompt Character system prompt
#' @return Tibble with classification results
#' @keywords internal
classify_chunks_for_fold <- function(chunks, tier, fold, act_name, year,
                                     true_label, text_type, codebook,
                                     fold_examples, model,
                                     use_self_consistency, system_prompt) {
  positive_label <- get_valid_labels(codebook)[1]

  if (nrow(chunks) == 0) {
    return(tibble::tibble(
      fold = integer(), act_name = character(), year = integer(),
      chunk_id = integer(), doc_id = character(), tier = integer(),
      text_type = character(), true_label = character(),
      pred_label = character(), confidence = numeric(),
      reasoning = character(), correct = logical()
    ))
  }

  purrr::map_dfr(seq_len(nrow(chunks)), function(j) {
    pred <- tryCatch({
      classify_with_codebook(
        text = chunks$text[j],
        codebook = codebook,
        few_shot_examples = fold_examples,
        model = model,
        temperature = 0,
        use_self_consistency = use_self_consistency,
        system_prompt = system_prompt
      )
    }, error = function(e) {
      list(label = NA_character_, reasoning = e$message, confidence = NA_real_)
    })

    # Handle vector vs scalar year
    chunk_year <- if (length(year) == 1) year else year[j]

    tibble::tibble(
      fold = fold,
      act_name = act_name,
      year = chunk_year,
      chunk_id = chunks$chunk_id[j],
      doc_id = chunks$doc_id[j],
      tier = tier,
      text_type = text_type,
      true_label = true_label,
      pred_label = pred$label %||% NA_character_,
      confidence = pred$confidence %||% NA_real_,
      reasoning = pred$reasoning %||% NA_character_,
      correct = identical(pred$label, true_label)
    )
  })
}


#' Evaluate LOOCV results with tier-stratified metrics
#'
#' Computes combined recall (Tier 1+2), Tier 1 recall, Tier 2 recall,
#' precision, F1, and accuracy with bootstrap CIs.
#'
#' @param loocv_results Tibble from run_loocv()
#' @param codebook_type Character codebook identifier ("C1", "C2", etc.)
#' @param n_bootstrap Integer bootstrap resamples (default 1000)
#' @param ci_level Numeric confidence level (default 0.95)
#' @return List with tier-stratified metrics, CIs, confusion matrix, and errors
#' @export
evaluate_loocv <- function(loocv_results,
                           codebook_type = "C1",
                           n_bootstrap = 1000,
                           ci_level = 0.95) {

  valid_results <- loocv_results |>
    dplyr::filter(!is.na(pred_label))

  n_total <- nrow(loocv_results)
  n_valid <- nrow(valid_results)

  if (n_valid < n_total) {
    warning(sprintf("%d/%d predictions had NA labels and were excluded",
                    n_total - n_valid, n_total))
  }

  # Confusion matrix
  labels <- sort(unique(c(valid_results$true_label, valid_results$pred_label)))
  cm <- table(
    Predicted = factor(valid_results$pred_label, levels = labels),
    True = factor(valid_results$true_label, levels = labels)
  )

  # Point estimates
  metrics <- compute_binary_metrics(valid_results, labels)

  # Tier-stratified recall
  tier1_results <- valid_results |> dplyr::filter(tier == 1)
  tier2_results <- valid_results |> dplyr::filter(tier == 2)
  positive_label <- labels[1]

  tier1_recall <- if (nrow(tier1_results) > 0) {
    mean(tier1_results$pred_label == positive_label, na.rm = TRUE)
  } else NA_real_

  tier2_recall <- if (nrow(tier2_results) > 0) {
    mean(tier2_results$pred_label == positive_label, na.rm = TRUE)
  } else NA_real_

  # Bootstrap CIs
  set.seed(42)
  boot_stats <- replicate(n_bootstrap, {
    boot_idx <- sample(seq_len(n_valid), n_valid, replace = TRUE)
    boot_data <- valid_results[boot_idx, ]
    m <- compute_binary_metrics(boot_data, labels)

    # Tier-stratified recall in bootstrap
    bt1 <- boot_data |> dplyr::filter(tier == 1)
    bt2 <- boot_data |> dplyr::filter(tier == 2)
    t1r <- if (nrow(bt1) > 0) mean(bt1$pred_label == positive_label, na.rm = TRUE) else NA_real_
    t2r <- if (nrow(bt2) > 0) mean(bt2$pred_label == positive_label, na.rm = TRUE) else NA_real_

    c(recall = m$recall, precision = m$precision, f1 = m$f1,
      accuracy = m$accuracy, specificity = m$specificity,
      tier1_recall = t1r, tier2_recall = t2r)
  })

  alpha <- 1 - ci_level
  ci_lower <- apply(boot_stats, 1, quantile, probs = alpha / 2, na.rm = TRUE)
  ci_upper <- apply(boot_stats, 1, quantile, probs = 1 - alpha / 2, na.rm = TRUE)

  # Error analysis
  errors <- valid_results |>
    dplyr::filter(!correct) |>
    dplyr::select(fold, act_name, year, chunk_id, doc_id, tier,
                  text_type, true_label, pred_label,
                  confidence, reasoning) |>
    dplyr::arrange(text_type, tier, act_name)

  # Per-act recall (positive chunks only)
  act_recall <- valid_results |>
    dplyr::filter(text_type == "positive") |>
    dplyr::group_by(act_name, year) |>
    dplyr::summarize(
      n_chunks = dplyr::n(),
      n_tier1 = sum(tier == 1, na.rm = TRUE),
      n_tier2 = sum(tier == 2, na.rm = TRUE),
      n_correct = sum(correct, na.rm = TRUE),
      recall = n_correct / n_chunks,
      .groups = "drop"
    ) |>
    dplyr::arrange(recall)

  list(
    codebook_type = codebook_type,
    combined_recall = metrics$recall,
    combined_recall_ci = c(lower = ci_lower["recall"], upper = ci_upper["recall"]),
    tier1_recall = tier1_recall,
    tier1_recall_ci = c(lower = ci_lower["tier1_recall"], upper = ci_upper["tier1_recall"]),
    tier2_recall = tier2_recall,
    tier2_recall_ci = c(lower = ci_lower["tier2_recall"], upper = ci_upper["tier2_recall"]),
    precision = metrics$precision,
    precision_ci = c(lower = ci_lower["precision"], upper = ci_upper["precision"]),
    f1 = metrics$f1,
    f1_ci = c(lower = ci_lower["f1"], upper = ci_upper["f1"]),
    accuracy = metrics$accuracy,
    accuracy_ci = c(lower = ci_lower["accuracy"], upper = ci_upper["accuracy"]),
    specificity = metrics$specificity,
    specificity_ci = c(lower = ci_lower["specificity"], upper = ci_upper["specificity"]),
    confusion_matrix = cm,
    error_analysis = errors,
    act_recall = act_recall,
    n_total = n_total,
    n_valid = n_valid,
    n_tier1 = nrow(tier1_results),
    n_tier2 = nrow(tier2_results),
    ci_level = ci_level,
    n_bootstrap = n_bootstrap
  )
}


#' Compute binary classification metrics
#'
#' @param results Tibble with true_label and pred_label columns
#' @param labels Character vector of label levels (positive first)
#' @return List with recall, precision, f1, accuracy, specificity
#' @keywords internal
compute_binary_metrics <- function(results, labels) {
  positive_label <- labels[1]

  tp <- sum(results$pred_label == positive_label & results$true_label == positive_label,
            na.rm = TRUE)
  fp <- sum(results$pred_label == positive_label & results$true_label != positive_label,
            na.rm = TRUE)
  fn <- sum(results$pred_label != positive_label & results$true_label == positive_label,
            na.rm = TRUE)
  tn <- sum(results$pred_label != positive_label & results$true_label != positive_label,
            na.rm = TRUE)

  recall <- if (tp + fn > 0) tp / (tp + fn) else NA_real_

  precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
  f1 <- if (!is.na(precision) && !is.na(recall) && precision + recall > 0) {
    2 * (precision * recall) / (precision + recall)
  } else {
    NA_real_
  }
  accuracy <- (tp + tn) / (tp + fp + fn + tn)
  specificity <- if (tn + fp > 0) tn / (tn + fp) else NA_real_

  list(
    recall = recall,
    precision = precision,
    f1 = f1,
    accuracy = accuracy,
    specificity = specificity,
    tp = tp, fp = fp, fn = fn, tn = tn
  )
}


# Null coalescing operator
if (!exists("%||%", mode = "function", envir = environment())) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
