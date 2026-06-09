# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Title**: "Scaling Narrative Fiscal Shock Identification with LLMs"
**Authors**: Esteban Degetau and Agustín Samano
**Affiliation**: World Bank
**Region**: Malaysia (pilot) → Southeast Asia (extension)

### Research Problem

For most emerging markets, we lack **consistent and comparable measures of exogenous fiscal shocks** — the cornerstone input required for credible fiscal policy analysis. The United States is the only country where this has been done systematically, through the "narrative approach" pioneered by Romer & Romer (2010). Their method uses historical documents to identify why taxes or spending changed, distinguishing exogenous shocks from policy actions responding to the business cycle.

Replicating this approach manually is costly. For low- and middle-income countries, it has simply never been feasible.

### Our Solution

Recent advances in Large Language Models (LLMs) make this possible for the first time. This project builds a **validated, LLM-assisted pipeline** for fiscal shock identification using two rigorous frameworks:

- **Romer & Romer (2010)**: 6-step methodology for identifying exogenous fiscal shocks (RR1-RR6)
- **Halterman & Keith (2025)**: 5-stage framework for rigorous LLM content analysis

The pipeline implements 4 domain-specific codebooks (C1-C4), each processed through the full H&K validation pipeline:

1. **Phase 0 (Codebook Development)**: Develop and validate codebooks C1-C4 on a subset of US chunks using H&K stages S0-S3 against 44 labeled acts
2. **Phase 1 (US Full Production)**: Run validated codebooks on the full `us_body` corpus; compare end-to-end results against `us_shocks.csv`
3. **Phase 2 (Malaysia Pilot)**: Deploy codebooks to Malaysia documents (1980-2022) with expert validation to test cross-country transfer learning
4. **Phase 3 (Regional Scaling)**: Extend methodology to Indonesia, Thailand, Philippines, Vietnam

### Key Innovation

**Country-Agnostic Transfer Learning**: Codebooks are designed to transfer across countries without retraining. We demonstrate that LLMs with limited US training data (44 labeled acts) can assist experts in identifying fiscal shocks cross-country with ≥80% agreement, reducing manual effort from months to weeks.

### Research Contribution

The contribution is **methodological**, not just dataset scale:
- Novel synthesis: First application of H&K validation framework to economic history/fiscal policy domain
- Shows LLMs can transfer across countries without retraining using country-agnostic codebooks
- Quantifies performance via H&K behavioral tests, zero-shot evaluation, and expert agreement rates
- Identifies where codebooks succeed and struggle
- Methodology replicable beyond Southeast Asia

### Current Status

- **Phase 0**: IN PROGRESS — Codebook development using C1-C4 framework (plus C0 Act Aggregator)
  - **C0 (Act Aggregator)**: Method-comparison phase. NOT an H&K S0-S3 codebook — methods are scored by RR-mapped recovery against the 49 R&R reference acts (keyword + Jaro-Winkler name gates + year alignment), with a Malaysia EN/BM paired stress test. Five methods compared in `notebooks/c0_aggregator.qmd` (M1 Jaro-Winkler, M2/M3 HDBSCAN unblocked + year-blocked, M4 hybrid embedding-NN + LLM pairwise judge [Phase B pending], M5 LLM canonical clustering). **M5 leads** (`prompts/c0_canonicalize.yml`, Haiku): v0.2.0 iter 2 (2026-06-03, commit 8c3b4a5). The bill-number identifier-equivalence clarification was net-neutral on all gates (RR recovery held 37/40-recoverable, fragmentation ~1.14, year alignment 0.978) and, on audit, failed its three target acts — Haiku merges trailing identifiers (`(H.R. 8371)`, `, Public Law 89-368`) but consistently splits the leading `H.R. NNNN, the <Name>` prefix despite the explicit rule (instruction-adherence/Haiku-capability limit, not a phrasing gap). Decision: report findings, leave a synthetic country-agnostic worked example as a possible path forward, carry forward the unbuilt over-merge year-spread diagnostic, pivot to EN/BM tests. See `prompts/iterations/c0.yml`. Note: C0 work began ahead of the documented Step-5/6/7 sequencing (see `docs/deltas.md` 2026-06-03). **Deployment model decision (iter 3, 2026-06-09, commit c5f8fa6):** at Malaysia deployment scale (877 single-shot surface forms, no ground truth) Haiku fragments acts it cannot attend to (GST split across 9 clusters; EN/BM "Cukai Barang dan Perkhidmatan" ↔ "Goods and Services Tax" not bridged) and commits at least one cross-act over-merge (Minimum Wages Order 2012 vs 2022), while **Sonnet 4.6** (streaming, `run_c0_deployment_stream`, commit 1da6f9f) consolidates these with zero detected cross-act over-merges (ARI 0.564; Sonnet's merges are a near-superset of Haiku's). Decision: **default to Sonnet for C0 deployment** (no codebook change — `c0_canonicalize.yml` held at v0.2.0; the downstream `country_c2b_inputs` switch is NOT yet wired). Sonnet has not been re-scored against the US RR-eval ground truth (see `docs/deltas.md` 2026-06-09). **EN/BM consistency test reworked around C0 (2026-06-03):** `notebooks/malay_consistency.qmd` now tests the full C1→C0→C2 pipeline — C0 runs at three scopes (per-doc / per-language / joint EN+BM), the within-doc JW clusterer and the Sonnet matcher + human-curation step are removed, and cross-language comparison is distributional (act / exo-endo / label-marginal / act-year tallies) + two timeline figures, no auxiliary-API matching (see `docs/deltas.md` 2026-06-03).
  - **C1 (Measure ID)**: v0.7.0 S3 GATE ACCEPTED for deployment (iter 33, 2026-05-20, commit 3663a80). Multi-measure schema (`measures[]` array) replaces v0.6.0's flat `measure_name`; per-measure `country` enum substituted at runtime from a `{country_iso}` token; long-form `c1_s2_results` (one row per chunk × measure); three S3 multi-measure failure-mode diagnostics (over-listing, country distribution, under-listing). S1 PASSED iter 30 after max_tokens=3072 bump; S2 iter 31 diagnostic gates missed within noise (combined recall 0.80, tier1 recall 0.88, precision 0.95 on N=840); S3 iter 32 diagnostic tests within noise vs v0.6.0; S3 manual audit iter 33 distribution **27A / 7B / 0C / 0D / 2E / 4F** (bias-corrected accuracy 81.8%, precision 77.8%, recall 87.5%, Tier 1 recall 80.0%, Tier 2 recall 100.0%). The 2 E errors (text_ids 3, 7 — both Tier 1) are v0.7.0-specific regressions: model recognized the relevant content but applied an overly restrictive "substantive" bar; hypothesized cause is the multi-measure schema raising the implicit threshold for what counts as a measure worth listing. v0.6.0 baseline (historical reference): S3 GATE PASSED at iteration 28, 31A/6B/0E/3F manual analysis, bias-corrected recall 100%, precision 83.3%. Three codebook gaps flagged for future C1 revision pass but non-blocking: foreign-credit/capital-controls scope (text_ids 23, 31); spending-side authorizations (text_ids 27, 28); overly-restrictive substantive threshold (text_ids 3, 7). **Post-validation prose change (commit 60f30eb, 2026-06-08):** a `{country}` token now injects the title-cased corpus-country name into the prose context line ("government of **Malaysia** (ISO code: `MY`)"), distinct from the `{country_iso}` schema enum (unchanged — output values stay `MY`/`OTHER`). This edits the validated v0.7.0 instructions block, so US S1-S3 dev targets and the deployment targets re-hash; version held at 0.7.0 and re-validation deferred under timeline constraints, trusting no deterioration (see `docs/deltas.md`).
  - **C2 (Motivation)**: S3 GATE PASSED, **v0.9.1 FROZEN as C2 deliverable** (iter 48, 2026-05-06, commit 2bfdf20). Decision: deploy to Malaysia (Phase 2). Iter 47 manual analysis (24A/2B/0C/0D/2E/11F; bias-corrected exogenous precision 0.833 with CI on n=18 likely containing 0.85 gate; sign accuracy on true-exogenous 0.955 PASSES) plus iter 48 automated S3 (Tests V/VI/VII + ablation) converge: model has internalized R&R-style fiscal motivation reasoning from pretraining; codebook adds modest calibration on top. Test V exclusion-criteria overall consistency 0.789 (combos 1-3: 100/92.3/92.3%; combo 4 modified-ev+modified-cb at 30.8% reveals partial — not absolute — exclusion-rule enforcement). Test VI generic-label degradation Δacc 0.034, change rate 0.079 (model not anchoring on label names). Test VII follows label-name slots 0.974 vs rotated definitions 0.026 (interpreted as priors-driven). Ablation drops small (≤7.7pp accuracy, ≤11.7pp wF1) with label_definition the largest single contributor (5.1pp); even all-removed retains 59% accuracy on the 4-way task. Two-codebook architecture: c2a_extraction.yml (v0.4.0, unchanged) + c2b_classification.yml (v0.9.1, frozen). Required two infra fixes to run S3 end-to-end (commits 3642033, 4e291a4 — latent v0.7.0+ schema-migration misses in S3 masked by no-classes early-return guard until v0.9.1 reintroduced classes). Three deferred recommendations carried forward: (i) iter 47's MINOR REVISION proposal (restore v0.6.1 causal-link priority rule analog inside SD; restore BCR1(b) analog inside LR for suspended-structural-provision cases) — deferred not rejected; revisit if Malaysia pilot reveals analogous E-category cases; (ii) Test V combo 4 finding documented as known zero-shot limitation; (iii) C4 sign-mapping worked-examples requirement.
  - **C3 (Timing)**: Not started
  - **C4 (Magnitude)**: Not started
  - See `docs/strategy.md` for authoritative methodology
- **Phase 1**: Deployment pipeline wired end-to-end — dynamic-branched country URLs → C1 → C0 → C2b act inventory (commit b92ee61 wired URLs → C2a evidence; commits 15664c7, 4c3f631 carried `country_iso` through and wired C0 + C2b). Cross-country headline notebook `notebooks/deployment.qmd` presents the per-country C1 → C0 → C2 inventory (commit fbd04b3). Re-validation gated on C1 v0.7.0 S1-S3 (and downstream cascade).
- **Phase 2**: BLOCKED on C0 (Act Aggregator) readiness per 2026-05-18 strategy update. Sequencing plan (`docs/deltas.md` 2026-05-18): C1 v0.7.0 implemented + S1-S3 re-validation complete (Step 4 ✅, closed 2026-05-20 iter 33); next is C2a v0.6.0 (Step 5), C2 re-validation (Step 6), C0 codebook (Step 7). See `docs/phase_1/malaysia_strategy.md` and `docs/phase_1/CLAUDE.md`.
- **Phase 3**: Not yet started

### Success Criteria

**Phase 0 uses H&K 5-stage validation per codebook:**

- **S0 (Codebook Prep)**: Machine-readable definitions with domain expert approval
- **S1 (Behavioral Tests)**: Legal outputs (100%), memorization (100%), order sensitivity (<5%)
- **S2 (Zero-Shot Eval)**: Single-pass zero-shot classification on chunk test set with primary metrics per codebook
- **S3 (Error Analysis)**: Documented failure patterns and ablation studies
- **S4 (Fine-Tuning)**: Last resort if S3 shows unacceptable patterns AND codebook improvements exhausted

**Target metrics per codebook:**

- C1 (Measure ID): Tier 1 Recall ≥95%, Combined Recall ≥90%, Precision ≥70% (all diagnostic benchmarks, not hard gates — S3 manual audit is the actual gate)
- C2 (Motivation, v0.9.0): Exogenous Precision ≥85% (binary, derived from 4-way label), Sign Accuracy on True-Exogenous ≥90%
- C3 (Timing): Exact Quarter ≥85%, ±1 Quarter ≥95%
- C4 (Magnitude): MAPE <30%, Sign Accuracy ≥95%

**Phase 2 (Malaysia Pilot):**

- Expert agreement ≥80% on measure identification (C1)
- Expert agreement ≥70% on motivation classification (C2)

### Data Constraints (IMPORTANT)

- **US training data**: 44 labeled fiscal acts (1945-2022), not 126 as originally assumed
- **Malaysia estimate**: 20-40 acts (1980-2022, 42-year political stable window)
- **Other SEA countries**: 20-60 acts each depending on political stability and archive quality
- **No ground truth labels** for Malaysia or other SEA countries (expert validation required)

### Strategic Framing

❌ **NOT**: "Fully automated pipeline generating 100+ acts per country"
✅ **YES**: "LLM-assisted methodology with expert validation, demonstrating cross-country transfer learning"

See `docs/strategy.md` for authoritative methodology, `docs/two_pager.qmd` for project description, and `docs/phase_1/malaysia_strategy.md` for Phase 2 (Malaysia) strategic plan.

## Development Commands

### R Environment
```R
# Restore R environment (run first time or after changes)
renv::restore()

library(targets)
# Run the targets pipeline
tar_make()                    # Execute all targets
tar_make_future()             # With distributed computing (crew)
tar_read(<target_name>)       # Read specific target output
tar_visnetwork()              # Visualize pipeline dependencies
```

### Python Environment

**Inside the Dev Container:**
Python is pre-configured with a virtual environment at `/opt/venv`. No setup needed - just use Python directly:
```bash
pip install <package>  # If you need additional packages
```

### Quarto Documentation
```bash
quarto render                 # Render all documents
quarto render notebooks/      # Render notebook subdirectory only
```

### Testing
```R
# Run test file (exploratory, not a formal test framework)
source("tests/test_pull.r")
```

## Architecture

### Pipeline (Targets-based)
The project uses `{targets}` for reproducible data pipelines with `crew` for parallel execution:

1. **Data Acquisition**: URL lists for ERP, Budget, and Treasury reports → PDF downloads
2. **Text Extraction**: PyMuPDF (Python) + pdftools (R) for PDF → text
3. **Processing**: Text cleaning → Document structuring → Paragraph extraction
4. **Filtering**: Keyword-based relevance filtering using `relevance_keys`

Key targets: `us_urls`, `us_text`, `us_body`, `aligned_data`, `chunks`, `c1_chunk_data`, `c1_s2_test_set`, `c1_s2_results`, `c1_s2_eval`, `c1_s3_test_set`, `c1_s3_results`, `c2_input_file`, `c2_input_data`, `c2a_s1_results`, `c2b_s1_results`, `c2_s2_results`, `c2_s2_eval`, `c2_s3_results`

See `_targets.R` for the complete list.

### Stage Independence

Each evaluation stage (S1, S2, S3) has independent targets, model configs, and test sets. Modifying one stage must not invalidate another stage's cached results. For example, `c1_s3_results` depends on `c1_s3_test_set` and `c1_codebook`, not on `c1_s2_results`. This was enforced after S3 was decoupled from S2 (see `docs/deltas.md`, 2026-03-07).

### Multi-Language Integration
- R calls Python scripts via `system2()` with JSON file interchange
- `reticulate` available for inline Python in notebooks

### Key Directories

- `R/` - Utility functions (PDF extraction, URL fetching, codebook implementations)
- `python/` - Python utilities (PyMuPDF extraction, data parsing)
- `notebooks/` - Quarto analysis notebooks (extract, clean, embed, identify)
- `docs/` - Documentation and proposals
- `docs/strategy.md` - Authoritative methodology document (C1-C4 + H&K framework)
- `docs/methods/` - Reference methodology documents (R&R, H&K)
- `docs/phase_0/` - Phase 0 (Codebook Development) implementation context
- `docs/phase_1/` - Phase 2 (Malaysia Pilot) strategy and expert review protocols
- `docs/archive/` - Historical Model A/B/C documentation (superseded)
- `data/raw/` - Reference data (`us_shocks.csv`, `us_labels.csv`)
- `data/validated/` - Frozen pipeline results (e.g., `c2_input_data.qs`) to decouple cross-codebook dependencies
- `prompts/` - YAML codebooks (C1-C4) and few-shot examples
- `.claude/agents/` - Specialized Claude Code agent configurations

### Claude Code Agents

The project includes 10 specialized agents in `.claude/agents/` organized by function:

**Development:**
- **codebook-developer**: Draft YAML codebooks (S0), interactive behavioral tests (S1)

**Code Production & Review:**
- **r-coder**: Write R functions following tidyverse idioms and targets integration
- **code-reviewer**: Technical review (haiku) — R best practices, API safety, no side effects
- **strategy-reviewer**: Strategic review — verify implementation matches `docs/strategy.md`, consults domain specialists

**Domain Specialists:**
- **fiscal-policy-specialist**: R&R methodology, motivation categories, exogeneity criteria
- **llm-eval-specialist**: H&K framework, behavioral tests (S1-S3), ablation studies, error analysis

**Infrastructure:**
- **pipeline-manager**: Targets pipeline definitions, `tar_make()`, debugging
- **document-extractor**: PDF extraction using PyMuPDF or pdftools

**Documentation:**
- **doc-writer**: Quarto notebooks and documentation
- **notebook-reviewer**: Verify notebooks evaluate what we intend

Use these agents via the Task tool for specialized work.

## Research Companion Principles

These principles shape Claude's role in this research project. They motivate the workflow conventions that follow. See `docs/onboarding.qmd` for the full treatment.

1. **Human confers meaning.** Claude pattern-matches against codebook definitions but does not understand what exogeneity means for causal identification. Never present classification outputs as research findings; present them as inputs requiring human interpretation.
2. **Delegate instrumental, own the core.** PDF extraction, pipeline plumbing, and documentation sync are fully delegable. Codebook design, success criteria, and error interpretation are human-owned. When uncertain whether something is core, ask rather than decide.
3. **Credibility tracks involvement.** The human must have lived through the iteration history to defend decisions at peer review. Claude's role is to make that history legible (iteration logs, structured diagnoses), not to bypass it.
4. **Commits belong to humans.** Claude can analyze, propose, and challenge. The decision ("we will do this, not that") belongs to the human and is recorded in the iteration log with date, context, and rationale.
5. **Error recoverability heuristic.** AI owns tasks where errors are recoverable (code, metrics, YAML validation). Humans own tasks where errors compound silently (research design, interpretation, cost authorization).

## Workflow Conventions

These rules govern how Claude Code operates in this project. They prevent recurring friction patterns identified during codebook development.

1. **Plan-first mode.** When asked to diagnose, investigate, or propose, present findings and wait. Do NOT implement changes or run code unless explicitly told to.
2. **Root cause first.** When something fails, identify the root cause before proposing a fix. Do not patch symptoms (e.g., don't fix test implementation when the codebook example is the problem).
3. **Model ID validation.** Before writing any model parameter, verify against known valid IDs. Current valid: `claude-haiku-4-5-20251001`, `claude-sonnet-4-20250514`. Flag any legacy IDs (e.g., `claude-3-5-sonnet-20241022`).
4. **Prefer existing files.** Search with Glob/Grep before creating new files. Duplicate implementations create maintenance burden.
5. **NO autonomous API calls.** Never run `tar_make()` on API-calling targets without explicit user approval. Read-only operations (`tar_read()`, `tar_outdated()`, `tar_visnetwork()`) are *API-safe* (no LLM cost), but "API-safe" is not "compute-cheap": a **full-graph `tar_outdated()` can be slow or hang** on this pipeline and may load workers. Prefer scoped checks (see #12).
6. **Commit before pipeline runs.** Before running API-calling targets, ensure no uncommitted changes to codebook YAML or R function files. The iteration log stores git hashes for reproducibility.
7. **One change at a time.** When iterating on a codebook, change one component per iteration. This makes the iteration log interpretable and supports ablation-style reasoning.
8. **Pipeline data validation.** After `tar_make()` completes, verify result shape with `tar_read(<target>) |> str()` before proceeding.
9. **Quarto render safety.** Always render specific files (`quarto render notebooks/c1_measure_id.qmd`), never the full project. After editing figures or tables, render to verify before committing; render **both HTML and Typst** when the figure/table is paper-bound (the cross-format bridge). Skip the Typst render for trivial, non-paper edits.
10. **Strategy reconciliation.** After a stage gate crossing (S1/S2/S3 pass) or when 3+ unresolved entries accumulate in `docs/deltas.md`, run `/strategy-sync` to reconcile implementation deltas with strategy docs. This is a human-driven reflection exercise: Claude challenges the user's reasoning, the user justifies decisions, and the rationale is recorded as an audit trail.
11. **Grep before editing.** When modifying a parameter or config value, first grep the entire codebase for every reference. Show all occurrences to the user and propose a plan to update ALL of them consistently. Never assume a single-file fix is sufficient.
12. **Verify target freshness.** Before reviewing pipeline results, check that evaluation targets have been rebuilt for the current codebook version. Use a **scoped** check on the specific affected targets (`tar_outdated(names = ...)` or `tar_meta(fields = ...)` filtered to those targets), **never a full-graph `tar_outdated()`** (it can hang on this pipeline). Flag upfront if any check could spin a crew/callr worker before running it. Do not review stale outputs.
13. **Surgical commits.** Stage only files relevant to the current task; **never `git add .`**. Preserve the user's unrelated work-in-progress, and show the committed diff. The decision to commit belongs to the human (see Research Companion Principle 4).
14. **Preserve target hashes.** When adding diagnostic or probe tests (e.g. UMAP, FP32 quantization), add them **without invalidating existing targets**. Confirm with a scoped `tar_outdated(names = ...)` that the existing targets' hashes are preserved.

### Multi-Agent Workflow Patterns

Three reusable patterns for parallel agent coordination:

- **Pattern 1: Codebook Review.** Two specialist agents (`fiscal-policy-specialist` + `llm-eval-specialist`) review a proposed codebook change in parallel. Main session synthesizes their feedback for the user.
- **Pattern 2: Pre-Pipeline Validation.** `pipeline-manager` + `strategy-reviewer` verify target readiness in parallel before user runs `tar_make()`.
- **Pattern 3: Post-Stage Documentation.** `doc-writer` + `notebook-reviewer` update and verify a notebook in parallel after a stage gate is crossed.

## Data Sources

US Government Documents (1946-present):
- Economic Report of the President (govinfo.gov, fraser.stlouisfed.org)
- Treasury Annual Reports (home.treasury.gov, fraser.stlouisfed.org)
- Budget Documents (fraser.stlouisfed.org)

## Technology Stack

- **R**: targets, crew, tidyverse, pdftools, quanteda, tidytext, rvest, googledrive, tinytable (for tables in new .qmd files; existing notebooks still use gt), pacman (for setup-chunk package loading)
- **Python**: pymupdf (PDF extraction)
- **Documentation**: Quarto with Typst and HTML output, Chicago Author-Date citations

### Quarto Style Guide

See `.claude/skills/quarto-style/SKILL.md` for complete Quarto conventions (tables, markdown formatting, plots, citations, writing style, setup chunks). Key rules:

- **tinytable (`tt()`) for all tables** (never gt or kableExtra in new documents; existing notebooks may still use gt and migrate when next edited)
- **`pacman::p_load()` instead of `library()`** for setup chunks
- **Blank line before bullet lists** in both markdown body and `cat()` output
- **Never end a section with a `---` divider**
- **Minimize em dashes**

### Iteration Logging

Use `/log-iteration` after running a pipeline stage (S1/S2/S3) to record what changed, what the metrics show, and what to do next. Creates YAML entries in `prompts/iterations/<codebook>.yml` with auto-gathered metrics and git commit hashes. See `.claude/skills/log-iteration/SKILL.md`.

### Iteration Cycle

Use `/iterate` to run the full codebook iteration cycle: pre-flight, pipeline review, and iteration logging with human decision points between each step. Composes `/pre-flight`, `/review-iteration`, and `/log-iteration`. See `.claude/skills/iterate/SKILL.md`.

### Strategy Reconciliation

Use `/strategy-sync` when unresolved deltas accumulate in `docs/deltas.md` (doc-sync will nudge you at 3+). The skill groups related deltas, challenges their implications against the full strategy, and records your justifications. See `.claude/skills/strategy-sync/SKILL.md`.

## {targets} Pipeline Conventions

### Reference
Official guide: https://books.ropensci.org/targets/

### Our Project Structure
```
_targets.R           # Main pipeline definition
R/
  functions_stage01.R
  functions_stage02.R
  functions_stage03.R
  prepare_training_data.R
_targets/           # Generated by targets (gitignored)
```

### **CRITICAL: Data Generation Policy**

**ALL data processing and generation MUST go through the `_targets` pipeline.**

✅ **DO:**
- Define all data generation as targets in `_targets.R`
- Put logic in functions in `R/` directory
- Use `tar_make()` to generate data
- Save outputs via targets `format` parameter (rds, parquet, qs)

❌ **DON'T:**
- Run standalone scripts that create data files
- Manually save data with `saveRDS()`, `write_csv()`, etc. outside targets
- Create data in `data/processed/` without a corresponding target
- Alter data or example files manually

**Rationale:** The targets pipeline ensures:
- Reproducibility (tracked dependencies)
- Caching (avoid re-running expensive operations)
- Lineage (know how each dataset was created)
- Documentation (targets graph shows data flow)

**Example:**
```r
# WRONG - manual script
aligned <- align_labels_shocks(labels, shocks)
saveRDS(aligned, "data/processed/aligned_data.rds")

# CORRECT - targets pipeline
tar_target(
  aligned_data,
  align_labels_shocks(us_labels, us_shocks, threshold = 0.85)
)
# Access via: tar_read(aligned_data)
```

### Key Conventions

**Target naming:**
- Stage outputs: `data_stage_01`, `data_stage_02`, etc.
- Intermediate objects: `stage_01_validated`, `stage_01_cleaned`
- Final outputs: `final_report`, `final_dataset`

**Function style:**
- All target functions in R/ directory
- One function per conceptual step
- Functions are PURE - no side effects, return objects
- File I/O handled by targets format, not inside functions

**Target definition pattern:**
```r
tar_target(
  data_stage_01,
  clean_stage_01_data(
    input = raw_data,
    config = config_params
  ),
  format = "parquet"  # or "qs", "rds"
)
```

**Branching (if we use it):**
```r
# Dynamic branching over cohorts
tar_target(
  results_by_cohort,
  analyze_cohort(data_stage_02, cohort),
  pattern = map(cohort)
)
```

**Branch heavy API-calling targets per document.** Pipeline steps that make per-chunk or per-measure LLM API calls (C1 / C2a / C0 deployment) should be dynamically branched per `doc_id` — a `tarchetypes::tar_group_by(doc_id)` source feeding `pattern = map(...)` steps with default vector iteration, so `tar_read()` still returns a combined tibble and pooled downstream steps recombine via the aggregated value. This keeps incremental corpus changes cheap: adding or editing one document re-runs only that document's branches, not the whole step. Reference implementation: the Malaysia consistency `malay_er_*` chain (2026-06-05). Caveat: dynamic branch identity is positional — appended documents are fully cheap, but a mid-sequence insertion shifts and re-runs the branches after it (use static `tar_map` keyed by `doc_id` if full insertion-robustness is required).

**File targets:**
- Use `tar_target(format = "file")` for external files
- Always return file path as character
- Example: reports, plots saved to disk


**DO:**
- ✅ Keep _targets.R clean - just target definitions
- ✅ All logic in R/functions_*.R
- ✅ Use tar_option_set() for global settings
- ✅ Use tarchetypes helpers (tar_file_read, etc.)

**DON'T:**
- ❌ Define functions inline in _targets.R
- ❌ Use side effects in target functions (no write.csv inside functions)
- ❌ Hardcode paths - use here::here() or pass as arguments

### Running Pipeline
```r
targets::tar_make()          # Run full pipeline
targets::tar_make(stage_01)  # Run specific target
targets::tar_visnetwork()    # Visualize dependency graph
targets::tar_outdated(names = ...)  # Check specific targets (scoped — avoid the full-graph call, it can hang; see Workflow Convention #12)
```
```

## For immediate help, prompt:
```
"I'm using {targets} for the pipeline. Please review the 
targets documentation at https://books.ropensci.org/targets/
and our project structure.

For Stage 1 implementation:
- Put the data processing logic in R/functions_stage01.R
- Define the target in _targets.R following our naming convention
- Use format = 'parquet' for the output
- Show me both files after implementation"