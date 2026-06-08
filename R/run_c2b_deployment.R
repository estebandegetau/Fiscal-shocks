# C2b Motivation Classification — production deployment wrapper
#
# Final step of the main per-country deployment chain. Classifies every C0
# canonical act (one prompt per act with all of its C2a evidence aggregated)
# into a motivation label, sign, and exogeneity verdict.
#
# Thin wrapper over run_c2b_classification() (R/c2_codebook_stage_2.R), which
# already groups c2a_results by (act_name, year) and unlists the evidence into a
# single prompt per act. Deployment-specific decisions hardcoded here: an all-NA
# stub test_set (Malaysia / SEA countries have no ground-truth labels) and
# threading the act-level metadata back onto the results. Mirrors
# run_malay_er_c2b() (R/malay_consistency.R) minus the EN/BM scope metadata.


#' Run C2b on the per-country C0 act inputs (every act classified)
#'
#' `run_c2b_classification()` inner-joins `test_set` on `act_name`, so the stub
#' must cover every act in `c2b_inputs` or acts get silently dropped — we build
#' it from the same input via `distinct(act_name, year)`. Act-level metadata
#' (canonical_name, cluster_id, the two timing-year sources) is threaded back
#' onto the per-act results for the deliverable inventory.
#'
#' Empty-input safe.
#'
#' @param c2b_inputs Tibble from `aggregate_c0_acts_deployment()`.
#' @param c2b_codebook Validated C2b codebook object.
#' @param model,max_tokens_c2b,provider,base_url,api_key Passed through to
#'   `run_c2b_classification()`.
#' @return `run_c2b_classification()` output plus canonical_name, cluster_id,
#'   act_name_year, doc_year_modal columns.
#' @export
run_c2b_deployment <- function(c2b_inputs,
                               c2b_codebook,
                               model = "claude-haiku-4-5-20251001",
                               max_tokens_c2b = 4096L,
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL) {

  empty <- tibble::tibble(
    act_name = character(0), year = integer(0),
    true_motivation = character(0), true_exogenous = logical(0),
    true_sign = character(0),
    pred_label = character(0), pred_exogenous = logical(0),
    pred_sign = character(0), pred_sign_raw = character(0),
    enacted = logical(0), confidence = character(0),
    evidence_raw = list(), enacted_signals_raw = list(),
    timing_signals_raw = list(),
    c2b_raw_response = character(0), reasoning = character(0),
    n_chunks = integer(0), n_evidence_items = integer(0),
    n_timing_signals = integer(0), n_c2a_failures = integer(0),
    canonical_name = character(0), cluster_id = integer(0),
    act_name_year = integer(0), doc_year_modal = integer(0)
  )
  if (nrow(c2b_inputs) == 0L) return(empty)

  stub_test_set <- c2b_inputs |>
    dplyr::distinct(act_name, year) |>
    dplyr::mutate(
      true_motivation = NA_character_,
      true_exogenous  = NA,
      true_sign       = NA_character_,
      true_quarters   = NA_character_
    )

  c2b_results <- run_c2b_classification(
    c2b_codebook = c2b_codebook,
    c2a_results = c2b_inputs,
    test_set = stub_test_set,
    model = model,
    max_tokens_c2b = max_tokens_c2b,
    provider = provider,
    base_url = base_url,
    api_key = api_key
  )

  act_meta <- c2b_inputs |>
    dplyr::distinct(act_name, canonical_name, cluster_id,
                    act_name_year, doc_year_modal)

  c2b_results |>
    dplyr::left_join(act_meta, by = "act_name")
}
