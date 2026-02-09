#!/usr/bin/env python3
"""Pre-download and extract PDFs from domains that block datacenter IPs.

Some government websites (cbo.gov, ssa.gov) block HTTP requests from
datacenter/cloud IP ranges with 403 Forbidden. This script is designed
to be run on a machine with unrestricted internet access (e.g., a
laptop) to pre-populate the extraction cache used by pull_text_local().

Usage:
    # Step 1: Generate URL list with cache keys from R
    Rscript -e '
      source("R/pull_us.R")
      source("R/pull_text_local.R")
      library(dplyr)
      library(digest)
      get_us_urls() |>
        filter(source %in% c("cbo.gov", "ssa.gov")) |>
        mutate(cache_file = sapply(pdf_url, function(u)
          paste0(digest(u, algo = "md5"), ".json"))) |>
        readr::write_csv("data/blocked_urls.csv")
    '

    # Step 2: Download and extract (run on unrestricted machine)
    python python/download_blocked_pdfs.py data/blocked_urls.csv data/extracted/

    # Step 3: Re-run pipeline (cache hits skip re-downloading)
    # Rscript -e 'targets::tar_make()'
"""

import argparse
import csv
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: 'requests' package required. Install with: pip install requests",
          file=sys.stderr)
    sys.exit(1)

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "application/pdf,*/*",
}

MAX_RETRIES = 3
BACKOFF_BASE = 2  # seconds


def download_pdf(url: str, dest: str) -> bool:
    """Download a PDF with retries and exponential backoff.

    Returns True on success, False on failure.
    """
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = requests.get(url, headers=HEADERS, timeout=60, stream=True)
            resp.raise_for_status()
            with open(dest, "wb") as f:
                for chunk in resp.iter_content(chunk_size=8192):
                    f.write(chunk)
            return True
        except requests.RequestException as e:
            wait = BACKOFF_BASE ** attempt
            print(f"  Attempt {attempt}/{MAX_RETRIES} failed: {e}", file=sys.stderr)
            if attempt < MAX_RETRIES:
                print(f"  Retrying in {wait}s...", file=sys.stderr)
                time.sleep(wait)
    return False


def extract_pdf(pdf_path: str, output_json: str, script_path: str) -> bool:
    """Run pymupdf_extract.py on a local PDF file.

    Returns True on success, False on failure.
    """
    result = subprocess.run(
        ["python", script_path,
         "--input", pdf_path,
         "--output", output_json],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  Extraction error: {result.stderr.strip()}", file=sys.stderr)
        return False
    return Path(output_json).exists()


def main():
    parser = argparse.ArgumentParser(
        description="Download and extract PDFs from blocked domains"
    )
    parser.add_argument(
        "csv_file",
        help="CSV with columns: pdf_url, cache_file (and optionally year, source, body)"
    )
    parser.add_argument(
        "output_dir",
        help="Directory to write cache JSON files (e.g., data/extracted/)"
    )
    parser.add_argument(
        "--extract-script",
        default=None,
        help="Path to pymupdf_extract.py (auto-detected if not set)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be downloaded without actually downloading"
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        default=True,
        help="Skip URLs that already have cache files (default: True)"
    )

    args = parser.parse_args()

    # Resolve extract script path
    if args.extract_script:
        extract_script = args.extract_script
    else:
        extract_script = str(
            Path(__file__).parent / "pymupdf_extract.py"
        )

    if not Path(extract_script).exists():
        print(f"ERROR: Extract script not found: {extract_script}", file=sys.stderr)
        sys.exit(1)

    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)

    # Read CSV
    with open(args.csv_file, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        print("No URLs found in CSV", file=sys.stderr)
        sys.exit(1)

    # Validate required columns
    if "pdf_url" not in rows[0] or "cache_file" not in rows[0]:
        print("ERROR: CSV must have 'pdf_url' and 'cache_file' columns.",
              file=sys.stderr)
        print("Generate it from R using the command in --help.", file=sys.stderr)
        sys.exit(1)

    total = len(rows)
    print(f"Found {total} URLs to process", file=sys.stderr)

    # Filter already-cached
    if args.skip_existing:
        to_process = []
        skipped = 0
        for row in rows:
            cache_path = os.path.join(args.output_dir, row["cache_file"])
            if Path(cache_path).exists():
                skipped += 1
            else:
                to_process.append(row)
        if skipped:
            print(f"Skipping {skipped} already-cached files", file=sys.stderr)
        rows = to_process

    if not rows:
        print("All files already cached. Nothing to do.", file=sys.stderr)
        return

    if args.dry_run:
        print(f"\nDry run: would download {len(rows)} PDFs:", file=sys.stderr)
        for row in rows:
            src = row.get("source", "?")
            yr = row.get("year", "?")
            print(f"  [{src} {yr}] {row['pdf_url']}", file=sys.stderr)
        return

    # Process each URL
    success = 0
    failed = 0
    failed_urls = []

    for i, row in enumerate(rows, 1):
        url = row["pdf_url"]
        cache_file = row["cache_file"]
        cache_path = os.path.join(args.output_dir, cache_file)
        label = f"{row.get('source', '?')} {row.get('year', '?')}"

        print(f"\n[{i}/{len(rows)}] {label}: {os.path.basename(url)}",
              file=sys.stderr)

        # Download to temp file
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
            tmp_path = tmp.name

        try:
            if not download_pdf(url, tmp_path):
                print(f"  FAILED: Could not download", file=sys.stderr)
                failed += 1
                failed_urls.append(url)
                continue

            file_size = os.path.getsize(tmp_path)
            print(f"  Downloaded: {file_size / 1024:.0f} KB", file=sys.stderr)

            # Extract text
            if not extract_pdf(tmp_path, cache_path, extract_script):
                print(f"  FAILED: Extraction error", file=sys.stderr)
                failed += 1
                failed_urls.append(url)
                continue

            # Verify the output JSON
            with open(cache_path, encoding="utf-8") as jf:
                result = json.load(jf)
            n_pages = result.get("n_pages", 0)
            print(f"  OK: {n_pages} pages extracted → {cache_file}",
                  file=sys.stderr)
            success += 1

        finally:
            # Clean up temp PDF
            if Path(tmp_path).exists():
                os.unlink(tmp_path)

    # Summary
    print(f"\n{'='*60}", file=sys.stderr)
    print(f"Results: {success} success, {failed} failed, "
          f"{total - len(rows) - success - failed} skipped (cached)",
          file=sys.stderr)

    if failed_urls:
        print(f"\nFailed URLs:", file=sys.stderr)
        for url in failed_urls:
            print(f"  {url}", file=sys.stderr)


if __name__ == "__main__":
    main()
