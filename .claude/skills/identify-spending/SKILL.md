---
name: identify-spending
description: Agentic narrative identification of discretionary government spending-side fiscal changes (stimulus/relief packages, subsidy-policy changes, large allocations, Five-Year Plan launches) from the deployment corpus, consolidated into a human-stamped frozen shock dataset. Spending-side analogue of identify-cit; mirrors notebooks/spending_identification.qmd.
user-invocable: true
---

# Identify Government Spending Shocks

Run an AI-assisted **narrative identification** pass over the deployment corpus to
build a clean dataset of a country's **discretionary government spending changes**,
the spending-side analogue of what `/identify-cit` does for statutory CIT rates.
This skill reads the source documents directly, consolidates scattered surface
forms into cohesive spending acts, records a preliminary exogeneity read, and
freezes a human-stamped reference dataset.

The output conforms to its own parallel contract,
`docs/phase_1/spending_shock_schema.md` (`instrument_type = "Expenditure"`,
`tax_type = NA`, plus `spending_category`). It is consumed by the spending pipeline
(`spending_shock_files` → `spending_shocks_identified` → `spending_shocks_evidence`
→ `spending_shocks_c2b` → `spending_shocks` in `_targets.R`), which binds it and
runs the **frozen C2a/C2b** classifier for motivation and exogeneity — exactly as
the tax pipeline does (C2a/C2b pass spending acts through unchanged).

This skill is **self-contained**. It **stops at freeze**: it identifies,
consolidates, freezes the dataset, and writes/extends the provenance notebook. The
API enrichment (C2a re-run + C2b) is run separately via the `spending_*` targets,
gated.

## When to Use

- You want a Das et al. (2026)-style discretionary government-spending dataset for a
  deployed country (one whose `country_chunks` / `country_body` branch exists),
  enriched downstream with motivation + exogeneity by the frozen C2b.
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
   completeness audit, *including the expected near-empty C1 finding* (C1 is
   tax-scoped, so it surfaces almost no spending events). Recall cannot be
   expert-validated from the dataset; the scorecard is the only record of what was
   searched and missed.
4. **One row per narratively-announced spending act.** A phased multi-year
   programme (a Five-Year Plan launch, a multi-tranche stimulus) is one row with a
   `phased_schedule`, not several rows. Scope is **major programs and policy
   changes**, not every year-on-year expenditure wiggle.
5. **No `tar_make()` on API targets without explicit approval.** Reading targets
   (`tar_read`) is fine. This skill itself makes no LLM API calls; the C2a re-run
   and C2b happen later, in the `spending_*` targets, gated.
6. **Country-agnostic language.** Identify by the *concept* (discretionary changes
   in government spending), using the country's surface terms; do not hard-code
   US/Malaysia assumptions into the reasoning.

## Procedure

### Step 1: Setup and instrument config

Confirm the target country slug (e.g. `malaysia`) and its branch index in the list
targets. Load the instrument config (inline — this skill is self-contained):

- **Concept:** *discretionary* changes in government spending — deliberate policy
  choices (new/expanded programmes, stimulus/relief packages, subsidy-policy
  changes, large allocations, Five-Year Plan launches, spending restraint /
  consolidation). **Not** automatic stabilizers, and not the routine baseline.
- **Surface terms / regex** (extend per country as needed; EN + Bahasa Malaysia):
  `spending|expenditure|development expenditure|allocation|subsid|transfer|infrastructure|infrastruktur|stimulus|rangsangan|peruntukan|perbelanjaan pembangunan|bantuan|PRIHATIN|PENJANA|PEMERKASA|Rancangan Malaysia|RMK`
- **Spending category** (Das component families) for each act:
  `INFRASTRUCTURE_INVESTMENT`, `SOCIAL_TRANSFERS`, `SUBSIDIES`, `PUBLIC_WAGES`,
  `CONSOLIDATION_RESTRAINT`, `OTHER`.
- **Anchor document types** for direct reading: Budget Speeches (Development
  Expenditure estimates), Five-Year Plans (Rancangan Malaysia / RMK), Economic
  Reports, central-bank (BNM) Annual Reports.

Read the corpus pool (API-safe):

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  c1 <- tar_read(country_c1_measures)[[<branch_idx>]]
  cat(nrow(c1), "C1 measures (expected: almost none are spending)\n")'
```

### Step 2: Keyword scan (expected near-empty — log it)

Filter `country_c1_measures$measure_name` by the spending regex. Record the count
and any surface forms. **This floor is expected to be near-empty** because C1 is
scoped to tax liabilities only — that is itself a finding and must go in the recall
scorecard. Do not treat a near-empty C1 as a failure.

### Step 3: Direct corpus sweep (the primary method here)

Because the C1 floor is near-empty, **direct reading of the corpus is the primary
identification method**, not a backstop. Sweep `country_chunks` text by the
spending regex and the component families; read the anchor documents' spending
sections in `country_body`. Note every candidate spending act with its `doc_id` +
`chunk_id`.

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  ch <- tar_read(country_chunks)[[<branch_idx>]]
  hits <- dplyr::filter(ch, grepl("PRIHATIN|stimulus|perbelanjaan pembangunan|subsid", text, ignore.case=TRUE))
  cat(nrow(hits), "candidate spending chunks\n")'
```

### Step 4: Recall recovery against known-act checkpoints

Verify the **known major spending acts** are present; where missing, read the
anchor source documents directly from full text. For Malaysia, the recall
checkpoints (must be found if the corpus and method are working):

- **National Economic Recovery Plan (1998)** — Asian-crisis fiscal response.
- **2009 GFC stimulus packages** — global-financial-crisis fiscal stimulus.
- **2020 COVID-19 packages — PRIHATIN / PENJANA / PEMERKASA** (RM250 bn+).

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  body <- tar_read(country_body)[[<branch_idx>]]
  doc  <- dplyr::filter(body, body == "Economic Report", year == 2020)
  cat(paste(doc$text[[1]], collapse="\n--PAGE--\n"))'
```

Record each recovered event with its `recovered_chunks` (the `doc_id`+`chunk_id` of
a chunk that contains it but C1 did not surface) and/or a `recovered_evidence`
direct quote (for events absent from any chunk). For spending, expect **most**
member chunks to be recovered (C1 is tax-scoped).

### Step 5: Consolidation

Group surface forms + recovered events into **announced spending acts** (one row
per act). For each: set `spending_category`, `direction` (`Increase`/`Decrease`/
`Neutral`), the magnitude in `magnitude_note` (RM bn, % of GDP, Δ% development
expenditure — there is no statutory rate, so `rate_from`/`rate_to`/`delta_pp` stay
`NA`), `announced_year`, `effective_year`, `effective_quarter` (if known), and the
`phased_schedule` for multi-tranche acts. Write the preliminary
`exogenous_preliminary` + `exogeneity_quote` and the `id_reasoning`.

**Preliminary exogeneity — the Das (2026) two-condition screen.** Mark an act
`exogenous_preliminary = TRUE` only when **both** hold: (i) the stated motive is
non-cyclical — an *inherited fiscal imbalance / medium-term consolidation target*,
a *long-run structural/ideological objective* (size or composition of the public
sector — growth, fairness, institutional design), or *compliance with a
law/treaty/supranational rule*; **and** (ii) the narrative does **not** cite
contemporaneous growth/recession, unemployment, overheating/inflation,
interest-rate/exchange-rate pressure, or financing stress as the rationale. Mark
`FALSE` when a cyclical motive is cited (most crisis stimulus is countercyclical →
endogenous). Use `ambiguous` when the corpus carries both framings. Apply the
**"acknowledgment ≠ endogeneity"** rule: merely *acknowledging* current conditions
does not make an act endogenous if the stated motive is explicitly non-cyclical.
Anchor the call in `exogeneity_quote`.

### Step 6: Build the artifact

Assemble the contract tibble (`docs/phase_1/spending_shock_schema.md`), the
`member_chunks` manifest (every `doc_id`+`chunk_id` that is evidence), and the
**recall scorecard** (stage × outcome, including the near-empty-C1 finding and how
each known act was recovered). Assign `shock_id` (`{ISO}-SPEND-NN`).

#### PAUSE POINT — human review & stamp

Present, for review:

```
- The consolidated spending-shock table (act_label, spending_category, direction, magnitude_note, years, preliminary exogeneity)
- The recall scorecard (near-empty C1; which known acts were recovered and how)
- The member-chunk manifest counts per shock
- Any open adjudication questions (consolidation grain, exogeneity ambiguity)
```

Do NOT persist the dataset until the human confirms the events, the consolidation
grain, and the preliminary reads. The human stamp is what makes this a reproducible
reference input.

### Step 7: Persist + document provenance

On confirmation, freeze the dataset and write its meta sidecar:

```r
Rscript -e 'library(qs2)
  qs_save(<shocks_tibble>, "data/validated/MY_SPENDING_shocks.qs")
  yaml::write_yaml(list(
    instrument = "SPENDING", country_iso = "MY", skill = "identify-spending",
    frozen_at = format(Sys.time()),
    git_hash = system("git rev-parse --short HEAD", intern = TRUE),
    reviewer = "<name>"),
    "data/validated/MY_SPENDING_shocks_meta.yml")'
```

Then **write/extend `notebooks/spending_identification.qmd`**: it loads the frozen
tibble, renders the recall scorecard as `tbl-recall`, the headline spending-act
table, the preliminary-exogeneity table, and the member-chunk manifest. The
notebook is the provenance record. **Stop here** — the C2a re-run + C2b run later,
via the `spending_*` targets, gated.

## What This Skill Does NOT Do

- Does not call the LLM API through the pipeline (the C2a re-run + C2b run in the
  `spending_*` targets, gated).
- Does not assign the final motivation/exogeneity label (that is the frozen C2b's
  job; this skill records a *preliminary* Das-style read only).
- Does not build a spending-side C2 *codebook* (deferred — the frozen tax-validated
  C2b is used for the final classification).
- Does not commit (commits are human-owned, Research Companion Principle 4).
- Does not run C0 / use C0 acts as the event layer (C0 is tax-scoped and fragments
  tight tracks).
- Does not wire spending into `tax_shock_files` or the `/identify-tax-shocks`
  orchestrator (the contracts and globs are kept disjoint).

## Error Handling

- **Country branch not found:** confirm the country completed C1 deployment; list
  `tar_read(country_chunks)` element countries.
- **C1 keyword scan returns nothing:** expected — log it in the recall scorecard and
  proceed with the direct corpus sweep (Step 3).
- **A recovered event's chunk is not in `country_chunks`:** record it via
  `recovered_evidence` (direct quote) instead of `recovered_chunks`; the pipeline
  folds it into the C2b bundle.
- **Ambiguous consolidation (one act or several):** surface it at the PAUSE POINT as
  an open question; default to one row per announced act with the schedule in
  `phased_schedule`.
- **Human declines to stamp:** do not persist; record the open questions and stop.

## Composability

- Self-contained. Parallel to `/identify-cit` / `/identify-pit` / `/identify-vat`
  (procedures duplicated by design), but with its own contract
  (`docs/phase_1/spending_shock_schema.md`) and its own pipeline targets.
- The frozen `.qs` is read by `R/spending_shock_dataset.R::bind_spending_shocks()`
  via the `spending_shock_files` target; the rest of the tail reuses
  `assemble_shock_evidence()` / `run_c2b_on_shocks()` /
  `assemble_tax_shock_deliverable()` from `R/tax_shock_dataset.R` unchanged.
- Follows `/quarto-style` when editing `spending_identification.qmd`.
