# Statutory tax-shock dataset assembly.
#
# Pipeline tail for the per-instrument agentic identification skills
# (identify-cit / identify-pit / identify-vat). The skills + human review freeze
# one hand-curated reference dataset per instrument to
# data/validated/{ISO}_{INSTRUMENT}_shocks.qs (see docs/phase_1/tax_shock_schema.md).
# This file binds those frozen datasets, assembles a C2a evidence bundle per
# shock (reusing existing country C2a evidence, re-running C2a only on the corpus
# chunks C1 omitted), runs the validated C2b classifier, and assembles the final
# deliverable.
#
# Reuses, unchanged: run_c2a_deployment() (R/run_c2a_deployment.R),
# run_c2b_deployment() (R/run_c2b_deployment.R). The emitted bundle matches the
# aggregate_c0_acts_deployment() schema (R/run_c0_deployment.R) so C2b runs
# byte-for-byte the same way it does in the main deployment chain.

if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

# Modal integer (first on ties); NA-safe. Local copy to avoid cross-file coupling.
.tax_mode_int <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(NA_integer_)
  ux <- unique(x)
  as.integer(ux[which.max(tabulate(match(x, ux)))])
}

# The frozen-dataset contract (docs/phase_1/tax_shock_schema.md). Scalar columns
# every per-instrument file must carry; list-cols are validated separately.
.tax_shock_required_cols <- c(
  "shock_id", "country", "country_iso", "act_label", "instrument_type",
  "tax_type", "direction", "rate_from", "rate_to", "delta_pp", "magnitude_note",
  "announced_year", "effective_year", "effective_quarter",
  "phased_schedule", "exogenous_preliminary", "exogeneity_quote", "id_reasoning",
  "member_chunks", "recovered_chunks", "recovered_evidence", "sources",
  "recall_scorecard"
)


#' Bind the frozen per-instrument tax-shock datasets
#'
#' Reads each `data/validated/{ISO}_{INSTRUMENT}_shocks.qs`, row-binds them,
#' validates the shared contract, assigns a per-row integer `cluster_id` (for
#' C2b metadata parity), and checks `shock_id` uniqueness. Empty-input safe:
#' returns a 0-row tibble with the contract columns when given no files.
#'
#' @param files Character vector of `.qs` file paths (e.g. `tax_shock_files$path`).
#' @return One tibble, all instruments row-bound, plus an integer `cluster_id`.
#' @export
bind_tax_shocks <- function(files) {
  files <- files[!is.na(files)]
  files <- files[file.exists(files)]

  if (length(files) == 0L) {
    return(tibble::tibble(
      shock_id = character(0), country = character(0), country_iso = character(0),
      act_label = character(0), instrument_type = character(0),
      tax_type = character(0), direction = character(0),
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

  missing <- setdiff(.tax_shock_required_cols, names(shocks))
  if (length(missing) > 0L) {
    stop(sprintf(
      "bind_tax_shocks: frozen dataset(s) missing contract column(s): %s\nSee docs/phase_1/tax_shock_schema.md",
      paste(missing, collapse = ", ")
    ))
  }

  if (anyDuplicated(shocks$shock_id) > 0L) {
    dups <- shocks$shock_id[duplicated(shocks$shock_id)]
    stop(sprintf(
      "bind_tax_shocks: duplicate shock_id(s) across instruments: %s",
      paste(unique(dups), collapse = ", ")
    ))
  }

  shocks |> dplyr::mutate(cluster_id = dplyr::row_number())
}


#' Assemble a per-shock C2a evidence bundle (reuse + re-run C2a on omitted chunks)
#'
#' For each shock, gathers its `member_chunks`, attaches existing C2a evidence by
#' (`doc_id`,`chunk_id`), and for any member chunk that has **no** existing
#' evidence (the chunks C1 never surfaced as a measure), pulls the chunk text
#' from `chunks` and runs `run_c2a_deployment()` with the shock's `act_label` as
#' the measure name. Any `recovered_evidence` direct quotes are folded in as
#' synthetic C2a records. The output matches `aggregate_c0_acts_deployment()`'s
#' schema, with `act_name = shock_id`, so `run_c2b_deployment()` consumes it
#' unchanged.
#'
#' The C2a re-run is keyed on **distinct** missing (`doc_id`,`chunk_id`) pairs: a
#' chunk shared by two shocks is extracted once (under one shock's label) and the
#' evidence joined back to every member row. This is an accepted approximation
#' (documented in docs/phase_1/tax_shock_schema.md) and is rare in practice.
#'
#' @param shocks Bound tibble from `bind_tax_shocks()`.
#' @param c2a_evidence Existing country C2a evidence (bind of `country_c2a_evidence`);
#'   columns include `doc_id`, `chunk_id`, `evidence`, `enacted_signals`,
#'   `timing_signals`, `c2a_valid`.
#' @param chunks Country chunk text (bind of `country_chunks`); columns include
#'   `doc_id`, `chunk_id`, `text`, `year`, and (optionally) `country`.
#' @param c2a_codebook Validated C2a codebook (`load_validate_codebook()`).
#' @param model,max_tokens_c2a,provider,base_url,api_key Passed to
#'   `run_c2a_deployment()`.
#' @return Tibble in the `aggregate_c0_acts_deployment()` schema (one row per
#'   shock × evidence-bearing chunk).
#' @export
assemble_shock_evidence <- function(shocks, c2a_evidence, chunks,
                                    c2a_codebook,
                                    model = "claude-haiku-4-5-20251001",
                                    max_tokens_c2a = 16384,
                                    provider = "anthropic",
                                    base_url = NULL,
                                    api_key = NULL) {

  empty <- tibble::tibble(
    act_name = character(0), year = integer(0),
    act_name_year = integer(0), doc_year_modal = integer(0),
    canonical_name = character(0), cluster_id = integer(0),
    chunk_id = integer(0), doc_id = character(0), measure_name = character(0),
    evidence = list(), enacted_signals = list(), timing_signals = list(),
    c2a_valid = logical(0)
  )
  if (nrow(shocks) == 0L) return(empty)

  # Per-shock act-level metadata (the C2b grouping keys + inventory fields).
  shock_meta <- shocks |>
    dplyr::transmute(
      shock_id,
      act_name       = shock_id,
      canonical_name = act_label,
      cluster_id,
      act_name_year  = as.integer(effective_year),
      year           = as.integer(dplyr::coalesce(effective_year, announced_year))
    )

  # One row per (shock, member chunk).
  members <- shocks |>
    dplyr::select(shock_id, member_chunks) |>
    tidyr::unnest(member_chunks)

  ev_cols <- c("doc_id", "chunk_id", "evidence", "enacted_signals",
               "timing_signals", "c2a_valid")
  ev <- if (nrow(c2a_evidence) == 0L) {
    tibble::tibble(doc_id = character(0), chunk_id = integer(0),
                   evidence = list(), enacted_signals = list(),
                   timing_signals = list(), c2a_valid = logical(0))
  } else {
    c2a_evidence |> dplyr::select(dplyr::all_of(ev_cols)) |>
      dplyr::distinct(doc_id, chunk_id, .keep_all = TRUE)
  }

  have <- members |> dplyr::inner_join(ev, by = c("doc_id", "chunk_id"))
  missing <- members |> dplyr::anti_join(ev, by = c("doc_id", "chunk_id"))

  # --- C2a re-run on the omitted chunks (distinct doc_id × chunk_id) ----------
  fresh <- empty[0, c("doc_id", "chunk_id", "evidence", "enacted_signals",
                      "timing_signals", "c2a_valid")] |>
    dplyr::mutate(shock_id = character(0))

  if (nrow(missing) > 0L) {
    miss_distinct <- missing |>
      dplyr::distinct(doc_id, chunk_id, .keep_all = TRUE) |>
      dplyr::left_join(dplyr::select(shock_meta, shock_id, canonical_name, year),
                       by = "shock_id") |>
      dplyr::left_join(
        chunks |> dplyr::select(doc_id, chunk_id, text,
                                chunk_year = year,
                                dplyr::any_of("country")),
        by = c("doc_id", "chunk_id")
      )

    c1_like <- miss_distinct |>
      dplyr::filter(!is.na(text)) |>
      dplyr::transmute(
        chunk_id, doc_id,
        country      = if ("country" %in% names(miss_distinct)) country else NA_character_,
        year         = as.integer(dplyr::coalesce(year, chunk_year)),
        measure_name = canonical_name,
        text
      )

    n_no_text <- sum(is.na(miss_distinct$text))
    if (n_no_text > 0L) {
      warning(sprintf(
        "assemble_shock_evidence: %d omitted chunk(s) had no text in `chunks` and were dropped from the C2a re-run",
        n_no_text
      ))
    }

    if (nrow(c1_like) > 0L) {
      message(sprintf(
        "assemble_shock_evidence: re-running C2a on %d omitted chunk(s) C1 did not surface",
        nrow(c1_like)
      ))
      c2a_new <- run_c2a_deployment(
        c1_like, c2a_codebook, model = model, max_tokens_c2a = max_tokens_c2a,
        provider = provider, base_url = base_url, api_key = api_key
      )
      fresh <- missing |>
        dplyr::left_join(
          c2a_new |> dplyr::select(dplyr::all_of(ev_cols)),
          by = c("doc_id", "chunk_id")
        )
    }
  }

  # --- Recovered direct quotes (events with no usable chunk) ------------------
  rec <- shocks |>
    dplyr::select(shock_id, recovered_evidence) |>
    tidyr::unnest(recovered_evidence)

  rec_rows <- if (nrow(rec) == 0L || !all(c("quote", "signal") %in% names(rec))) {
    empty[0, ] |> dplyr::mutate(shock_id = character(0)) |>
      dplyr::select(shock_id, doc_id, chunk_id, evidence, enacted_signals,
                    timing_signals, c2a_valid)
  } else {
    rec |>
      dplyr::transmute(
        shock_id,
        doc_id          = NA_character_,
        chunk_id        = NA_integer_,
        evidence        = purrr::map2(quote, signal, ~ list(list(quote = .x, signal = .y))),
        enacted_signals = purrr::map(seq_len(dplyr::n()), ~ list()),
        timing_signals  = purrr::map(seq_len(dplyr::n()), ~ list()),
        c2a_valid       = TRUE
      )
  }

  # --- Combine and emit the aggregate_c0_acts_deployment() schema -------------
  combined <- dplyr::bind_rows(have, fresh, rec_rows) |>
    dplyr::filter(!is.na(c2a_valid))

  if (nrow(combined) == 0L) return(empty)

  doc_modal <- combined |>
    dplyr::left_join(dplyr::select(chunks, doc_id, chunk_id, chunk_year = year),
                     by = c("doc_id", "chunk_id")) |>
    dplyr::group_by(shock_id) |>
    dplyr::summarize(doc_year_modal = .tax_mode_int(chunk_year), .groups = "drop")

  combined |>
    dplyr::left_join(shock_meta, by = "shock_id") |>
    dplyr::left_join(doc_modal, by = "shock_id") |>
    dplyr::mutate(
      measure_name   = canonical_name,
      doc_year_modal = dplyr::coalesce(doc_year_modal, year)
    ) |>
    dplyr::select(act_name, year, act_name_year, doc_year_modal,
                  canonical_name, cluster_id, chunk_id, doc_id, measure_name,
                  evidence, enacted_signals, timing_signals, c2a_valid)
}


#' Classify the per-shock evidence bundles with the validated C2b codebook
#'
#' Thin wrapper over `run_c2b_deployment()` (C2b v0.9.1, frozen). The bundle's
#' `act_name` is the unique `shock_id`, so each shock is one classified row.
#' Empty-input safe.
#'
#' @param bundles Tibble from `assemble_shock_evidence()`.
#' @param c2b_codebook Validated C2b codebook object.
#' @param model,max_tokens_c2b,provider,base_url,api_key Passed through.
#' @return `run_c2b_deployment()` output (one row per shock), with `shock_id`.
#' @export
run_c2b_on_shocks <- function(bundles, c2b_codebook,
                              model = "claude-haiku-4-5-20251001",
                              max_tokens_c2b = 4096L,
                              provider = "anthropic",
                              base_url = NULL,
                              api_key = NULL) {
  out <- run_c2b_deployment(
    bundles, c2b_codebook, model = model, max_tokens_c2b = max_tokens_c2b,
    provider = provider, base_url = base_url, api_key = api_key
  )
  out |> dplyr::mutate(shock_id = act_name, .before = 1)
}


#' Assemble the final statutory tax-change deliverable
#'
#' Joins the C2b classification (`pred_label`, `pred_exogenous`, `pred_sign`,
#' `enacted`, `confidence`, motivation `reasoning`) onto the identified shocks by
#' `shock_id`. Both the preliminary narrative read (`exogenous_preliminary`,
#' `exogeneity_quote`) and C2b's verdict are kept side by side — neither
#' overwrites the other (the preliminary read is pending expert adjudication).
#'
#' @param shocks Bound tibble from `bind_tax_shocks()`.
#' @param c2b_out Tibble from `run_c2b_on_shocks()`.
#' @return The deliverable tibble: identification columns + C2b motivation/sign/
#'   exogeneity, one row per shock. List-cols (`member_chunks`, `sources`, etc.)
#'   are carried through.
#' @export
assemble_tax_shock_deliverable <- function(shocks, c2b_out) {
  c2b_cols <- c2b_out |>
    dplyr::select(
      shock_id,
      c2b_label      = pred_label,
      c2b_exogenous  = pred_exogenous,
      c2b_sign       = pred_sign,
      c2b_sign_raw   = pred_sign_raw,
      c2b_enacted    = enacted,
      c2b_confidence = confidence,
      c2b_reasoning  = reasoning,
      c2b_stop_reason,
      n_chunks, n_evidence_items
    )

  shocks |>
    dplyr::left_join(c2b_cols, by = "shock_id") |>
    dplyr::relocate(c2b_label, c2b_exogenous, c2b_sign, c2b_sign_raw, c2b_enacted,
                    c2b_confidence, c2b_reasoning, c2b_stop_reason,
                    .after = exogeneity_quote)
}
