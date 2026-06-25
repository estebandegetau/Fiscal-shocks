---
name: identify-pit
description: Agentic narrative identification of statutory personal/individual income-tax (PIT) rate changes from the deployment corpus, consolidated into a human-stamped frozen shock dataset. Mirrors notebooks/cit_identification.qmd.
user-invocable: true
---

# Identify PIT Statutory Shocks

Run an AI-assisted **narrative identification** pass over the deployment corpus to
build a clean dataset of a country's **statutory personal/individual income-tax
(PIT) rate changes**, the way `notebooks/cit_identification.qmd` did for corporate
income tax. The pipeline (C1, C0) pre-screens candidate measures; this skill reads
the surfaced evidence *and the source documents directly*, consolidates scattered
surface forms into cohesive shocks, recovers events C1 missed, and freezes a
human-stamped reference dataset.

The output conforms to the shared contract in `docs/phase_1/tax_shock_schema.md`
(`tax_type = "PIT"`). It is consumed by the `identify-tax-shocks` orchestrator,
which binds it with the CIT/consumption datasets and runs C2a/C2b for motivation
and exogeneity.

This skill is **self-contained** (its procedure is duplicated in `identify-cit`
and `identify-vat` by design). It produces a fresh provenance notebook
`notebooks/pit_identification.qmd` from the CIT template.

## When to Use

- You want a Vegh & Vuletin (2015)-style statutory PIT-rate dataset for a deployed
  country, enriched downstream with motivation + exogeneity.
- Invoked directly, or as the second instrument in `/identify-tax-shocks`.
- Prerequisite: the country has completed C1 deployment (`country_c1_measures`
  has a branch) and `country_body` / `country_chunks` are populated.

## Critical Rules

1. **Human confers meaning.** This skill identifies and proposes; the researcher
   adjudicates exogeneity and stamps the dataset (Research Companion Principle 1).
2. **Preliminary exogeneity is pending, never settled.** `exogenous_preliminary`
   is a quote-anchored suggestion, carried alongside — never replacing — C2b's
   downstream label.
3. **Recall scorecard is mandatory.** Every run produces a `tbl-recall`-style
   completeness audit. Recall cannot be expert-validated from the dataset alone;
   the scorecard is the only record of what was searched and missed.
4. **One row per narratively-announced act × tax_type.** A phased multi-step
   change is one row with a `phased_schedule`. Note the PIT-specific subtlety
   below.
5. **No `tar_make()` on API targets without explicit approval.** This skill makes
   no LLM API calls through the pipeline.
6. **Country-agnostic language.** Identify by the *concept* (the statutory tax on
   individuals' income), using the country's surface terms.

## Procedure

### Step 1: Setup and instrument config

Confirm the target country slug and its branch index. Load the instrument config
(inline — self-contained):

- **Concept:** the statutory tax on individual/personal income. PIT is usually a
  **progressive schedule**, not a single rate — track the **top marginal rate** as
  the headline series, and record bracket/threshold changes and the chargeable-
  income structure in `magnitude_note` / `phased_schedule`. Flag clearly when a
  "change" is a bracket shift rather than a top-rate change.
- **Surface terms / regex** (extend per country as needed):
  `individual income tax|personal income tax|cukai pendapatan individu|cukai pendapatan persendirian|personal tax|individual tax|top marginal|tax bracket|chargeable income`
- **Anchor document types:** Budget Speeches, Economic Reports, central-bank
  Annual Reports, medium-term plans.

Read the corpus pool (API-safe):

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  c1 <- tar_read(country_c1_measures)[[<branch_idx>]]
  cat(nrow(c1), "measures\n")'
```

### Step 2: Keyword scan

Filter `country_c1_measures$measure_name` by the PIT regex. Record the count and
the distinct surface forms with their years.

### Step 3: Semantic sweep

Read the keyword-matched measures *and their chunk text* (`country_chunks`), then
broaden to all income-tax surface forms in the pool to catch PIT events phrased
without the keywords. **Disambiguate from CIT**: a chunk may discuss both — keep
only the individual/personal-income provisions. Note each candidate with its
`doc_id` + `chunk_id`.

### Step 4: Recall recovery

Where a top-rate or major bracket change is implied but missing from C1, **read
the anchor source documents directly** from full text:

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  body <- tar_read(country_body)[[<branch_idx>]]
  doc  <- dplyr::filter(body, body == "Budget Speech", year == 2015)
  cat(paste(doc$text[[1]], collapse="\n--PAGE--\n"))'
```

Record each recovered event via `recovered_chunks` (chunk present but not
surfaced) and/or `recovered_evidence` (direct quote).

### Step 5: Consolidation

Group surface forms + recovered events into **announced acts** (one row per act ×
`PIT`). For each: extract `rate_from`/`rate_to`/`delta_pp` (top marginal rate),
`direction`, `announced_year`, `effective_year`, `effective_quarter` (if known),
and `phased_schedule` for multi-step changes. Capture bracket/threshold detail in
`magnitude_note`. Write the preliminary `exogenous_preliminary` + `exogeneity_quote`
and the `id_reasoning`.

### Step 6: Build the artifact

Assemble the contract tibble, the `member_chunks` manifest, and the **recall
scorecard**. Assign `shock_id` (`{ISO}-PIT-NN`).

#### PAUSE POINT — human review & stamp

Present, for review:

```
- The consolidated PIT shock table (act_label, top-rate from/to, years, direction, preliminary exogeneity)
- The recall scorecard (what C1 surfaced / missed / recovered)
- The member-chunk manifest counts per shock
- Open adjudication questions (top-rate vs bracket changes, consolidation, exogeneity)
```

Do NOT persist until the human confirms the events, the consolidation grain, the
top-rate-vs-bracket calls, and the preliminary reads.

### Step 7: Persist + document provenance

On confirmation, freeze the dataset and write its meta sidecar:

```r
Rscript -e 'library(qs2)
  qs_save(<shocks_tibble>, "data/validated/MY_PIT_shocks.qs")
  yaml::write_yaml(list(
    instrument = "PIT", country_iso = "MY", skill = "identify-pit",
    frozen_at = format(Sys.time()),
    git_hash = system("git rev-parse --short HEAD", intern = TRUE),
    reviewer = "<name>"),
    "data/validated/MY_PIT_shocks_meta.yml")'
```

Then create `notebooks/pit_identification.qmd` from the `cit_identification.qmd`
template (purpose, recall scorecard, headline rate table + step path, motivation/
preliminary-exogeneity table, member-chunk manifest, open questions).

## What This Skill Does NOT Do

- Does not call the LLM API through the pipeline (C2a re-run + C2b run later, gated).
- Does not assign the final motivation/exogeneity label (records a preliminary read only).
- Does not commit (human-owned).
- Does not use C0 acts as the event layer.
- Does not treat every bracket/threshold tweak as a headline shock — the top
  marginal rate is the headline series; record sub-changes as detail.

## Error Handling

- **Country branch not found:** confirm C1 deployment completed for the country.
- **CIT/PIT ambiguity in a chunk:** keep only individual/personal provisions; if
  genuinely both, the same chunk may be a member of both a CIT and a PIT shock.
- **Schedule vs single rate:** default the headline series to the top marginal
  rate; if the country has a flat PIT, treat it like CIT.
- **A recovered event's chunk is absent from `country_chunks`:** use
  `recovered_evidence`.
- **Human declines to stamp:** do not persist; record open questions and stop.

## Composability

- Invoked standalone or as step 2 of `/identify-tax-shocks`.
- Shares the output contract `docs/phase_1/tax_shock_schema.md` with
  `/identify-cit` and `/identify-vat` (procedures duplicated by design).
- The frozen `.qs` is read by `R/tax_shock_dataset.R::bind_tax_shocks()` via the
  `tax_shock_files` target.
- Follows `/quarto-style` when writing `pit_identification.qmd`.
