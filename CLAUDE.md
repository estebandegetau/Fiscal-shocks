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
- Quantifies performance via H&K behavioral tests, LOOCV evaluation, and expert agreement rates
- Identifies where codebooks succeed and struggle
- Methodology replicable beyond Southeast Asia

### Current Status

- **Phase 0**: IN PROGRESS — Codebook development using C1-C4 framework
  - **C1 (Measure ID)**: Not started
  - **C2 (Motivation)**: Not started
  - **C3 (Timing)**: Not started
  - **C4 (Magnitude)**: Not started
  - See `docs/strategy.md` for authoritative methodology
- **Phase 1**: Not yet started (depends on Phase 0 codebook validation)
- **Phase 2**: Strategic plan complete, ready for Malaysia deployment after Phase 1 (see `docs/phase_1/malaysia_strategy.md` and `docs/phase_1/CLAUDE.md`)
- **Phase 3**: Not yet started

### Success Criteria

**Phase 0 uses H&K 5-stage validation per codebook:**

- **S0 (Codebook Prep)**: Machine-readable definitions with domain expert approval
- **S1 (Behavioral Tests)**: Legal outputs (100%), memorization (100%), order sensitivity (<5%)
- **S2 (Zero-Shot Eval)**: LOOCV on 44 US acts with primary metrics per codebook
- **S3 (Error Analysis)**: Documented failure patterns and ablation studies
- **S4 (Fine-Tuning)**: Last resort if S3 shows unacceptable patterns AND codebook improvements exhausted

**Target metrics per codebook:**

- C1 (Measure ID): Recall ≥90%, Precision ≥80%
- C2 (Motivation): Weighted F1 ≥70%, Exogenous Precision ≥85%
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
python python/docling_extract.py --input <pdf_path> --output <json_output>
pip install <package>  # If you need additional packages


### Docling PDF Extraction (Python subprocess)
```bash
python python/docling_extract.py --input <pdf_path> --output <json_output> [--no-table-structure]
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
2. **Text Extraction**: `pdftools` (R) or Docling (Python) for PDF → text
3. **Processing**: Text cleaning → Document structuring → Paragraph extraction
4. **Filtering**: Keyword-based relevance filtering using `relevance_keys`

Key targets: `erp_urls`, `budget_urls`, `annual_report_urls`, `us_text`, `documents`, `paragraphs`, `relevant_paragraphs`

Additional production pipeline targets will be added for codebook evaluation and robustness testing. See `_targets.R` for the complete list.

### Multi-Language Integration
- R calls Python scripts via `system2()` with JSON file interchange
- Environment variables `DOCLING_PYTHON` and `DOCLING_SCRIPT` configure Python paths
- `reticulate` available for inline Python in notebooks

### Key Directories

- `R/` - Utility functions (PDF extraction, URL fetching, codebook implementations)
- `python/` - Python utilities (Docling extraction, embeddings)
- `notebooks/` - Quarto analysis notebooks (extract, clean, embed, identify)
- `docs/` - Documentation and proposals
- `docs/strategy.md` - Authoritative methodology document (C1-C4 + H&K framework)
- `docs/methods/` - Reference methodology documents (R&R, H&K)
- `docs/phase_0/` - Phase 0 (Codebook Development) implementation context
- `docs/phase_1/` - Phase 2 (Malaysia Pilot) strategy and expert review protocols
- `docs/archive/` - Historical Model A/B/C documentation (superseded)
- `data/raw/` - Reference data (`us_shocks.csv`, `us_labels.csv`)
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
- **llm-eval-specialist**: H&K framework, behavioral tests, LOOCV, error analysis

**Infrastructure:**
- **pipeline-manager**: Targets pipeline definitions, `tar_make()`, debugging
- **document-extractor**: PDF extraction using Docling or pdftools

**Documentation:**
- **doc-writer**: Quarto notebooks and documentation
- **notebook-reviewer**: Verify notebooks evaluate what we intend

Use these agents via the Task tool for specialized work.

## Data Sources

US Government Documents (1946-present):
- Economic Report of the President (govinfo.gov, fraser.stlouisfed.org)
- Treasury Annual Reports (home.treasury.gov, fraser.stlouisfed.org)
- Budget Documents (fraser.stlouisfed.org)

## Technology Stack

- **R**: targets, crew, tidyverse, pdftools, quanteda, tidytext, rvest, googledrive, gt (for tables in .qmd files)
- **Python**: docling (PDF extraction), sentence-transformers (embeddings), torch
- **Documentation**: Quarto with Typst and HTML output, Chicago Author-Date citations

### Quarto Style Guide

See `.claude/skills/quarto-style/SKILL.md` for complete Quarto conventions (tables, markdown formatting, plots, citations, writing style, setup chunks). Key rules:

- **gt for all tables** (never kableExtra)
- **Blank line before bullet lists** in both markdown body and `cat()` output
- **Never end a section with a `---` divider**
- **Minimize em dashes**

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
targets::tar_outdated()      # Check what needs updating
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