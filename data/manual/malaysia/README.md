# Manually-downloaded Malaysian PDFs

This directory holds Malaysian fiscal-policy PDFs that cannot be fetched programmatically (anti-bot 403s, search-interface-only archives, landing-page navigation, or print-only sources). It is the human-verification half of the deployment pipeline.

The `country_urls` target produced by `R/pull_malaysia.R` enumerates the full target manifest with `access_status` flags. Rows with `access_status == "manual"` resolve at `tar_make()` time:

- File present at `data/manual/malaysia/<series>/<filename>.pdf` → `access_status = "manual_ready"`; the pipeline ingests it like any auto URL.
- File absent → `access_status = "manual_pending"`; the dashboard at `notebooks/verify_malaysia_urls.qmd` renders it as a clickable link for human download.

## Drop convention

| Series | Subdirectory | Filename pattern |
|---|---|---|
| Economic Report / *Tinjauan Ekonomi* | `economic_report/` | `<year>.pdf` |
| Budget Speech / *Ucapan Bajet* | `budget_speech/` | `<year>.pdf` |
| Bank Negara Malaysia Annual Report | `bnm_annual_report/` | `<year>.pdf` |
| Five-Year Plans + MTRs | `rmk/` | `rmk<plan>_{plan,mtr}_<year>.pdf` |
| Crisis booklets | `stimulus/` | named per `package_id` (e.g., `prihatin_2020.pdf`) |

The exact `local_path` for each row is in the `country_urls` manifest — see the dashboard.

## Workflow

1. Render the dashboard: `quarto render notebooks/verify_malaysia_urls.qmd` (or run via the `verify_malaysia_urls` target).
2. Open the rendered HTML and scroll to the *manual_pending* table. Each row has a clickable URL (direct PDF if known, else landing page) and a target local path.
3. Click each link, navigate to the PDF in your browser, save it to the displayed local path.
4. Re-render the dashboard to confirm the row flips to *manual_ready*.
5. When ready to ingest, run `tar_make(country_text)` to extract text from the dropped PDFs.

## Replicability

`*.pdf` files in this directory are **not** committed to git (per `.gitignore`). To preserve replicability, the pipeline produces `MANIFEST.csv` listing each downloaded file with its sha256. That manifest IS committed. Future re-runs verify your local copies match.

To regenerate the manifest after dropping new files:

```r
source("R/build_manual_manifest.R")
build_manual_manifest("malaysia")
```

(This helper does not yet exist; it is a follow-up once Phase 2 acquisition is far enough along to be worth checksumming.)
