# Statutory Tax-Shock Dataset — Shared Output Contract

This document is the **single source of truth** for the columns of the frozen
per-instrument tax-shock datasets produced by the `identify-cit`, `identify-pit`,
and `identify-vat` skills. The three skills are self-contained (their procedures
are duplicated, by design), so this contract is what keeps their outputs
row-compatible and lets `bind_tax_shocks()` (`R/tax_shock_dataset.R`) bind them
without surprises.

If you change a column here, update all three skills and `R/tax_shock_dataset.R`
in the same pass (Workflow Convention #11: grep before editing).

## Reproducibility framing

The agentic identification pass is **not a pure function**, so it does not live
in a `tar_target` command. Each frozen dataset is a **hand-curated reference
input** — analogous to `data/raw/us_shocks.csv` — produced by the skill +
provenance notebook + human stamp, then read back into the pipeline through a
file target. The *target* is the frozen output; the notebook documents provenance.
See `docs/deltas.md` (2026-06-25 carve-out).

## Grain

**One row per (narratively-announced act × tax_type).** A phased multi-step act
(e.g. the 2007–2009 CIT cut 28→27→26→25) is a **single row**; the per-step
schedule lives in `phased_schedule`. An omnibus act that changes two taxes
produces **two rows** (one per `tax_type`), each with its own `shock_id`.

## Persistence

- File: `data/validated/{ISO}_{INSTRUMENT}_shocks.qs` (qs2; handles list-columns).
  `INSTRUMENT` ∈ {`CIT`, `PIT`, `CONSUMPTION`}. Example: `data/validated/MY_CIT_shocks.qs`.
- Sidecar: `data/validated/{ISO}_{INSTRUMENT}_shocks_meta.yml` (git hash + date +
  skill version + human reviewer), written the same way `R/freeze_results.R` writes meta.

## Columns

Scalar columns unless marked **list-col**. List-cols hold a tibble (data frame)
per row so they `tidyr::unnest()` cleanly.

| Column | Type | Notes |
|---|---|---|
| `shock_id` | chr | Unique within and across instruments, e.g. `MY-CIT-01`. Used as the C2b `act_name` grouping key (guaranteed unique, so no cluster-suffix trick needed). |
| `country` | chr | Lower-case slug, e.g. `malaysia`. |
| `country_iso` | chr | e.g. `MY`. |
| `act_label` | chr | Human-readable act/event name, e.g. `Corporate income tax rate reduction (Budget 2007)`. Carried through as `canonical_name` for the inventory. |
| `instrument_type` | chr | {`Tax`, `Expenditure`, `Incentive`}. These three skills emit `Tax`; enum kept general for later additions. |
| `tax_type` | chr | {`CIT`, `PIT`, `CONSUMPTION`, `NA`}. `CONSUMPTION` = VAT/GST/SST (country-agnostic). |
| `direction` | chr | {`Cut`, `Hike`, `Neutral`}. Must be consistent with `delta_pp` sign. |
| `rate_from` | dbl | Statutory rate before the change (percent, e.g. `28`). `NA` if not a rate change. |
| `rate_to` | dbl | Statutory rate after the change. `NA` if not a rate change. |
| `delta_pp` | dbl | `rate_to - rate_from` (percentage points). `NA` if non-rate. |
| `magnitude_note` | chr | Free text for revenue estimates or non-rate magnitude (e.g. one-off levy size). |
| `announced_year` | int | Year the act was announced (budget year). |
| `effective_year` | int | Year of assessment / year the change took effect. |
| `effective_quarter` | chr | e.g. `2016Q1`; `NA` when only year is known. |
| `phased_schedule` | **list-col** | tibble{`step_year` int, `step_rate` dbl}; one row per phase step. Empty tibble for single-step acts. |
| `exogenous_preliminary` | chr | {`TRUE`, `FALSE`, `ambiguous`} — Claude's **preliminary** narrative read. Pending expert adjudication; kept *alongside* C2b's label, never overwriting it. |
| `exogeneity_quote` | chr | The most diagnostic source quote supporting `exogenous_preliminary`. |
| `id_reasoning` | chr | Identification/consolidation reasoning (distinct from C2b's motivation reasoning). |
| `member_chunks` | **list-col** | tibble{`doc_id` chr, `chunk_id` int}; every corpus chunk that is evidence for this shock. Drives the C2a join / re-run. |
| `recovered_chunks` | **list-col** | tibble{`doc_id` chr, `chunk_id` int}; subset of `member_chunks` that C1 did **not** surface (documentation + recall scorecard). May be empty. The C2a re-run is driven by an anti-join against existing evidence, not by this column, so it need not be exhaustive. |
| `recovered_evidence` | **list-col** | tibble{`quote` chr, `signal` chr}; direct quotes for events with no usable chunk at all (rare). Folded into the evidence bundle as synthetic C2a records. Empty tibble when unused. |
| `sources` | **list-col** | tibble{`doc_id` chr, `body` chr, `year` int, `pdf_url` chr, `doc_language` chr}; the citable documents, traced via `country_body`/`country_urls`. |
| `recall_scorecard` | **list-col** | tibble{`stage` chr, `outcome` chr}; the `tbl-recall`-style search-completeness audit. **Mandatory** — every skill run must populate it. |

## How the pipeline consumes this

`R/tax_shock_dataset.R`:

1. `bind_tax_shocks(files)` — read + row-bind the frozen `.qs`, validate these
   columns exist, assign a per-row `cluster_id`, check `shock_id` uniqueness.
2. `assemble_shock_evidence(shocks, c2a_evidence, chunks, c2a_codebook, ...)` —
   unnest `member_chunks`; left-join existing `country_c2a_evidence` by
   (`doc_id`,`chunk_id`); for member chunks with **no** existing evidence, pull
   `text` from `country_chunks` and run `run_c2a_deployment()` with `act_label`
   as the measure name; fold in `recovered_evidence`. Emits the exact
   `aggregate_c0_acts_deployment()` schema (`act_name` = `shock_id`).
3. `run_c2b_on_shocks(bundles, c2b_codebook, ...)` — reuses `run_c2b_deployment()`
   (C2b v0.9.1 frozen) unchanged.
4. `assemble_tax_shock_deliverable(shocks, c2b_out)` — joins C2b
   `pred_label`/`pred_exogenous`/`pred_sign`/`reasoning` onto the identified
   shocks. Final deliverable keeps **both** `exogenous_preliminary` and C2b's
   `pred_exogenous`.
