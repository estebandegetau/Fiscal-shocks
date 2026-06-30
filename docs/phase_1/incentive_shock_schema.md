# Tax-Incentive / Holiday Shock Dataset — Output Contract

This document is the **single source of truth** for the columns of the frozen
per-country tax-incentive shock datasets produced by the `identify-incentives`
skill. It is the incentive-side analogue of `docs/phase_1/tax_shock_schema.md` and
`docs/phase_1/spending_shock_schema.md`, and is kept **deliberately parallel**: the
column set is the **tax contract plus an `incentive_category` column**, so the same
pipeline tail (`R/tax_shock_dataset.R`'s `assemble_shock_evidence()`,
`run_c2b_on_shocks()`, `assemble_tax_shock_deliverable()`) consumes incentive shocks
**unchanged**. Only the bind step differs (`bind_incentive_shocks()` in
`R/incentive_shock_dataset.R`).

If you change a column here, update the `identify-incentives` skill and
`R/incentive_shock_dataset.R` in the same pass (Workflow Convention #11: grep
before editing).

## Why a parallel contract (and why it is the *tax* contract, not the spending one)

A tax incentive is a **hybrid** of the tax and spending cases:

1. **Rate fields stay meaningful.** Unlike spending (where `rate_from`/`rate_to`/
   `delta_pp` are always `NA`), many incentives *are* rate-denominated — a
   concessionary investor rate (Labuan 3%, Principal Hub 10%, pharma/vaccine
   0–10%, manufacturing-relocation 15%). The incentive contract therefore keeps the
   tax contract's rate fields, populated for `PREFERENTIAL_RATE` cases and `NA` for
   non-rate incentives (holidays, allowances, credits).
2. **A category column carries the mechanism.** Like spending's `spending_category`,
   an `incentive_category` column (the K&VP-style mechanism families) carries the
   typology that `tax_type` cannot.
3. **`tax_type` carries the underlying base.** Because the scope spans investment,
   consumption-holiday, and personal-relief incentives, `tax_type` records the
   **tax base** the incentive sits on (`CIT`/`PIT`/`CONSUMPTION`, or `NA` where none
   applies), distinct from spending's always-`NA`.

The final C2b motivation/sign label is still produced by the **frozen C2b
classifier** (C2a/C2b pass incentive acts through unchanged), kept *alongside* the
preliminary narrative read — never overwriting it.

## Scope and the ownership-by-mechanism boundary

Scope is **changes to selective tax-relief instruments** — investment incentives
(tax holidays, investment/reinvestment allowances, accelerated depreciation,
investment tax credits, concessionary investor rates, free/export/enterprise zones,
sectoral/R&D incentives), consumption-side holidays, and personal-income reliefs.
**One row per *legislative change*** (a new scheme, a rate/duration change, a
sectoral extension, an expiry/repeal); the standing existence of a long-running
scheme is **not** a row.

**Ownership-by-mechanism (no duplication).** Each event lives in exactly one
dataset. The discriminating test (Klemm & Van Parys 2012) is **selectivity +
temporariness + base-vs-rate mechanism**: a measure that is *targeted* (conditional
on investor / sector / region / activity), *time-bounded*, or operating through the
*base or a carve-out rate* → **INCENTIVE**; a *universal, permanent* change to a
*standing statutory rate* → CIT/PIT/CONSUMPTION. Consequently the 2018 GST→SST
interim "tax holiday" stays in the consumption set (`MY-CONSUMPTION-03/04`) and
genuinely new reliefs/holidays land here. There is no `cross_ref` column; the
`_INCENTIVE_shocks.qs` glob is disjoint from the tax and spending globs, so
incentive rows never mix into `tax_shocks` or `spending_shocks` and vice-versa.

The seed of the Malaysia dataset is the set of concessionary regimes the
`/identify-cit` pass deliberately set aside (`notebooks/cit_identification.qmd`):
Labuan offshore 3%, Principal Hub 10% (2019), biomass (2001), pharma/vaccine 0–10%
(2021), manufacturing-relocation 15% (2023), the 1981 DEB equity-restructuring 5pp
exemption — plus the Promotion of Investments Act 1986 framework instruments
(Pioneer Status, Investment Tax Allowance, Reinvestment Allowance) where the corpus
records a *change*.

## Reproducibility framing

The agentic identification pass is **not a pure function**, so it does not live in a
`tar_target` command. Each frozen dataset is a **hand-curated reference input** —
analogous to `data/raw/us_shocks.csv` and to the tax-/spending-shock `.qs` files —
produced by the skill + provenance notebook + human stamp, then read back into the
pipeline through the `incentive_shock_files` file target. The *target* is the frozen
output; the notebook (`notebooks/incentives_identification.qmd`) documents
provenance. See `docs/deltas.md` (2026-06-25 carve-out; the incentive datasets fall
under the same category-(2) human-curated-input carve-out as the tax and spending
datasets).

## Grain

**One row per (narratively-announced incentive change).** A phased multi-step change
(e.g. a holiday whose duration is extended in stages) is a **single row**; the
per-step schedule lives in `phased_schedule`.

## Persistence

- File: `data/validated/{ISO}_INCENTIVE_shocks.qs` (qs2; handles list-columns).
  Example: `data/validated/MY_INCENTIVE_shocks.qs`. The `_INCENTIVE_shocks.qs` glob
  is disjoint from the tax glob `_(CIT|PIT|CONSUMPTION)_shocks.qs` and the spending
  glob `_SPENDING_shocks.qs`.
- Sidecar: `data/validated/{ISO}_INCENTIVE_shocks_meta.yml` (git hash + date +
  skill + human reviewer).

## Columns

Scalar columns unless marked **list-col**. List-cols hold a tibble (data frame) per
row so they `tidyr::unnest()` cleanly. **Columns and types are identical to
`tax_shock_schema.md` except where bold-marked.**

| Column | Type | Notes |
|---|---|---|
| `shock_id` | chr | Unique, e.g. `MY-INCENT-01`. **Pattern `{ISO}-INCENT-NN`.** Used as the C2b `act_name` grouping key (guaranteed unique). |
| `country` | chr | Lower-case slug, e.g. `malaysia`. |
| `country_iso` | chr | e.g. `MY`. |
| `act_label` | chr | Human-readable act/event name, e.g. `Principal Hub 10% concessionary rate (Budget 2019)`. Carried through as `canonical_name`. |
| `instrument_type` | chr | **Always `Incentive`** (from the `{Tax, Expenditure, Incentive}` enum). |
| `tax_type` | chr | **{`CIT`, `PIT`, `CONSUMPTION`, `NA`}** — the underlying tax base the incentive sits on (NOT always `NA` as for spending). |
| `incentive_category` | chr | **NEW. {`TAX_HOLIDAY`, `INVESTMENT_ALLOWANCE`, `PREFERENTIAL_RATE`, `ZONE`, `SECTORAL_RD`, `OTHER`}** (K&VP mechanism families). |
| `direction` | chr | **{`Cut`, `Hike`, `Neutral`}** — tax semantics. A new/expanded incentive lowers the effective burden = `Cut`; a repeal / scaling-back = `Hike`. Must be consistent with `delta_pp` sign when rate-bearing. |
| `rate_from` | dbl | Concessionary/standard rate before the change (percent). **Meaningful for `PREFERENTIAL_RATE`**; `NA` for non-rate incentives. |
| `rate_to` | dbl | Concessionary rate after the change. `NA` for non-rate incentives. |
| `delta_pp` | dbl | `rate_to - rate_from` (pp). `NA` for non-rate incentives. |
| `magnitude_note` | chr | Free text carrying the non-rate magnitude: holiday duration (e.g. `5-year holiday`), allowance rate (e.g. `60% ITA`), revenue/tax-expenditure estimate, scope/sector. The primary magnitude field for non-rate incentives. |
| `announced_year` | int | Year the change was announced (budget / statute year). |
| `effective_year` | int | Year the change took effect / year of assessment. |
| `effective_quarter` | chr | e.g. `2019Q1`; `NA` when only year is known. |
| `phased_schedule` | **list-col** | tibble{`step_year` int, `step_rate` dbl}; one row per phase step. Empty tibble for single-step changes. |
| `exogenous_preliminary` | chr | {`TRUE`, `FALSE`, `ambiguous`} — preliminary narrative read. Incentives skew **exogenous** (FDI-attraction / industrial-policy / structural-competitiveness motives are long-run, non-cyclical); mark `FALSE` only when the stated rationale is an explicit cyclical/crisis response. A *tax-competition-reactive* motive (set in response to neighbouring jurisdictions) is non-countercyclical → lean `TRUE`, noting the reactivity. Pending expert adjudication; kept *alongside* C2b's label, never overwriting it. |
| `exogeneity_quote` | chr | The most diagnostic source quote supporting `exogenous_preliminary`. |
| `id_reasoning` | chr | Identification/consolidation reasoning (distinct from C2b's motivation reasoning). |
| `member_chunks` | **list-col** | tibble{`doc_id` chr, `chunk_id` int}; every corpus chunk that is evidence for this shock. Drives the C2a join / re-run. |
| `recovered_chunks` | **list-col** | tibble{`doc_id` chr, `chunk_id` int}; subset of `member_chunks` that C1 did **not** surface. For incentives this is expected to be **most** chunks (C1 is tax-rate-scoped, not incentive-scoped). May be empty. |
| `recovered_evidence` | **list-col** | tibble{`quote` chr, `signal` chr}; direct quotes for events with no usable chunk. Folded into the evidence bundle as synthetic C2a records. Empty tibble when unused. |
| `sources` | **list-col** | tibble{`doc_id` chr, `body` chr, `year` int, `pdf_url` chr, `doc_language` chr}; the citable documents, traced via `country_body`/`country_urls`. |
| `recall_scorecard` | **list-col** | tibble{`stage` chr, `outcome` chr}; the `tbl-recall`-style search-completeness audit. **Mandatory** — every run must populate it, including the near-empty-C1 finding. |

## How the pipeline consumes this

`R/incentive_shock_dataset.R` + `R/tax_shock_dataset.R` (reused):

1. `bind_incentive_shocks(files)` — read + row-bind the frozen `.qs`, validate these
   columns exist (`.incentive_shock_required_cols`), assign a per-row integer
   `cluster_id`, check `shock_id` uniqueness. Does **not** enforce the
   `delta_pp`/`direction` sign-consistency check (rate fields are `NA` for non-rate
   incentives). Empty-input safe.
2. `assemble_shock_evidence(shocks, c2a_evidence, chunks, c2a_codebook, ...)` —
   **reused unchanged** from `R/tax_shock_dataset.R`. Unnests `member_chunks`,
   left-joins existing `country_c2a_evidence`, re-runs `run_c2a_deployment()` on
   member chunks with no existing evidence, folds in `recovered_evidence`. Emits the
   `aggregate_c0_acts_deployment()` schema (`act_name` = `shock_id`).
3. `run_c2b_on_shocks(bundles, c2b_codebook, ...)` — **reused unchanged**; C2b v0.9.1
   frozen.
4. `assemble_tax_shock_deliverable(shocks, c2b_out)` — **reused unchanged**; joins
   C2b `pred_label`/`pred_exogenous`/`pred_sign`/`reasoning` onto the identified
   shocks. `incentive_category` flows through as a `shocks` column (the deliverable's
   `left_join` preserves every input column). Final deliverable keeps **both**
   `exogenous_preliminary` and C2b's `pred_exogenous`.

The matching pipeline targets are `incentive_shock_files` → `incentive_shocks_identified`
→ `incentive_shocks_evidence` → `incentive_shocks_c2b` → `incentive_shocks` (`_targets.R`).
