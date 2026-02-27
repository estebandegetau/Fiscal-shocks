# Dockerfile for Fiscal-shocks project
# R 4.5.0 + Python environment for PDF extraction and text analysis

FROM rocker/r-ver:4.5.0

LABEL maintainer="Esteban Degetau"
LABEL description="Research pipeline for fiscal shock identification from historical US government documents (Quarto 1.8.27, R 4.5.0, Python 3)"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV RENV_PATHS_CACHE=/renv/cache

# Install system dependencies for R packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    build-essential \
    cmake \
    g++ \
    gcc \
    gfortran \
    make \
    # Library dependencies for R packages
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    zlib1g-dev \
    # Additional R package dependencies (igraph, clipr, etc.)
    libglpk-dev \
    libx11-dev \
    # PDF processing (pdftools, qpdf)
    libpoppler-cpp-dev \
    poppler-data \
    libqpdf-dev \
    # Font and graphics libraries (systemfonts, ragg, textshaping)
    libfreetype6-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    # Unzip for font installation
    unzip \
    # Image libraries
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libwebp-dev \
    # ICU for text processing
    libicu-dev \
    # Git for package installation
    git \
    # Pandoc for document rendering
    pandoc \
    # Python
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    # Timezone data
    tzdata \
    # Utilities
    wget \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Libertinus fonts from GitHub (not available as apt package on Noble)
ARG LIBERTINUS_VERSION=7.040
RUN wget -q https://github.com/alerque/libertinus/releases/download/v${LIBERTINUS_VERSION}/Libertinus-${LIBERTINUS_VERSION}.zip \
    && unzip -q Libertinus-${LIBERTINUS_VERSION}.zip -d /tmp/libertinus \
    && mkdir -p /usr/share/fonts/opentype/libertinus \
    && find /tmp/libertinus -name '*.otf' -exec cp {} /usr/share/fonts/opentype/libertinus/ \; \
    && fc-cache -f \
    && rm -rf /tmp/libertinus Libertinus-${LIBERTINUS_VERSION}.zip

# Note: libv8-dev and libnode-dev are NOT installed due to Ubuntu Noble
# compatibility issues (libv8-dev doesn't exist, libnode-dev conflicts with
# NodeSource). This may affect the R V8 package if used.
# Node.js is installed separately from NodeSource below for Claude Code CLI.

# Install Node.js (required for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Install Quarto
ARG QUARTO_VERSION=1.8.27
RUN wget -q https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.deb \
    && dpkg -i quarto-${QUARTO_VERSION}-linux-amd64.deb \
    && rm quarto-${QUARTO_VERSION}-linux-amd64.deb

# Set up Python virtual environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r /tmp/requirements.txt

# Create renv cache directory
RUN mkdir -p /renv/cache

# Set working directory
WORKDIR /app

# Copy renv files first for better caching
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json

# Install renv and restore packages
RUN R -e "install.packages('renv', repos = 'https://cloud.r-project.org')" \
    && R -e "renv::restore(prompt = FALSE)"

# Copy project files
COPY . .

# Create directories for data and outputs
RUN mkdir -p data/raw data/processed _targets

# Default command - run the targets pipeline
CMD ["R", "-e", "targets::tar_make()"]
