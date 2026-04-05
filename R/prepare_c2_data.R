#' Assemble act-level data for C2 (Motivation Classification)
#'
#' Aggregates C1 chunk data by act, concatenating chunk texts into a single
#' input per act. Simulates what C2 would receive in production after C1
#' identifies relevant chunks. Joins motivation labels from aligned_data.
#'
#' @param c1_chunk_data List from assemble_c1_chunk_data() with $tier1, $tier2
#' @param aligned_data Tibble from align_labels_shocks() with act-level labels
#' @param n_tier2_per_act Max Tier 2 chunks per act (NULL = no cap)
#' @param seed RNG seed for Tier 2 sampling
#' @return Tibble with one row per act
assemble_c2_act_data <- function(c1_chunk_data, aligned_data,
                                  n_tier2_per_act = 20L, seed = 20251206L) {

  tier1 <- c1_chunk_data$tier1 |>
    dplyr::select(chunk_id, doc_id, act_name, year, text) |>
    dplyr::mutate(tier = 1L)

  tier2 <- c1_chunk_data$tier2 |>
    dplyr::select(chunk_id, doc_id, act_name, year, text) |>
    dplyr::mutate(tier = 2L)

  # Cap Tier 2 per act if requested
  if (!is.null(n_tier2_per_act)) {
    set.seed(seed)
    tier2 <- tier2 |>
      dplyr::group_by(act_name) |>
      dplyr::mutate(.rand = runif(dplyr::n())) |>
      dplyr::arrange(.rand, .by_group = TRUE) |>
      dplyr::slice_head(n = n_tier2_per_act) |>
      dplyr::ungroup() |>
      dplyr::select(-".rand")
  }

  # Combine and aggregate by act
  act_data <- dplyr::bind_rows(tier1, tier2) |>
    dplyr::group_by(act_name) |>
    dplyr::summarise(
      n_tier1 = sum(tier == 1L),
      n_tier2 = sum(tier == 2L),
      n_chunks_used = dplyr::n(),
      assembled_text = paste(text, collapse = "\n\n---\n\n"),
      .groups = "drop"
    ) |>
    dplyr::mutate(approx_tokens = round(nchar(assembled_text) / 4))

  # Join ground truth labels from aligned_data
  labels <- aligned_data |>
    dplyr::select(act_name, year, motivation_category, exogenous_flag)

  act_data <- act_data |>
    dplyr::inner_join(labels, by = "act_name") |>
    dplyr::select(
      act_name, year, motivation_category, exogenous_flag,
      assembled_text, n_chunks_used, n_tier1, n_tier2, approx_tokens
    )

  message(sprintf(
    "C2 act data assembled: %d acts, %d-%d tokens (median %d), %d total chunks",
    nrow(act_data),
    min(act_data$approx_tokens), max(act_data$approx_tokens),
    stats::median(act_data$approx_tokens),
    sum(act_data$n_chunks_used)
  ))

  act_data
}
