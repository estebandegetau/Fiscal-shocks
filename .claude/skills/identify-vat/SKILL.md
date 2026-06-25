---
name: identify-vat
description: Agentic narrative identification of statutory broad consumption / indirect-tax (VAT/GST/SST) changes from the deployment corpus, consolidated into a human-stamped frozen shock dataset. Mirrors notebooks/cit_identification.qmd.
user-invocable: true
---

# Identify Consumption-Tax Statutory Shocks

Run an AI-assisted **narrative identification** pass over the deployment corpus to
build a clean dataset of a country's **statutory broad consumption / indirect-tax
changes** (VAT / GST / sales-and-service tax), the way
`notebooks/cit_identification.qmd` did for corporate income tax. The pipeline
(C1, C0) pre-screens candidate measures; this skill reads the surfaced evidence
*and the source documents directly*, consolidates scattered surface forms into
cohesive shocks, recovers events C1 missed, and freezes a human-stamped reference
dataset.

The output conforms to the shared contract in `docs/phase_1/tax_shock_schema.md`
(`tax_type = "CONSUMPTION"`). It is consumed by the `identify-tax-shocks`
orchestrator, which binds it with the CIT/PIT datasets and runs C2a/C2b for
motivation and exogeneity.

This skill is **self-contained** (its procedure is duplicated in `identify-cit`
and `identify-pit` by design). It produces a fresh provenance notebook
`notebooks/vat_identification.qmd` from the CIT template.

## When to Use

- You want a statutory consumption-tax dataset for a deployed country, enriched
  downstream with motivation + exogeneity.
- Invoked directly, or as the third instrument in `/identify-tax-shocks`.
- Prerequisite: the country has completed C1 deployment (`country_c1_measures`
  has a branch) and `country_body` / `country_chunks` are populated.
- Note: many SEA countries lack a Western-style VAT; the concept is the broad
  consumption/indirect tax in whatever local form (GST, SST, sales tax). If the
  country has none, the dataset may be legitimately empty — record that in the
  recall scorecard.

## Critical Rules

1. **Human confers meaning.** This skill identifies and proposes; the researcher
   adjudicates exogeneity and stamps the dataset (Research Companion Principle 1).
2. **Preliminary exogeneity is pending, never settled.** Carried alongside —
   never replacing — C2b's downstream label.
3. **Recall scorecard is mandatory.** Recall cannot be expert-validated from the
   dataset alone; the scorecard records what was searched and missed (including
   "no consumption tax in this period" when true).
4. **One row per narratively-announced act × tax_type.** A regime
   introduction/abolition and its rate is one announced act.
5. **No `tar_make()` on API targets without explicit approval.** This skill makes
   no LLM API calls through the pipeline.
6. **Country-agnostic language.** Identify by the *concept* (a broad tax on
   consumption / value added / sales of goods and services), using the country's
   surface terms (VAT, GST, SST, sales tax, …). Do not assume "VAT".

## Procedure

### Step 1: Setup and instrument config

Confirm the target country slug and its branch index. Load the instrument config
(inline — self-contained):

- **Concept:** the broad statutory tax on consumption / value added / sales of
  goods and services. **Regime events count as shocks:** introducing a GST/VAT is
  a `Hike`, abolishing it is a `Cut`, replacing one regime with another is two
  rows (abolition + introduction) or one act per the narrative.
- **Surface terms / regex** (extend per country as needed):
  `goods and services tax|GST|cukai barang dan perkhidmatan|sales and service tax|sales tax|service tax|SST|cukai jualan|cukai perkhidmatan|value.added|VAT|consumption tax`
- **Anchor document types:** Budget Speeches, Economic Reports, central-bank
  Annual Reports, medium-term plans.

Read the corpus pool (API-safe):

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  c1 <- tar_read(country_c1_measures)[[<branch_idx>]]
  cat(nrow(c1), "measures\n")'
```

### Step 2: Keyword scan

Filter `country_c1_measures$measure_name` by the consumption-tax regex. Record
the count and the distinct surface forms with their years.

### Step 3: Semantic sweep

Read the keyword-matched measures *and their chunk text* (`country_chunks`), then
broaden to catch regime introductions/abolitions and rate changes phrased without
the keywords. Note each candidate with its `doc_id` + `chunk_id`.

### Step 4: Recall recovery

Regime introductions/abolitions are high-salience but briefly stated — where one
is implied but missing from C1, **read the anchor source documents directly**:

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  body <- tar_read(country_body)[[<branch_idx>]]
  doc  <- dplyr::filter(body, body == "Budget Speech", year == 2014)
  cat(paste(doc$text[[1]], collapse="\n--PAGE--\n"))'
```

Record each recovered event via `recovered_chunks` and/or `recovered_evidence`.

### Step 5: Consolidation

Group surface forms + recovered events into **announced acts** (one row per act ×
`CONSUMPTION`). For each: set `rate_from`/`rate_to`/`delta_pp` (for an
introduction, `rate_from = 0`; for an abolition, `rate_to = 0`), `direction`,
`announced_year`, `effective_year`, `effective_quarter`, and `phased_schedule`.
Capture scope/base detail (exemptions, zero-rating) in `magnitude_note`. Write the
preliminary `exogenous_preliminary` + `exogeneity_quote` and the `id_reasoning`.

### Step 6: Build the artifact

Assemble the contract tibble, the `member_chunks` manifest, and the **recall
scorecard** (include a "no consumption tax in <period>" row where applicable).
Assign `shock_id` (`{ISO}-CONSUMPTION-NN`).

#### PAUSE POINT — human review & stamp

Present, for review:

```
- The consolidated consumption-tax shock table (act_label, rate from/to, years, direction, preliminary exogeneity)
- The recall scorecard (regimes found / missed / recovered; "none" where true)
- The member-chunk manifest counts per shock
- Open adjudication questions (regime replacement = one act or two; offset-package framing)
```

Do NOT persist until the human confirms the events, the regime-event treatment,
and the preliminary reads.

### Step 7: Persist + document provenance

On confirmation, freeze the dataset and write its meta sidecar:

```r
Rscript -e 'library(qs2)
  qs_save(<shocks_tibble>, "data/validated/MY_CONSUMPTION_shocks.qs")
  yaml::write_yaml(list(
    instrument = "CONSUMPTION", country_iso = "MY", skill = "identify-vat",
    frozen_at = format(Sys.time()),
    git_hash = system("git rev-parse --short HEAD", intern = TRUE),
    reviewer = "<name>"),
    "data/validated/MY_CONSUMPTION_shocks_meta.yml")'
```

Then create `notebooks/vat_identification.qmd` from the `cit_identification.qmd`
template.

## What This Skill Does NOT Do

- Does not call the LLM API through the pipeline (C2a re-run + C2b run later, gated).
- Does not assign the final motivation/exogeneity label (records a preliminary read only).
- Does not commit (human-owned).
- Does not use C0 acts as the event layer.
- Does not assume a Western-style VAT exists; an empty dataset is valid if the
  country had no broad consumption tax in the corpus period.

## Error Handling

- **Country branch not found:** confirm C1 deployment completed for the country.
- **No consumption tax in the period:** persist an empty (0-row) dataset with a
  recall scorecard documenting the absence; the orchestrator handles it.
- **Regime replacement (e.g. GST → SST):** surface at the PAUSE POINT whether it
  is one act or two; default to two rows (abolition + introduction).
- **A recovered event's chunk is absent from `country_chunks`:** use
  `recovered_evidence`.
- **Human declines to stamp:** do not persist; record open questions and stop.

## Composability

- Invoked standalone or as step 3 of `/identify-tax-shocks`.
- Shares the output contract `docs/phase_1/tax_shock_schema.md` with
  `/identify-cit` and `/identify-pit` (procedures duplicated by design).
- The frozen `.qs` is read by `R/tax_shock_dataset.R::bind_tax_shocks()` via the
  `tax_shock_files` target.
- Follows `/quarto-style` when writing `vat_identification.qmd`.
