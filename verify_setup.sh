#!/bin/bash
# Verification script for Fiscal Shocks container setup
# Run this after container creation to verify all dependencies are installed

set -e

echo "============================================"
echo "Fiscal Shocks Environment Verification"
echo "============================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 found: $(command -v $1)"
        return 0
    else
        echo -e "${RED}✗${NC} $1 not found"
        return 1
    fi
}

check_python_package() {
    if pip show "$1" &> /dev/null; then
        VERSION=$(pip show "$1" | grep Version | cut -d' ' -f2)
        echo -e "${GREEN}✓${NC} $1 installed (version $VERSION)"
        return 0
    else
        echo -e "${RED}✗${NC} $1 not installed"
        return 1
    fi
}

echo "--- System Commands ---"
check_command python
check_command R
check_command quarto
check_command git
echo ""

echo "--- Python Environment ---"
PYTHON_PATH=$(which python)
PYTHON_VERSION=$(python --version 2>&1)
echo "Python: $PYTHON_PATH"
echo "Version: $PYTHON_VERSION"

if [[ "$PYTHON_PATH" == "/opt/venv/bin/python" ]]; then
    echo -e "${GREEN}✓${NC} Using virtual environment at /opt/venv"
else
    echo -e "${RED}✗${NC} Not using expected virtual environment"
fi
echo ""

echo "--- Python Packages ---"
check_python_package "docling"
check_python_package "sentence-transformers"
check_python_package "torch"
echo ""

echo "--- R Environment ---"
R_VERSION=$(R --version | head -1)
echo "R Version: $R_VERSION"
echo ""

echo "--- R Packages ---"
R -q -e "
packages <- c('targets', 'crew', 'tidyverse', 'pdftools', 'quanteda', 'tidytext', 'rvest', 'googledrive', 'renv')
installed <- installed.packages()[,1]
for (pkg in packages) {
    if (pkg %in% installed) {
        cat(sprintf('\033[0;32m✓\033[0m %s installed\n', pkg))
    } else {
        cat(sprintf('\033[0;31m✗\033[0m %s NOT installed\n', pkg))
    }
}
" 2>/dev/null
echo ""

echo "--- R Environment Status ---"
R -q -e "renv::status()" 2>/dev/null || echo -e "${RED}Warning: renv::status() failed${NC}"
echo ""

echo "--- File System ---"
if [ -d "/workspaces/Fiscal-shocks" ]; then
    echo -e "${GREEN}✓${NC} Project directory exists: /workspaces/Fiscal-shocks"
else
    echo -e "${RED}✗${NC} Project directory not found"
fi

if [ -f "/workspaces/Fiscal-shocks/_targets.R" ]; then
    echo -e "${GREEN}✓${NC} Targets pipeline file exists"
else
    echo -e "${RED}✗${NC} _targets.R not found"
fi

if [ -d "/workspaces/Fiscal-shocks/python" ]; then
    echo -e "${GREEN}✓${NC} Python scripts directory exists"
else
    echo -e "${RED}✗${NC} python/ directory not found"
fi
echo ""

echo "--- Environment Variables ---"
echo "DOCLING_PYTHON=${DOCLING_PYTHON:-not set}"
echo "DOCLING_SCRIPT=${DOCLING_SCRIPT:-not set}"
echo "RENV_PATHS_CACHE=${RENV_PATHS_CACHE:-not set}"
echo ""

echo "============================================"
echo "Verification Complete"
echo "============================================"
echo ""
echo "If all checks passed with ✓, your environment is ready!"
echo "If any checks failed with ✗, refer to readme.md troubleshooting section."
echo ""
echo "Quick start:"
echo "  R -e 'targets::tar_make()'     # Run the pipeline"
echo "  python python/docling_extract.py --help  # PDF extraction help"
