---
name: identify-cit
description: Agentic narrative identification of statutory corporate-income-tax (CIT) rate changes from the deployment corpus, consolidated into a human-stamped frozen shock dataset. Mirrors notebooks/cit_identification.qmd.
user-invocable: true
---

# Identify CIT Statutory Shocks

Run an AI-assisted **narrative identification** pass over the deployment corpus to
build a clean dataset of a country's **statutory corporate-income-tax (CIT) rate
changes**, the way `notebooks/cit_identification.qmd` did for Malaysia. The
pipeline (C1, C0) pre-screens candidate measures; this skill reads the surfaced
evidence *and the source documents directly*, consolidates scattered surface
forms into cohesive shocks, recovers events C1 missed, and freezes a
human-stamped reference dataset.

The output conforms to the shared contract in `docs/phase_1/tax_shock_schema.md`
(`tax_type = "CIT"`). It is consumed by the `identify-tax-shocks` orchestrator,
which binds it with the PIT/consumption datasets and runs C2a/C2b for motivation
and exogeneity.

This skill is **self-contained** (its procedure is duplicated in `identify-pit`
and `identify-vat` by design). The CIT pass additionally **extends
`notebooks/cit_identification.qmd` in place** rather than creating a new notebook.

## When to Use

- You want a Vegh & Vuletin (2015)-style statutory CIT-rate dataset for a
  deployed country (one whose `country_chunks` / `country_c1_measures` branch
  exists), enriched downstream with motivation + exogeneity.
- Invoked directly, or as the first instrument in `/identify-tax-shocks`.
- Prerequisite: the country has completed C1 deployment (`country_c1_measures`
  has a branch) and `country_body` / `country_chunks` are populated.

## Critical Rules

1. **Human confers meaning.** This skill identifies and proposes; the researcher
   adjudicates exogeneity and stamps the dataset. Classification outputs are
   inputs requiring human interpretation, never findings (Research Companion
   Principle 1).
2. **Preliminary exogeneity is pending, never settled.** `exogenous_preliminary`
   is a suggestion anchored in a quote; it is carried alongside — never replaces —
   C2b's downstream label.
3. **Recall scorecard is mandatory.** Every run must produce a `tbl-recall`-style
   completeness audit. Precision can be expert-validated from the dataset; recall
   cannot — the scorecard is the only record of what was searched and what was
   missed.
4. **One row per narratively-announced act × tax_type.** A phased multi-step cut
   is one row with a `phased_schedule`, not several rows.
5. **No `tar_make()` on API targets without explicit approval.** Reading targets
   (`tar_read`) is fine. This skill itself makes no LLM API calls through the
   pipeline; the C2a re-run and C2b happen later, in the orchestrator, gated.
6. **Country-agnostic language.** Identify by the *concept* (general corporate
   income tax on company profits), using the country's surface terms; do not
   hard-code US/Malaysia assumptions into the reasoning.

## Procedure

### Step 1: Setup and instrument config

Confirm the target country slug (e.g. `malaysia`) and its branch index in the
list targets. Load the instrument config (inline — this skill is self-contained):

- **Concept:** the general statutory tax rate on corporate/company profits
  (headline rate; track SME/sectoral/petroleum rates separately, headline first).
- **Surface terms / regex** (extend per country as needed):
  `corporat|company tax|companies tax|cukai pendapatan syarikat|cukai syarikat|cukai korporat|single.tier`
- **Anchor document types** for direct reading: Budget Speeches, Economic
  Reports, central-bank Annual Reports, medium-term plans.

Read the corpus pool (API-safe):

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  c1 <- tar_read(country_c1_measures)[[<branch_idx>]]
  cat(nrow(c1), "measures\n")'
```

### Step 2: Keyword scan

Filter `country_c1_measures$measure_name` by the CIT regex. Record the count and
the distinct surface forms with their years. This is the recall floor.

### Step 3: Semantic sweep

Read the keyword-matched measures *and their chunk text* (`country_chunks`),
then broaden: scan all tax-related surface forms in the pool (not just keyword
hits) to catch CIT events phrased without the keywords (e.g. "reduce the rate to
24 per cent"). Note every candidate with its `doc_id` + `chunk_id`.

### Step 4: Recall recovery (the agentic step that matters)

For each headline rate level implied by the sweep, verify it is present. Where a
step is missing, **read the anchor source documents directly** from full text:

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  body <- tar_read(country_body)[[<branch_idx>]]
  doc  <- dplyr::filter(body, body == "Budget Speech", year == 2015)
  cat(paste(doc$text[[1]], collapse="\n--PAGE--\n"))'
```

Record each recovered event with its `recovered_chunks` (the `doc_id`+`chunk_id`
of the chunk that contains it, if it exists in `country_chunks` but C1 did not
surface it) and/or a `recovered_evidence` direct quote (for events absent from
any chunk). This is how `cit_identification.qmd` recovered the 2016 cut and the
2022 Cukai Makmur.

### Step 5: Consolidation

Group surface forms + recovered events into **announced acts** (one row per act ×
`CIT`). For each: extract `rate_from`/`rate_to`/`delta_pp`, set `direction`
(Cut/Hike/Neutral), `announced_year`, `effective_year`, `effective_quarter` (if
known), and the `phased_schedule` for multi-step acts. Write the preliminary
`exogenous_preliminary` + `exogeneity_quote` and the `id_reasoning`.

### Step 6: Build the artifact

Assemble the contract tibble (`docs/phase_1/tax_shock_schema.md`), the
`member_chunks` manifest (every `doc_id`+`chunk_id` that is evidence), and the
**recall scorecard** (stage × outcome, including which events C1 missed and how
they were recovered). Assign `shock_id` (`{ISO}-CIT-NN`).

#### PAUSE POINT — human review & stamp

Present, for review:

```
- The consolidated CIT shock table (act_label, rates, years, direction, preliminary exogeneity)
- The recall scorecard (what C1 surfaced / missed / recovered)
- The member-chunk manifest counts per shock
- Any open adjudication questions (consolidation, exogeneity ambiguity)
```

Do NOT persist the dataset until the human confirms the events, the
consolidation grain, and the preliminary reads. The human stamp is what makes
this a reproducible reference input.

### Step 7: Persist + document provenance

On confirmation, freeze the dataset and write its meta sidecar:

```r
Rscript -e 'library(qs2)
  qs_save(<shocks_tibble>, "data/validated/MY_CIT_shocks.qs")
  yaml::write_yaml(list(
    instrument = "CIT", country_iso = "MY", skill = "identify-cit",
    frozen_at = format(Sys.time()),
    git_hash = system("git rev-parse --short HEAD", intern = TRUE),
    reviewer = "<name>"),
    "data/validated/MY_CIT_shocks_meta.yml")'
```

Then **extend `notebooks/cit_identification.qmd` in place**: add a chunk that
assembles/loads the frozen tibble, renders the member-chunk manifest, and renders
the recall scorecard as `tbl-recall`. Keep the existing narrative tables; the
notebook is the provenance record.

## What This Skill Does NOT Do

- Does not call the LLM API through the pipeline (the C2a re-run + C2b run in the
  orchestrator, gated).
- Does not assign the final motivation/exogeneity label (that is C2b's job; this
  skill records a *preliminary* read only).
- Does not commit (commits are human-owned, Research Companion Principle 4).
- Does not run C0 / use C0 acts as the event layer (C0 fragments tight instrument
  tracks — see `cit_identification.qmd` §2).
- Does not identify SME/sectoral/petroleum rates as headline shocks (track them
  separately, headline rate is the priority).

## Error Handling

- **Country branch not found:** confirm the country completed C1 deployment;
  list `tar_read(country_chunks)` element countries.
- **A recovered event's chunk is not in `country_chunks`:** record it via
  `recovered_evidence` (direct quote) instead of `recovered_chunks`; the
  orchestrator folds it into the C2b bundle.
- **Ambiguous consolidation (one act or several):** surface it at the PAUSE
  POINT as an open question; default to one row per announced act with the
  schedule in `phased_schedule`.
- **Human declines to stamp:** do not persist; record the open questions and stop.

## Composability

- Invoked standalone or as step 1 of `/identify-tax-shocks`.
- Shares the output contract `docs/phase_1/tax_shock_schema.md` with
  `/identify-pit` and `/identify-vat` (procedures duplicated by design).
- The frozen `.qs` is read by `R/tax_shock_dataset.R::bind_tax_shocks()` via the
  `tax_shock_files` target.
- Follows `/quarto-style` when editing `cit_identification.qmd`.
