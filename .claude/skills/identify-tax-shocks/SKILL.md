---
name: identify-tax-shocks
description: Orchestrate the per-instrument statutory tax-shock identification (CIT, PIT, consumption) for a country, then bind the frozen datasets and run C2a/C2b to add motivation and exogeneity. Produces the final statutory tax-change deliverable.
user-invocable: true
---

# Identify Statutory Tax Shocks (orchestrator)

Sequence the three per-instrument identification skills (`identify-cit`,
`identify-pit`, `identify-vat`) for a country, then run the pipeline tail that
binds their frozen datasets, re-runs C2a on any corpus chunks C1 omitted, and runs
the validated C2b classifier — producing a Vegh & Vuletin (2015)-style statutory
tax-change dataset **plus** motivation and exogeneity (`tar_read(tax_shocks)`).

This is a **thin sequencer with human gates**. It does not duplicate the
instrument procedures (each lives in its own self-contained skill) and it never
runs API-calling targets without explicit approval.

## When to Use

- You want the full statutory tax-change deliverable for a deployed country in one
  guided pass.
- Prerequisite: the country has completed C1 deployment and `country_body` /
  `country_chunks` / `country_c2a_evidence` are populated.

## Critical Rules

1. **Human gates at every boundary.** Each instrument ends at its own
   human-stamp PAUSE POINT; the orchestrator adds gates before each API target.
2. **No `tar_make()` on API targets without explicit approval** (Workflow
   Convention #5). `tax_shocks_evidence` (C2a re-run) and `tax_shocks_c2b` are
   API-calling and must be individually approved.
3. **Commit before API runs** (Convention #6): ensure the frozen datasets and any
   codebook/function edits are committed so the run is reproducible.
4. **Both exogeneity reads survive.** The deliverable keeps the preliminary
   narrative read *and* C2b's label; neither is dropped.
5. **Surgical, human-owned commits** (Conventions #13, Principle 4).

## Procedure

### Step 1: Confirm country and scope

Confirm the country slug and that its C1 deployment + C2a evidence exist. List
which instruments to run (default: all three).

### Step 2: Run the instrument passes (each gated)

Run, in order, pausing at each skill's human-stamp PAUSE POINT before continuing:

1. Run the `identify-cit` skill procedure (`.claude/skills/identify-cit/SKILL.md`).
2. Run the `identify-pit` skill procedure (`.claude/skills/identify-pit/SKILL.md`).
3. Run the `identify-vat` skill procedure (`.claude/skills/identify-vat/SKILL.md`).

Each freezes `data/validated/{ISO}_{INSTRUMENT}_shocks.qs` + meta and updates its
provenance notebook. Do not proceed to Step 3 until all requested instruments are
frozen and stamped.

#### PAUSE POINT 1 — confirm frozen inputs

Present the frozen files found and their shock counts:

```r
Rscript -e 'fs <- list.files("data/validated", pattern="_(CIT|PIT|CONSUMPTION)_shocks\\.qs$", full.names=TRUE)
  for (f in fs) cat(basename(f), nrow(qs2::qs_read(f)), "shocks\n")'
```

Confirm the set is complete before binding. Remind the user to commit the frozen
datasets (Convention #6) before any API run.

### Step 3: Bind (no API) and pre-flight

Build the bind target and inspect it (API-safe):

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  targets::tar_make(tax_shocks_identified)
  str(tar_read(tax_shocks_identified))'
```

Scoped freshness check (never full-graph — Convention #12):

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  print(tar_outdated(names = c("tax_shocks_identified","tax_shocks_evidence","tax_shocks_c2b","tax_shocks")))'
```

#### PAUSE POINT 2 — approve the C2a re-run (API)

The next target re-runs C2a only on member chunks lacking existing evidence (the
chunks C1 omitted). Present the estimated count of omitted chunks and request
explicit approval. On approval:

```r
Rscript -e 'library(targets); tar_config_set(store="_targets"); tar_make(tax_shocks_evidence)'
```

Confirm from the run log that C2a fired only on the omitted chunks.

#### PAUSE POINT 3 — approve C2b (API)

On explicit approval:

```r
Rscript -e 'library(targets); tar_config_set(store="_targets"); tar_make(tax_shocks_c2b)'
```

### Step 4: Assemble and present the deliverable

```r
Rscript -e 'library(targets); tar_config_set(store="_targets")
  tar_make(tax_shocks); str(tar_read(tax_shocks))'
```

Present the final dataset: per `tax_type` rate paths, the motivation/exogeneity
columns (both preliminary and C2b), and any shocks where the preliminary read and
C2b disagree (flag these for expert adjudication). Offer to render
`notebooks/tax_shocks.qmd`:

```bash
quarto render notebooks/tax_shocks.qmd
```

## What This Skill Does NOT Do

- Does not duplicate the instrument identification procedures.
- Does not run API targets without per-target approval.
- Does not adjudicate exogeneity (presents preliminary-vs-C2b disagreements for
  the human).
- Does not commit (human-owned).

## Error Handling

- **A requested instrument was not frozen / stamped:** stop at PAUSE POINT 1; do
  not bind a partial set unless the user explicitly chooses to.
- **`tax_shocks_evidence` re-runs C2a on more chunks than expected:** halt and
  review the member-chunk manifests — likely a recall sweep that pulled in
  non-evidence chunks.
- **C2b degenerate output:** inspect `tar_read(tax_shocks_c2b)` for parse
  failures; C2b v0.9.1 is frozen, so the fix is in the evidence bundle, not the
  codebook.
- **An instrument dataset is empty (e.g. no consumption tax):** the bind handles
  it; the deliverable simply has no rows for that `tax_type`.

## Composability

- Composes `/identify-cit`, `/identify-pit`, `/identify-vat` (each self-contained,
  each ending at its own human-stamp gate).
- Drives the `R/tax_shock_dataset.R` pipeline targets: `tax_shocks_identified` →
  `tax_shocks_evidence` → `tax_shocks_c2b` → `tax_shocks`.
- Reuses `run_c2a_deployment()` and `run_c2b_deployment()` unchanged (C2b v0.9.1
  frozen).
- Final notebook follows `/quarto-style`.
