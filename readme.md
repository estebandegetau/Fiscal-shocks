# Fiscal Shocks: Scaling Narrative Fiscal Shock Identification with LLMs

Research data pipeline for identifying fiscal shocks (tax and spending policy changes) from historical US government documents (1946-present) using text extraction and LLM-based analysis.

**Authors:** Esteban Degetau and Agustín Samano

## Quick Start

### Prerequisites

- Docker or compatible container runtime
- VS Code with Dev Containers extension (recommended)
- 8GB+ RAM allocated to container
- 10GB+ free disk space

### Container Setup

#### Option 1: Using VS Code Dev Containers (Recommended)

1. Open this folder in VS Code
2. When prompted, click "Reopen in Container" (or use Command Palette: "Dev Containers: Reopen in Container")
3. Wait for container to build and start (first time: 5-10 minutes)
4. The container will automatically run `renv::restore()` after creation
5. Verify setup (see below)

#### Option 2: Using Docker Directly

```bash
# Build the container
docker build -t fiscal-shocks .

# Run the container
docker run -it --rm \
  --memory=8g \
  --memory-swap=8g \
  --cpus=4 \
  -v $(pwd):/app \
  fiscal-shocks
```

### Post-Setup Verification

Run the verification script to check everything is installed correctly:

```bash
./verify_setup.sh
```

Or verify manually:

```bash
# Verify Python environment
python --version          # Should show Python 3.12.x
pip list | grep -E "(docling|sentence-transformers|torch)"

# Verify R environment
R -e "renv::status()"
R -e "c('targets', 'crew', 'tidyverse', 'pdftools', 'quanteda') %in% installed.packages()[,1]"

# Verify Quarto
quarto --version
```

Expected output:
- Python 3.12.3 at `/opt/venv/bin/python`
- docling, sentence-transformers, and torch installed
- All key R packages: targets, crew, tidyverse, pdftools, quanteda, tidytext, rvest, googledrive
- Quarto 1.6.40 or later

### First Run

```R
# In R console or RStudio
library(targets)

# Visualize the pipeline
tar_visnetwork()

# Run the full pipeline
tar_make()

# Or run with parallel processing
tar_make_future()
```

## Development Workflow

### R (Targets Pipeline)

```R
# Restore environment (if packages are out of sync)
renv::restore()

# Run pipeline
tar_make()                    # Execute all targets
tar_make_future()             # With distributed computing (crew)
tar_read(<target_name>)       # Read specific target output
tar_visnetwork()              # Visualize pipeline dependencies
tar_outdated()                # Check what needs updating

# Install new packages
install.packages("package_name")
renv::snapshot()              # Update renv.lock
```

### Python (PDF Extraction)

```bash
# Extract text from PDF using Docling
python python/docling_extract.py \
  --input data/raw/document.pdf \
  --output data/processed/document.json

# Optional: Skip table structure parsing for faster extraction
python python/docling_extract.py \
  --input data/raw/document.pdf \
  --output data/processed/document.json \
  --no-table-structure

# Install additional Python packages
pip install <package_name>
pip freeze > requirements.txt  # Update requirements if needed
```

### Documentation (Quarto)

```bash
# Render all documents
quarto render

# Render specific directory
quarto render notebooks/

# Preview with live reload
quarto preview
```

## Project Structure

```
.
├── _targets.R              # Main pipeline definition
├── R/                      # R utility functions
│   ├── functions_stage01.R # Data acquisition
│   ├── functions_stage02.R # Text extraction
│   └── functions_stage03.R # Processing & filtering
├── python/                 # Python utilities
│   ├── docling_extract.py  # PDF extraction with Docling
│   └── embeddings.py       # Text embeddings
├── notebooks/              # Quarto analysis notebooks
│   ├── extract.qmd
│   ├── clean.qmd
│   ├── embed.qmd
│   └── identify.qmd
├── data/
│   ├── raw/               # Reference data (us_shocks.csv, us_labels.csv)
│   └── processed/         # Pipeline outputs
├── _targets/              # Targets cache (gitignored)
├── renv/                  # R package management
│   ├── activate.R
│   └── settings.json
├── renv.lock              # R package lockfile
├── requirements.txt       # Python dependencies
├── Dockerfile             # Main container definition
├── Dockerfile.lambda      # Lambda deployment container
├── .dockerignore          # Docker build exclusions (see note below)
├── .devcontainer/         # VS Code dev container config
├── verify_setup.sh        # Environment verification script
├── readme.md              # This file
└── CLAUDE.md              # AI assistant guidance
```

**Note on .dockerignore:** The Lambda-specific exclusions are currently commented out for development builds. If building for Lambda deployment, uncomment those sections.

## Technology Stack

### R Packages
- **Pipeline:** targets (orchestration), crew (parallel execution)
- **Data:** tidyverse, dplyr, tidyr, purrr
- **Text:** pdftools, quanteda, tidytext
- **Web:** rvest (scraping), googledrive (cloud storage)
- **Environment:** renv (package management)

### Python Packages
- **PDF:** docling (advanced PDF extraction)
- **NLP:** sentence-transformers (embeddings)
- **ML:** torch (deep learning backend)

### Tools
- **Documentation:** Quarto (with Typst and HTML output)
- **Version Control:** Git
- **Containerization:** Docker

## Data Sources

Historical US Government Documents (1946-present):
- Economic Report of the President (govinfo.gov, fraser.stlouisfed.org)
- Treasury Annual Reports (home.treasury.gov, fraser.stlouisfed.org)
- Budget Documents (fraser.stlouisfed.org)

## Troubleshooting

### R Package Issues

**Problem:** `renv::status()` shows out-of-sync packages
```R
# Solution: Restore from lockfile
renv::restore(prompt = FALSE)

# If specific package fails to install, try:
renv::install("package_name")
```

**Problem:** Missing system dependency errors during package installation
```bash
# Inside container, install system packages:
apt update
apt install -y <library-name>

# Common ones already included:
# - libglpk-dev (igraph)
# - libx11-dev (clipr)
# - libcurl4-openssl-dev (httr, curl)
# - libxml2-dev (xml2, rvest)
```

### Python Issues

**Problem:** Python packages not found
```bash
# Verify you're using the venv
which python  # Should be /opt/venv/bin/python

# Reinstall if needed
pip install -r requirements.txt
```

**Problem:** Docling extraction fails
```bash
# Check if input file exists and is a valid PDF
file <input.pdf>

# Try with --no-table-structure flag for faster extraction
python python/docling_extract.py --input <pdf> --output <json> --no-table-structure
```

### Container Issues

**Problem:** Container runs out of memory
```bash
# Increase memory in .devcontainer/devcontainer.json:
"runArgs": [
  "--memory=16g",      # Increase from 8g
  "--memory-swap=16g",
  "--cpus=4"
]
```

**Problem:** Container build fails
```bash
# Clear Docker cache and rebuild
docker system prune -a
docker build --no-cache -t fiscal-shocks .
```

### Known Limitations

- **libnode-dev:** Cannot be installed due to nodejs version conflicts in Ubuntu Noble. This affects the V8 R package. If you need V8 functionality, you may need to adjust the Dockerfile base image or install nodejs differently.
- **Large PDFs:** Very large PDF files (>100MB) may require significant memory and processing time with Docling.

## Environment Variables

The container sets these environment variables automatically:

```bash
TZ=UTC                                    # Timezone
RENV_PATHS_CACHE=/renv/cache             # R package cache
DOCLING_PYTHON=/opt/venv/bin/python      # Python interpreter for R→Python calls
DOCLING_SCRIPT=/workspaces/Fiscal-shocks/python/docling_extract.py  # Docling script path
```

## Updating Dependencies

### Adding R Packages

```R
# Install new package
install.packages("package_name")

# Update lockfile
renv::snapshot()

# Commit renv.lock to git
```

### Adding Python Packages

```bash
# Install new package
pip install package_name

# Update requirements.txt
pip freeze | grep package_name >> requirements.txt

# Or manually add to requirements.txt with version constraint
```

### Rebuilding Container After Dependency Changes

If `renv.lock` or `requirements.txt` changes:

**VS Code Dev Containers:**
1. Command Palette → "Dev Containers: Rebuild Container"
2. Wait for rebuild to complete

**Docker CLI:**
```bash
docker build --no-cache -t fiscal-shocks .
```

## Contributing

1. Create a feature branch
2. Make changes and test with `tar_make()`
3. Update `renv.lock` if R packages changed: `renv::snapshot()`
4. Update `requirements.txt` if Python packages changed
5. Run `./verify_setup.sh` to ensure everything works
6. Commit and create pull request

## Additional Documentation

- **CLAUDE.md:** Detailed guidance for Claude Code AI assistant
- **Targets pipeline guide:** https://books.ropensci.org/targets/
- **Docling documentation:** https://github.com/DS4SD/docling

## License

[Add your license here]

## Contact

Esteban Degetau - [contact information]
Agustín Samano - [contact information]
