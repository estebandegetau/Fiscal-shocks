#' Assemble C1-classified chunks with text and ground truth labels
#'
#' Merges C1 S2 classification outputs with chunk text and act-level ground
#' truth labels from aligned_data. Produces one row per classified chunk that
#' belongs to a labeled act. Negatives and chunks for unlabeled acts are
#' dropped via inner join on act_name.
#'
#' @param c1_s2_results Tibble from run_zero_shot() with C1 classifications
#' @param chunks Tibble from make_chunks() with chunk text
#' @param aligned_data Tibble from align_labels_shocks() with act-level labels
#' @return Tibble with one row per classified chunk: C1 outputs + text + labels
#' @export
assemble_c1_classified_chunks <- function(c1_s2_results, chunks, aligned_data) {

  # Select C1 classification outputs
  classified <- c1_s2_results |>
    dplyr::select(
      chunk_id, doc_id, act_name, year, tier,
      pred_label, discusses_motivation, discusses_timing, discusses_magnitude,
      reasoning
    )

  # Join chunk text
  chunk_text <- chunks |>
    dplyr::select(doc_id, chunk_id, text, approx_tokens)

  classified <- classified |>
    dplyr::left_join(chunk_text, by = c("doc_id", "chunk_id"))

  n_missing_text <- sum(is.na(classified$text))
  if (n_missing_text > 0) {
    warning(sprintf(
      "assemble_c1_classified_chunks: %d chunks have no text after join",
      n_missing_text
    ))
  }

  # Join ground truth labels from aligned_data (inner join drops negatives)
  labels <- aligned_data |>
    dplyr::select(act_name, motivation_category, exogenous_flag) |>
    dplyr::distinct()

  result <- classified |>
    dplyr::inner_join(labels, by = "act_name")

  message(sprintf(
    "C1 classified chunks assembled: %d chunks across %d acts (%d FISCAL_MEASURE, %d NOT_FISCAL_MEASURE)",
    nrow(result),
    dplyr::n_distinct(result$act_name),
    sum(result$pred_label == "FISCAL_MEASURE", na.rm = TRUE),
    sum(result$pred_label == "NOT_FISCAL_MEASURE", na.rm = TRUE)
  ))

  result
}


#' Assemble C2 input data from C1-classified chunks
#'
#' Filters C1-classified chunks to those predicted as FISCAL_MEASURE with
#' discusses_motivation == TRUE. Returns individual chunks ready for C2
#' motivation classification — no concatenation, no sampling.
#'
#' @param c1_classified_chunks Tibble from assemble_c1_classified_chunks()
#' @return Tibble of filtered chunks for C2 input
#' @export
assemble_c2_input_data <- function(c1_classified_chunks) {

  result <- c1_classified_chunks |>
    dplyr::filter(
      pred_label == "FISCAL_MEASURE",
      discusses_motivation == TRUE
    )

  n_acts_before <- dplyr::n_distinct(c1_classified_chunks$act_name)
  n_acts_after <- dplyr::n_distinct(result$act_name)
  lost_acts <- setdiff(
    unique(c1_classified_chunks$act_name),
    unique(result$act_name)
  )

  if (length(lost_acts) > 0) {
    warning(sprintf(
      "assemble_c2_input_data: %d act(s) lost all chunks after filtering: %s",
      length(lost_acts),
      paste(lost_acts, collapse = ", ")
    ))
  }

  message(sprintf(
    "C2 input data: %d chunks across %d/%d acts (filtered from %d classified chunks)",
    nrow(result),
    n_acts_after, n_acts_before,
    nrow(c1_classified_chunks)
  ))

  result
}
