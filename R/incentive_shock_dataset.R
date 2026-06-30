# Tax-incentive / holiday shock dataset assembly (bind step only).
#
# Incentive-side analogue of R/tax_shock_dataset.R and R/spending_shock_dataset.R.
# The `identify-incentives` skill + human review freeze one hand-curated reference
# dataset per country to data/validated/{ISO}_INCENTIVE_shocks.qs (see
# docs/phase_1/incentive_shock_schema.md). This file provides the ONLY
# incentive-specific pipeline function -- `bind_incentive_shocks()` -- which
# row-binds those frozen datasets and validates the incentive contract. The rest
# of the tail is REUSED UNCHANGED from R/tax_shock_dataset.R:
#   - assemble_shock_evidence()         (C2a reuse + re-run on omitted chunks)
#   - run_c2b_on_shocks()               (frozen C2b v0.9.1)
#   - assemble_tax_shock_deliverable()  (join preliminary + C2b reads side by side)
# Those three are generic over the contract (they touch only member_chunks,
# recovered_evidence, act_label, shock_id, exogeneity_quote -- all shared, plus a
# left_join that preserves every input column including incentive_category), so the
# incentive_* targets call them directly.

# The frozen incentive-dataset contract (docs/phase_1/incentive_shock_schema.md).
# This is the TAX contract plus `incentive_category` (rate fields stay meaningful,
# unlike spending). Scalar columns every frozen file must carry; list-cols are
# validated by binding (they must bind).
.incentive_shock_required_cols <- c(
  "shock_id", "country", "country_iso", "act_label", "instrument_type",
  "tax_type", "incentive_category", "direction",
  "rate_from", "rate_to", "delta_pp", "magnitude_note",
  "announced_year", "effective_year", "effective_quarter",
  "phased_schedule", "exogenous_preliminary", "exogeneity_quote", "id_reasoning",
  "member_chunks", "recovered_chunks", "recovered_evidence", "sources",
  "recall_scorecard"
)


#' Bind the frozen per-country tax-incentive shock datasets
#'
#' Reads each `data/validated/{ISO}_INCENTIVE_shocks.qs`, row-binds them, validates
#' the incentive contract (`.incentive_shock_required_cols`), assigns a per-row
#' integer `cluster_id` (for C2b metadata parity), and checks `shock_id`
#' uniqueness. Parallel to `bind_spending_shocks()` but with `incentive_category` in
#' the contract; like the spending bind it does **no** `delta_pp`/`direction`
#' sign-consistency check (rate fields are `NA` for non-rate incentives such as
#' holidays and allowances). Empty-input safe: returns a 0-row tibble with the
#' contract columns when given no files, so the downstream chain is inert until the
#' first frozen file exists.
#'
#' @param files Character vector of `.qs` file paths (e.g. `incentive_shock_files$path`).
#' @return One tibble, all countries row-bound, plus an integer `cluster_id`.
#' @export
bind_incentive_shocks <- function(files) {
  files <- files[!is.na(files)]
  files <- files[file.exists(files)]

  if (length(files) == 0L) {
    return(tibble::tibble(
      shock_id = character(0), country = character(0), country_iso = character(0),
      act_label = character(0), instrument_type = character(0),
      tax_type = character(0), incentive_category = character(0),
      direction = character(0),
      rate_from = double(0), rate_to = double(0), delta_pp = double(0),
      magnitude_note = character(0),
      announced_year = integer(0), effective_year = integer(0),
      effective_quarter = character(0), phased_schedule = list(),
      exogenous_preliminary = character(0), exogeneity_quote = character(0),
      id_reasoning = character(0), member_chunks = list(),
      recovered_chunks = list(), recovered_evidence = list(), sources = list(),
      recall_scorecard = list(), cluster_id = integer(0)
    ))
  }

  shocks <- purrr::map(files, qs2::qs_read) |> dplyr::bind_rows()

  missing <- setdiff(.incentive_shock_required_cols, names(shocks))
  if (length(missing) > 0L) {
    stop(sprintf(
      "bind_incentive_shocks: frozen dataset(s) missing contract column(s): %s\nSee docs/phase_1/incentive_shock_schema.md",
      paste(missing, collapse = ", ")
    ))
  }

  if (anyDuplicated(shocks$shock_id) > 0L) {
    dups <- shocks$shock_id[duplicated(shocks$shock_id)]
    stop(sprintf(
      "bind_incentive_shocks: duplicate shock_id(s) across files: %s",
      paste(unique(dups), collapse = ", ")
    ))
  }

  shocks |> dplyr::mutate(cluster_id = dplyr::row_number())
}
