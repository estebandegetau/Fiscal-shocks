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

## Provenance notes

Manual corrections to dropped binaries (not reconstructable from git, since `*.pdf` is gitignored):

- **2026-06-04 — Economic Report 2020/2021 split.** The downloaded `economic_report/2020.pdf` was two reports concatenated: *Economic Outlook 2020* (EN, pp. 1–124) followed by *Economic Outlook 2021* (EN, pp. 125–322). This inflated the EN-2020 measure count in `notebooks/malay_consistency.qmd` (the −11 BM−EN drift). Split at the p124/p125 boundary into `2020.pdf` (pp. 1–124, 124 pp) and a new `2021.pdf` (pp. 125–322, 198 pp, English EO2021). The pre-existing `2021.pdf` (206 pp, *Tinjauan Ekonomi 2021*, BM) was renamed to `2021_bm.pdf`, making 2021 a full EN+BM pair (MANIFEST 2021 row flipped `BM,FALSE,TRUE` → `EN,TRUE,TRUE`). A separate, redundant image-based BM 2021 copy dropped in chapter fragments (`_inbox/{prakata,kata_pengantar,Bab1-4,carta_*}.pdf`) was routed to `_inbox/_excluded/` (lower quality, lacks the statistical annex; the existing 206 pp text-extractable file was kept).

- **2026-06-05 — Economic Report 2023 EN/BM pairing.** The on-disk `economic_report/2023.pdf` was actually the **BM** *Tinjauan Ekonomi 2023* (214 pp), mis-filed without the `_bm` suffix; `parse_pdf_path()` keys language off `_bm`, so it was being ingested as English (`MY_ECON_REPORT-2023`, `doc_language="en"`) — a latent BM-as-EN leak. Renamed it to `2023_bm.pdf`. The EN side was assembled from the 17 part-PDFs in `_inbox/2023_en/` (the full *Updates on Economic and Fiscal Outlook and Revenue Estimates 2023*) via PyMuPDF `insert_pdf()` into a new `2023.pdf` (205 pp), concatenated in printed-folio order: front matter (`highlights`, `chart_malaysia` vii) → Economic & Fiscal Outlook (`preface` 69, `chart_economy` 71, `chart_budget` 72, `content` 73, `chart_acronym` 78, `section1`–`section4` 83–144) → Revenue Estimates (`statistical_tables` 149, `memorandum` 213, `summary` 221, `details` 229, `revenue` 243, `organisation` 245). MANIFEST 2023 row flipped `BM,FALSE,TRUE` → `EN,TRUE,TRUE`, making 2023 a pair year in `notebooks/malay_consistency.qmd`. **Edition caveat:** the EN side is the **Feb-2023 re-tabled-budget "Updates" edition** (a condensed Economic & Fiscal Outlook plus a bundled Federal Government Revenue Estimates / Treasury Memorandum block), whereas the BM side is the **Oct-2022 full *Tinjauan Ekonomi 2023*** — different editions of the 2023 budget cycle. The EN bundle also carries the Revenue-Estimates block, which has no counterpart on the BM side or in any 2014–2022 EN file, so expect EN-heavy C1 measure counts for 2023; discount the 2023 row in the cross-language drift accordingly. Source parts left in `_inbox/2023_en/` as an audit trail (gitignored).
