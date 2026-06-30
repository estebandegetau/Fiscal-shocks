---
name: identify-incentives
description: Agentic narrative identification of changes to tax incentives / holidays (tax holidays, investment & reinvestment allowances, concessionary investor rates, zones, sectoral/R&D incentives, consumption holidays, personal reliefs) from the deployment corpus, consolidated into a human-stamped frozen shock dataset. Incentive-side analogue of identify-spending; mirrors notebooks/incentives_identification.qmd.
user-invocable: true
---

# Identify Tax-Incentive / Holiday Shocks

Run an AI-assisted **narrative identification** pass over the deployment corpus to
build a clean dataset of a country's **changes to selective tax-relief
instruments** — the incentive-side analogue of what `/identify-spending` does for
discretionary spending. This skill reads the source documents directly,
consolidates scattered surface forms into cohesive incentive acts, records a
preliminary exogeneity read, and freezes a human-stamped reference dataset.

The output conforms to its own parallel contract,
`docs/phase_1/incentive_shock_schema.md` (`instrument_type = "Incentive"`,
`incentive_category` mechanism family, `tax_type` carrying the underlying base, and
rate fields meaningful for preferential-rate cases). It is consumed by the incentive
pipeline (`incentive_shock_files` → `incentive_shocks_identified` →
`incentive_shocks_evidence` → `incentive_shocks_c2b` → `incentive_shocks` in
`_targets.R`), which binds it and runs the **frozen C2a/C2b** classifier for
motivation and exogeneity — exactly as the tax and spending pipelines do (C2a/C2b
pass incentive acts through unchanged).

This skill is **self-contained**. It **stops at freeze**: it identifies,
consolidates, freezes the dataset, and writes/extends the provenance notebook. The
API enrichment (C2a re-run + C2b) is run separately via the `incentive_*` targets,
gated.

## When to Use

- You want a Klemm & Van Parys (2012)-style tax-incentive dataset for a deployed
  country (one whose `country_chunks` / `country_body` branch exists), enriched
  downstream with motivation + exogeneity by the frozen C2b.
- Prerequisite: the country has completed C1 deployment and `country_body` /
  `country_chunks` / `country_c2a_evidence` are populated.

## Critical Rules

1. **Human confers meaning.** This skill identifies and proposes; the researcher
   adjudicates exogeneity and stamps the dataset. Classification outputs are inputs
   requiring human interpretation, never findings (Research Companion Principle 1).
2. **Preliminary exogeneity is pending, never settled.** `exogenous_preliminary`
   is a suggestion anchored in a quote; it is carried alongside — never replaces —
   C2b's downstream label.
3. **Recall scorecard is mandatory.** Every run must produce a `tbl-recall`-style
   completeness audit, *including the expected near-empty C1 finding* (C1 is scoped
   to standing tax rates/liabilities, so it surfaces almost no incentive events).
   Recall cannot be expert-validated from the dataset; the scorecard is the only
   record of what was searched and missed.
4. **One row per narratively-announced incentive *change*.** A new scheme, a
   rate/duration change, a sectoral extension, or an expiry/repeal is one row. The
   **standing existence** of a long-running scheme (e.g. Pioneer Status since the
   1960s) is **not** a row. A phased multi-step change is one row with a
   `phased_schedule`.
5. **Ownership-by-mechanism (no duplication).** Each event lives in exactly one
   dataset. The discriminating test (Klemm & Van Parys 2012) is **selectivity +
   temporariness + base-vs-rate mechanism**: *targeted* (conditional on investor /
   sector / region / activity), *time-bounded*, or *base-or-carve-out-rate*
   measures → INCENTIVE; *universal, permanent* changes to a *standing statutory
   rate* → CIT/PIT/CONSUMPTION. Do **not** re-list an event already frozen in the
   CIT/PIT/VAT or spending sets (e.g. the 2018 GST→SST interim holiday stays in the
   consumption set as `MY-CONSUMPTION-03/04`).
6. **No `tar_make()` on API targets without explicit approval.** Reading targets
   (`tar_read`) is fine. This skill itself makes no LLM API calls; the C2a re-run
   and C2b happen later, in the `incentive_*` targets, gated.
7. **Country-agnostic language.** Identify by the *concept* (a change to a
   selective/temporary tax-relief instrument), using the country's surface terms;
   do not hard-code US/Malaysia assumptions into the reasoning.

## Procedure

### Step 1: Setup and instrument config

Confirm the target country slug (e.g. `malaysia`) and its branch index in the list
targets. Load the instrument config (inline — this skill is self-contained):

- **Concept:** a *change* to a selective tax-relief instrument — investment
  incentives (tax holidays, investment / reinvestment allowances, accelerated
  depreciation, investment tax credits, concessionary investor rates, free / export
  / enterprise zones, sectoral / R&D incentives), consumption-side holidays, and
  personal-income reliefs / rebates. **Not** a universal, permanent statutory rate
  change (that belongs to `/identify-cit` / `/identify-pit` / `/identify-vat`).
- **Incentive category** (Klemm & Van Parys mechanism families) for each act:
  `TAX_HOLIDAY`, `INVESTMENT_ALLOWANCE`, `PREFERENTIAL_RATE`, `ZONE`, `SECTORAL_RD`,
  `OTHER`. Record the **underlying base** in `tax_type` (`CIT`/`PIT`/`CONSUMPTION`/`NA`).
- **Surface terms / regex** (extend per country as needed; EN + Bahasa Malaysia):
  `tax incentive|fiscal incentive|tax holiday|pioneer status|taraf perintis|investment tax allowance|elaun cukai pelaburan|reinvestment allowance|elaun penanaman semula|accelerated (capital )?allowance|tax exemption|pengecualian cukai|tax rebate|rebat cukai|relief|pelepasan|free zone|export zone|enterprise zone|zon|Promotion of Investments Act|MSC|Multimedia Super Corridor|Labuan|Principal Hub|concessionary rate|preferential rate`
- **Anchor document types** for direct reading: Budget Speeches (incentive
  announcements), Economic Reports, MIDA / investment-authority materials,
  central-bank (BNM) Annual Reports, the Promotion of Investments Act 1986 and
  Income Tax Act incentive schedules. **Note:** Klemm & Van Parys (2012) and Nar
  (2019) supply the *generic* vocabulary only — Malaysia instrument names must be
  sourced from the corpus / MIDA / the PIA, not from those two papers.

**Seed list (Malaysia).** The `/identify-cit` pass deliberately set aside the
concessionary / incentive regimes — they are the seed of this dataset
(`notebooks/cit_identification.qmd`): Labuan offshore 3% / RM20k regime; Principal
Hub 10% (2019); biomass companies (2001); pharma/vaccine 0–10% (2021);
manufacturing-relocation 15% (2023); the 1981 DEB equity-restructuring 5pp
exemption — plus PIA 1986 framework instruments (Pioneer Status, Investment Tax
Allowance, Reinvestment Allowance) where the corpus records a *change*.

Read the corpus pool (API-safe):

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  c1 <- tar_read(country_c1_measures)[[<branch_idx>]]
  cat(nrow(c1), "C1 measures (expected: almost none are incentives)\n")'
```

### Step 2: Keyword scan (expected near-empty — log it)

Filter `country_c1_measures$measure_name` by the incentive regex. Record the count
and any surface forms. **This floor is expected to be near-empty** because C1 is
scoped to standing tax rates/liabilities — that is itself a finding and must go in
the recall scorecard. Do not treat a near-empty C1 as a failure.

### Step 3: Direct corpus sweep (the primary method here)

Because the C1 floor is near-empty, **direct reading of the corpus is the primary
identification method**, not a backstop. Sweep `country_chunks` text by the
incentive regex and the mechanism families; read the anchor documents' incentive
sections in `country_body`. Note every candidate incentive change with its `doc_id`
+ `chunk_id`.

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  ch <- tar_read(country_chunks)[[<branch_idx>]]
  hits <- dplyr::filter(ch, grepl("tax holiday|pioneer|investment tax allowance|reinvestment allowance|Principal Hub|Labuan|tax incentive|pengecualian cukai", text, ignore.case=TRUE))
  cat(nrow(hits), "candidate incentive chunks\n")'
```

### Step 4: Recall recovery against known-act checkpoints

Verify the **known major incentive changes** are present; where missing, read the
anchor source documents directly from full text. For Malaysia, candidate recall
checkpoints (confirm against the corpus — sourced from MIDA/PIA, not Klemm/Nar):

- **Promotion of Investments Act 1986** — the enabling reform (Pioneer Status /
  ITA framework).
- **Principal Hub 10% concessionary rate (2019)** and the sectoral special rates
  (biomass 2001, pharma/vaccine 0–10% 2021, manufacturing-relocation 15% 2023).
- **MSC / Multimedia Super Corridor status** and **Labuan offshore** regime changes.

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  body <- tar_read(country_body)[[<branch_idx>]]
  doc  <- dplyr::filter(body, body == "Budget Speech", year == 2019)
  cat(paste(doc$text[[1]], collapse="\n--PAGE--\n"))'
```

Record each recovered event with its `recovered_chunks` (the `doc_id`+`chunk_id` of
a chunk that contains it but C1 did not surface) and/or a `recovered_evidence`
direct quote (for events absent from any chunk). For incentives, expect **most**
member chunks to be recovered (C1 is tax-rate-scoped).

### Step 5: Consolidation

Group surface forms + recovered events into **announced incentive changes** (one row
per change). For each: set `incentive_category`, `tax_type` (underlying base),
`direction` (`Cut` = new/expanded incentive lowering the effective burden; `Hike` =
repeal / scale-back; `Neutral`). For preferential-rate cases set
`rate_from`/`rate_to`/`delta_pp`; for non-rate cases leave them `NA` and capture the
holiday duration / allowance rate / revenue estimate / scope in `magnitude_note`.
Set `announced_year`, `effective_year`, `effective_quarter` (if known), and the
`phased_schedule` for phased changes. Write the preliminary `exogenous_preliminary`
+ `exogeneity_quote` and the `id_reasoning`.

**Preliminary exogeneity — the incentive prior.** Incentives skew **exogenous**:
the dominant motives (attract FDI / mobile capital, promote a sector / region /
activity, raise long-run growth and competitiveness) are structural and
non-cyclical → `exogenous_preliminary = TRUE`. A **tax-competition-reactive** motive
(an incentive set in response to neighbouring jurisdictions) is also
non-countercyclical → lean `TRUE`, but note the reactivity. Mark `FALSE` only when
the stated rationale is an explicit **cyclical / crisis response** (e.g. a temporary
investment sweetener introduced to counter a recession). Use `ambiguous` when the
corpus carries both framings. Apply the **"acknowledgment ≠ endogeneity"** rule:
merely *acknowledging* current conditions does not make an act endogenous if the
stated motive is explicitly non-cyclical. Anchor the call in `exogeneity_quote`.

### Step 6: Build the artifact

Assemble the contract tibble (`docs/phase_1/incentive_shock_schema.md`), the
`member_chunks` manifest (every `doc_id`+`chunk_id` that is evidence), and the
**recall scorecard** (stage × outcome, including the near-empty-C1 finding and how
each known act was recovered). Assign `shock_id` (`{ISO}-INCENT-NN`).

#### PAUSE POINT — human review & stamp

Present, for review:

```
- The consolidated incentive-change table (act_label, incentive_category, base, direction, rate/magnitude, years, preliminary exogeneity)
- The recall scorecard (near-empty C1; which known acts were recovered and how)
- The member-chunk manifest counts per shock
- Any open adjudication questions (consolidation grain, ownership-vs-CIT boundary, exogeneity ambiguity)
```

Do NOT persist the dataset until the human confirms the events, the consolidation
grain, the ownership boundary (no re-listing of CIT/PIT/VAT/spending events), and
the preliminary reads. The human stamp is what makes this a reproducible reference
input.

### Step 7: Persist + document provenance

On confirmation, freeze the dataset and write its meta sidecar:

```r
Rscript -e 'library(qs2)
  qs_save(<shocks_tibble>, "data/validated/MY_INCENTIVE_shocks.qs")
  yaml::write_yaml(list(
    instrument = "INCENTIVE", country_iso = "MY", skill = "identify-incentives",
    frozen_at = format(Sys.time()),
    git_hash = system("git rev-parse --short HEAD", intern = TRUE),
    reviewer = "<name>"),
    "data/validated/MY_INCENTIVE_shocks_meta.yml")'
```

Then **write/extend `notebooks/incentives_identification.qmd`**: it loads the frozen
tibble, renders the recall scorecard as `tbl-recall`, the headline incentive-act
table, the preliminary-exogeneity table, and the member-chunk manifest. The notebook
is the provenance record. **Stop here** — the C2a re-run + C2b run later, via the
`incentive_*` targets, gated.

## What This Skill Does NOT Do

- Does not call the LLM API through the pipeline (the C2a re-run + C2b run in the
  `incentive_*` targets, gated).
- Does not assign the final motivation/exogeneity label (that is the frozen C2b's
  job; this skill records a *preliminary* read only).
- Does not build an incentive-side C2 *codebook* (deferred — the frozen
  tax-validated C2b is used for the final classification).
- Does not commit (commits are human-owned, Research Companion Principle 4).
- Does not use C0 acts as the event layer (C0 is tax-scoped and fragments tight
  tracks).
- Does not re-list an event already frozen in the CIT/PIT/VAT or spending sets
  (ownership-by-mechanism, Critical Rule 5); the `_INCENTIVE_shocks.qs` glob is kept
  disjoint.

## Error Handling

- **Country branch not found:** confirm the country completed C1 deployment; list
  `tar_read(country_chunks)` element countries.
- **C1 keyword scan returns nothing:** expected — log it in the recall scorecard and
  proceed with the direct corpus sweep (Step 3).
- **A recovered event's chunk is not in `country_chunks`:** record it via
  `recovered_evidence` (direct quote) instead of `recovered_chunks`; the pipeline
  folds it into the C2b bundle.
- **An event already lives in another set (CIT/PIT/VAT/spending):** do not re-list
  it; note the cross-reference in `id_reasoning` and leave ownership with the other
  set (Critical Rule 5).
- **Ambiguous consolidation (one change or several):** surface it at the PAUSE POINT
  as an open question; default to one row per announced change with the schedule in
  `phased_schedule`.
- **Human declines to stamp:** do not persist; record the open questions and stop.

## Composability

- Self-contained. Parallel to `/identify-cit` / `/identify-pit` / `/identify-vat`
  and `/identify-spending` (procedures duplicated by design), but with its own
  contract (`docs/phase_1/incentive_shock_schema.md`) and its own pipeline targets.
- The frozen `.qs` is read by `R/incentive_shock_dataset.R::bind_incentive_shocks()`
  via the `incentive_shock_files` target; the rest of the tail reuses
  `assemble_shock_evidence()` / `run_c2b_on_shocks()` /
  `assemble_tax_shock_deliverable()` from `R/tax_shock_dataset.R` unchanged.
- Follows `/quarto-style` when editing `incentives_identification.qmd`.
