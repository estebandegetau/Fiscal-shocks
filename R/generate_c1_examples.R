# C1-Specific Data Helpers: Chunk-Based Negative Generation and Few-Shot Formatting
#
# Generates negative examples from chunks for C1 (Measure Identification)
# and formats LOOCV fold examples (passage-level few-shot, chunk-level input).

#' Generate negative chunk examples for C1
#'
#' Samples clean negative chunks from the chunk tier data, stratified by
#' document source type (ERP, Budget, Treasury).
#'
#' @param c1_chunk_data List from prepare_c1_chunk_data() with negatives component
#' @param n Integer total number of negative examples (default 200)
#' @param seed Integer random seed (default 20251206)
#' @return Tibble with columns: chunk_id, doc_id, text, year, source_type, approx_tokens
#' @export
generate_c1_negative_examples <- function(c1_chunk_data,
                                           n = 200,
                                           seed = 20251206) {
  set.seed(seed)

  negatives <- c1_chunk_data$negatives

  if (nrow(negatives) == 0) {
    warning("No negative chunks available")
    return(tibble::tibble(
      chunk_id = integer(), doc_id = character(), text = character(),
      year = integer(), source_type = character(), approx_tokens = numeric()
    ))
  }

  if (nrow(negatives) < n) {
    message(sprintf("Warning: Only %d negative chunks available (requested %d)",
                    nrow(negatives), n))
    n <- nrow(negatives)
  }

  # Stratified sampling by source_type
  source_counts <- negatives |>
    dplyr::count(source_type) |>
    dplyr::mutate(target_n = pmax(1, round(n * (n / sum(n)))))

  # Adjust target_n to sum to n
  source_counts$target_n <- round(n * source_counts$n / sum(source_counts$n))
  diff <- n - sum(source_counts$target_n)
  if (diff != 0) {
    # Add/subtract from the largest group
    idx <- which.max(source_counts$n)
    source_counts$target_n[idx] <- source_counts$target_n[idx] + diff
  }

  sampled <- purrr::map2_dfr(
    source_counts$source_type,
    source_counts$target_n,
    function(st, target) {
      pool <- negatives |> dplyr::filter(source_type == st)
      pool |> dplyr::slice_sample(n = min(target, nrow(pool)))
    }
  )

  message(sprintf("Generated %d C1 negative chunk examples:", nrow(sampled)))
  type_counts <- sampled |>
    dplyr::count(source_type) |>
    dplyr::mutate(pct = round(n / sum(n) * 100, 1))
  for (i in seq_len(nrow(type_counts))) {
    message(sprintf("  %s: %d (%.1f%%)",
                    type_counts$source_type[i],
                    type_counts$n[i],
                    type_counts$pct[i]))
  }

  sampled |>
    dplyr::select(chunk_id, doc_id, text, year, source_type, approx_tokens)
}


#' Generate few-shot examples for one LOOCV fold (C1)
#'
#' For a given LOOCV fold, samples passage-level positive examples from
#' training acts and short negative passages extracted from negative chunks.
#' Few-shot examples are kept short (passage-level) even though test inputs
#' are full chunks, matching the production pattern where the model sees
#' short examples showing what to look for and classifies long documents.
#'
#' @param train_data Tibble with training acts (all acts except held-out).
#'   Must have columns: act_name, passages_text, n_passages
#' @param negative_chunks Tibble of negative chunks (from c1_chunk_data$negatives)
#' @param n_per_class Integer number of examples per class (default 5)
#' @param codebook A validated codebook object
#' @param seed Integer random seed for this fold
#' @return List of few-shot examples with input/output structure
#' @export
generate_c1_loocv_fold_examples <- function(train_data,
                                             negative_chunks,
                                             n_per_class = 5,
                                             codebook,
                                             seed) {
  set.seed(seed)

  examples_list <- list()

  # Positive examples: sample individual passages from training acts
  # (passage-level, not full chunks — keeps few-shot context manageable)
  positive_pool <- train_data |>
    dplyr::select(act_name, passages_text) |>
    dplyr::mutate(
      passages = stringr::str_split(passages_text, "\n\n")
    ) |>
    tidyr::unnest(passages) |>
    dplyr::filter(nchar(stringr::str_trim(passages)) > 50) |>
    dplyr::mutate(text = stringr::str_trim(passages))

  n_pos <- min(n_per_class, nrow(positive_pool))
  if (n_pos > 0) {
    sampled_pos <- positive_pool |>
      dplyr::slice_sample(n = n_pos)

    for (i in seq_len(nrow(sampled_pos))) {
      row <- sampled_pos[i, ]
      examples_list[[length(examples_list) + 1]] <- list(
        input = row$text,
        output = list(
          label = "FISCAL_MEASURE",
          measure_name = row$act_name,
          reasoning = sprintf(
            "This passage describes the %s, an enacted fiscal measure with substantive detail about its provisions.",
            row$act_name
          )
        )
      )
    }
  }

  # Negative examples: extract short passages from negative chunks
  # (not full chunks — keep few-shot examples compact)
  n_neg <- min(n_per_class, nrow(negative_chunks))
  if (n_neg > 0) {
    sampled_neg <- negative_chunks |>
      dplyr::slice_sample(n = n_neg)

    for (i in seq_len(nrow(sampled_neg))) {
      row <- sampled_neg[i, ]
      # Extract first 1-2 paragraphs as a short passage
      paragraphs <- stringr::str_split(row$text, "\n\n+")[[1]]
      paragraphs <- paragraphs[nchar(stringr::str_trim(paragraphs)) > 50]
      short_passage <- if (length(paragraphs) > 0) {
        paste(head(paragraphs, 2), collapse = "\n\n")
      } else {
        substr(row$text, 1, 500)
      }

      examples_list[[length(examples_list) + 1]] <- list(
        input = short_passage,
        output = list(
          label = "NOT_FISCAL_MEASURE",
          measure_name = NULL,
          reasoning = "This passage does not describe a specific enacted fiscal measure with substantive detail about its provisions."
        )
      )
    }
  }

  examples_list
}
