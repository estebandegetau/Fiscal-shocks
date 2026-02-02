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

Recent advances in Large Language Models (LLMs) make this possible for the first time. This project builds a **validated, LLM-assisted pipeline** for fiscal shock identification:

1. **Phase 0 (US Benchmark)**: Train few-shot LLM models on 44 US fiscal acts with Romer & Romer labels to identify acts, classify motivations, and extract timing/magnitude
2. **Phase 1 (Malaysia Pilot)**: Deploy US-trained models to Malaysia documents (1980-2022), generating candidate dataset with expert validation to test cross-country transfer learning
3. **Phase 2 (SEA Scaling)**: Extend methodology to Indonesia, Thailand, Philippines, Vietnam

### Key Innovation

**Transfer Learning with Limited Training Data**: We demonstrate that LLMs trained on limited US data (44 labeled acts) can assist experts in identifying fiscal shocks cross-country with ≥80% agreement, reducing manual effort from months to weeks.

### Research Contribution

The contribution is **methodological**, not just dataset scale:
- Shows LLMs can transfer across countries without retraining
- Quantifies performance via expert agreement rates and error analysis
- Identifies where models succeed (act detection, motivation classification) and struggle (magnitude extraction)
- Methodology replicable beyond Southeast Asia

### Current Status

- **Phase 0**: IN PROGRESS
  - **Model A**: Rework in progress — redesigned as passage extractor (raw documents → fiscal shock discussions). See `docs/phase_0/model_A_extractor_design.md`
  - **Model B**: LOOCV evaluation complete on curated passages; robustness testing on extracted passages in progress
  - **Model C**: Implemented; awaiting robustness testing on extracted passages
- **Phase 1**: Strategic plan complete, ready for Malaysia deployment (see `docs/phase_1/malaysia_strategy.md` and `docs/phase_1/CLAUDE.md`)
- **Phase 2**: Not yet started

### Success Criteria

**Phase 0 uses two evaluation tracks:**

- **Track 1 (LOOCV)**: Leave-one-out cross-validation on human-curated passages — measures model quality in ideal conditions
- **Track 2 (Robustness)**: Performance on Model A extracted passages — measures end-to-end pipeline quality

**Target metrics:**

- Model A: Recall ≥90% on known US acts
- Model B: ≥80% accuracy (Track 1), ≥70% accuracy (Track 2)
- Model C: Correct year extraction ≥85%

**Phase 1 (Malaysia Pilot):**

- Expert agreement ≥80% on act identification
- Expert agreement ≥70% on motivation classification

### Data Constraints (IMPORTANT)

- **US training data**: 44 labeled fiscal acts (1945-2022), not 126 as originally assumed
- **Malaysia estimate**: 20-40 acts (1980-2022, 42-year political stable window)
- **Other SEA countries**: 20-60 acts each depending on political stability and archive quality
- **No ground truth labels** for Malaysia or other SEA countries (expert validation required)

### Strategic Framing

❌ **NOT**: "Fully automated pipeline generating 100+ acts per country"
✅ **YES**: "LLM-assisted methodology with expert validation, demonstrating cross-country transfer learning"

See `docs/two_pager.qmd` for full project description and `docs/phase_1/malaysia_strategy.md` for Phase 1 strategic plan.

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

Additional production pipeline targets exist for Model A extraction and robustness evaluation. See `_targets.R` for the complete list.

### Multi-Language Integration
- R calls Python scripts via `system2()` with JSON file interchange
- Environment variables `DOCLING_PYTHON` and `DOCLING_SCRIPT` configure Python paths
- `reticulate` available for inline Python in notebooks

### Key Directories

- `R/` - Utility functions (PDF extraction, URL fetching, model implementations)
- `python/` - Python utilities (Docling extraction, embeddings)
- `notebooks/` - Quarto analysis notebooks (extract, clean, embed, identify)
- `docs/` - Documentation and proposals
- `docs/phase_0/` - Phase 0 design documents (Model A extractor design, etc.)
- `docs/phase_1/` - Phase 1 strategy and expert review protocols
- `data/raw/` - Reference data (`us_shocks.csv`, `us_labels.csv`)
- `prompts/` - System prompts and few-shot examples for Models A, B, C
- `.claude/agents/` - Specialized Claude Code agent configurations

### Claude Code Agents

The project includes 5 specialized agents in `.claude/agents/` for different tasks:

- **document-extractor**: PDF extraction using Docling or pdftools
- **doc-writer**: Quarto documentation and research notebooks
- **pipeline-manager**: Targets pipeline management and debugging
- **shock-classifier**: Fiscal shock classification (Models A, B, C)
- **validation-analyst**: Agreement metrics and error analysis

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

### Table Rendering

**Use gt package for all tables in .qmd files:**
- gt works with both HTML and Typst output formats
- Basic pattern: `data %>% gt() %>% cols_label(...) %>% tab_options(table.width = pct(100))`
- Do NOT use kableExtra (incompatible with Typst rendering)

### Markdown Rendering in .qmd Files

**CRITICAL: Bullet lists require blank lines before them**

This applies to **both R code chunks AND markdown body text**.

#### In R Code Chunks

When using `cat()` with `results='asis'` in R code chunks to generate markdown, **you must include a blank line before bullet lists**:

```r
# ❌ WRONG - bullet list will not render correctly
cat("Some text:\n")
cat("- Bullet point 1\n")
cat("- Bullet point 2\n")

# ✅ CORRECT - note the \n\n (two newlines)
cat("Some text:\n\n")
cat("- Bullet point 1\n")
cat("- Bullet point 2\n")
```

**Pattern to look for:** `cat("text:\n")` followed by `cat("- bullet")` → change to `cat("text:\n\n")`

#### In Markdown Body

When writing bullet lists directly in markdown (outside R code chunks), **you must include a blank line before the list**:

```markdown
# ❌ WRONG - bullet list will not render correctly
**Some heading:**
- Bullet point 1
- Bullet point 2

# ✅ CORRECT - blank line before list
**Some heading:**

- Bullet point 1
- Bullet point 2
```

**Pattern to look for:** Text or heading followed immediately by `-` → add blank line between them

#### Why This Matters

**Why:** Markdown requires a blank line before block-level elements like bullet lists. Without it, the bullets render as running text.

**When this applies:**
- Before bullet lists (`- item`)
- Before numbered lists (`1. item`)
- Before block quotes (`> text`)
- Before code blocks (` ``` `)
- Both in R code chunks (`cat()`) and markdown body text

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