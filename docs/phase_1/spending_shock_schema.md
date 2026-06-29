# Government Spending-Shock Dataset — Output Contract

This document is the **single source of truth** for the columns of the frozen
per-country spending-shock datasets produced by the `identify-spending` skill. It
is the spending-side analogue of `docs/phase_1/tax_shock_schema.md` and is kept
**deliberately parallel**: the column set is identical except for the spending
specifics noted below, so the same pipeline tail (`R/tax_shock_dataset.R`'s
`assemble_shock_evidence()`, `run_c2b_on_shocks()`,
`assemble_tax_shock_deliverable()`) consumes spending shocks **unchanged**. Only
the bind step differs (`bind_spending_shocks()` in `R/spending_shock_dataset.R`).

If you change a column here, update the `identify-spending` skill and
`R/spending_shock_dataset.R` in the same pass (Workflow Convention #11: grep
before editing).

## Why a parallel contract (not the tax contract)

A spending act has no statutory rate, so the tax contract's rate fields
(`rate_from`/`rate_to`/`delta_pp`) are always `NA` here, and the
exogenous/endogenous question is framed on the spending side following
**Das, Furceri, Patel & Peralta-Alva (2026, IMF WP/26/43)** rather than purely on
R&R's tax-side motivation taxonomy. The two facts that make this its own contract:

1. **No C1/C0 recall floor.** C1 is scoped to tax liabilities only
   (`docs/strategy.md`), so `country_c1_measures` surfaces almost no spending
   events. Identification is driven by **direct reading of `country_body`**, not
   the C1 pool. The recall scorecard records this.
2. **Spending category replaces tax type.** `tax_type` is `NA`; a
   `spending_category` column (Das component families) carries the typology.

The final C2b motivation/sign label is still produced by the **frozen C2b
classifier** (C2a/C2b pass spending acts through unchanged), kept *alongside* the
preliminary Das-style read — never overwriting it.

## Reproducibility framing

The agentic identification pass is **not a pure function**, so it does not live in
a `tar_target` command. Each frozen dataset is a **hand-curated reference input** —
analogous to `data/raw/us_shocks.csv` and to the tax-shock `.qs` files — produced
by the skill + provenance notebook + human stamp, then read back into the pipeline
through the `spending_shock_files` file target. The *target* is the frozen output;
the notebook (`notebooks/spending_identification.qmd`) documents provenance. See
`docs/deltas.md` (2026-06-25 carve-out; the spending datasets fall under the same
category-(2) human-curated-input carve-out as the tax datasets).

## Grain

**One row per (narratively-announced spending act).** A multi-year programme with
a phased disbursement (e.g. a Five-Year Plan launch, a multi-tranche stimulus) is a
**single row**; the per-step schedule lives in `phased_schedule`. Scope is **major
programs and policy changes** — named stimulus/relief packages, subsidy-policy
changes, large new allocations, Five-Year Plan launches — not every year-on-year
expenditure wiggle.

## Persistence

- File: `data/validated/{ISO}_SPENDING_shocks.qs` (qs2; handles list-columns).
  Example: `data/validated/MY_SPENDING_shocks.qs`. The `_SPENDING_shocks.qs` glob
  is disjoint from the tax glob `_(CIT|PIT|CONSUMPTION)_shocks.qs`, so spending
  rows never enter `tax_shocks` and vice-versa.
- Sidecar: `data/validated/{ISO}_SPENDING_shocks_meta.yml` (git hash + date +
  skill + human reviewer).

## Columns

Scalar columns unless marked **list-col**. List-cols hold a tibble (data frame)
per row so they `tidyr::unnest()` cleanly. **Columns and types are identical to
`tax_shock_schema.md` except where bold-marked.**

| Column | Type | Notes |
|---|---|---|
| `shock_id` | chr | Unique, e.g. `MY-SPEND-01`. **Pattern `{ISO}-SPEND-NN`.** Used as the C2b `act_name` grouping key (guaranteed unique). |
| `country` | chr | Lower-case slug, e.g. `malaysia`. |
| `country_iso` | chr | e.g. `MY`. |
| `act_label` | chr | Human-readable act/event name, e.g. `PRIHATIN economic stimulus package (2020)`. Carried through as `canonical_name`. |
| `instrument_type` | chr | **Always `Expenditure`** (from the `{Tax, Expenditure, Incentive}` enum). |
| `tax_type` | chr | **Always `NA`** (kept for structural parity / bind compatibility). |
| `spending_category` | chr | **NEW. {`INFRASTRUCTURE_INVESTMENT`, `SOCIAL_TRANSFERS`, `SUBSIDIES`, `PUBLIC_WAGES`, `CONSOLIDATION_RESTRAINT`, `OTHER`}** (Das component families). |
| `direction` | chr | **{`Increase`, `Decrease`, `Neutral`}** — spending-native (an `Increase` is expansionary). Distinct from the tax enum `{Cut, Hike, Neutral}` to avoid sign confusion. |
| `rate_from` | dbl | **Always `NA`** (spending has no statutory rate). |
| `rate_to` | dbl | **Always `NA`**. |
| `delta_pp` | dbl | **Always `NA`**. |
| `magnitude_note` | chr | Free text carrying the spending magnitude (e.g. `RM250 bn`, `+18% development expenditure`, `% of GDP`). The primary magnitude field for spending. |
| `announced_year` | int | Year the act was announced (budget / plan year). |
| `effective_year` | int | Year the spending took effect / began disbursing. |
| `effective_quarter` | chr | e.g. `2020Q1`; `NA` when only year is known. |
| `phased_schedule` | **list-col** | tibble{`step_year` int, `step_rate` dbl}; for spending, `step_rate` carries the per-tranche magnitude (units documented in `magnitude_note`). Empty tibble for single-step acts. |
| `exogenous_preliminary` | chr | {`TRUE`, `FALSE`, `ambiguous`} — preliminary read via the **Das two-condition screen** (exogenous iff motive is non-cyclical AND the narrative does not cite contemporaneous growth/inflation/unemployment/FX/financing-stress as the rationale). Pending expert adjudication; kept *alongside* C2b's label, never overwriting it. |
| `exogeneity_quote` | chr | The most diagnostic source quote supporting `exogenous_preliminary`. |
| `id_reasoning` | chr | Identification/consolidation reasoning (distinct from C2b's motivation reasoning). |
| `member_chunks` | **list-col** | tibble{`doc_id` chr, `chunk_id` int}; every corpus chunk that is evidence for this shock. Drives the C2a join / re-run. |
| `recovered_chunks` | **list-col** | tibble{`doc_id` chr, `chunk_id` int}; subset of `member_chunks` that C1 did **not** surface. For spending this is expected to be **most** chunks (C1 is tax-scoped). May be empty. |
| `recovered_evidence` | **list-col** | tibble{`quote` chr, `signal` chr}; direct quotes for events with no usable chunk. Folded into the evidence bundle as synthetic C2a records. Empty tibble when unused. |
| `sources` | **list-col** | tibble{`doc_id` chr, `body` chr, `year` int, `pdf_url` chr, `doc_language` chr}; the citable documents, traced via `country_body`/`country_urls`. |
| `recall_scorecard` | **list-col** | tibble{`stage` chr, `outcome` chr}; the `tbl-recall`-style search-completeness audit. **Mandatory** — every run must populate it, including the near-empty-C1 finding. |

## How the pipeline consumes this

`R/spending_shock_dataset.R` + `R/tax_shock_dataset.R` (reused):

1. `bind_spending_shocks(files)` — read + row-bind the frozen `.qs`, validate these
   columns exist (`.spending_shock_required_cols`), assign a per-row `cluster_id`,
   check `shock_id` uniqueness. Does **not** enforce the `delta_pp`/`direction`
   sign-consistency check (rate fields are `NA`). Empty-input safe.
2. `assemble_shock_evidence(shocks, c2a_evidence, chunks, c2a_codebook, ...)` —
   **reused unchanged** from `R/tax_shock_dataset.R`. Unnests `member_chunks`,
   left-joins existing `country_c2a_evidence`, re-runs `run_c2a_deployment()` on
   member chunks with no existing evidence (most of them, for spending), folds in
   `recovered_evidence`. Emits the `aggregate_c0_acts_deployment()` schema
   (`act_name` = `shock_id`).
3. `run_c2b_on_shocks(bundles, c2b_codebook, ...)` — **reused unchanged**; C2b
   v0.9.1 frozen.
4. `assemble_tax_shock_deliverable(shocks, c2b_out)` — **reused unchanged**; joins
   C2b `pred_label`/`pred_exogenous`/`pred_sign`/`reasoning` onto the identified
   shocks. `spending_category` flows through as a `shocks` column. Final deliverable
   keeps **both** `exogenous_preliminary` and C2b's `pred_exogenous`.

The matching pipeline targets are `spending_shock_files` → `spending_shocks_identified`
→ `spending_shocks_evidence` → `spending_shocks_c2b` → `spending_shocks` (`_targets.R`).
