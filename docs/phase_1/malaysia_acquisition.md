# Malaysia Document Acquisition

This document records how we built the Malaysian primary-source corpus for Phase 2 (Malaysia pilot deployment of the Halterman-Keith validated codebooks C1 and C2). It serves two readers: the Phase 3 team replicating this for Indonesia, Thailand, Philippines, Vietnam; and a methodological appendix for the eventual paper.

The acquisition was deliberately human-in-the-loop. The codebook design is Claude-assisted but the decision about *which documents constitute "the corpus"* is research design, not engineering. Most failures of cross-country LLM fiscal analysis would be traceable back to corpus-construction errors that look small in the moment ("we used the JICA report instead of the actual NERP"), so we wrote down both the mapping rationale and the false-trail inventory before either could decay.

## 1. Purpose and scope

**Goal**: deploy the US-validated codebooks (C1 measure identification, C2 motivation+sign+timing) to a Malaysian primary-source corpus spanning 1980-2022, then expert-validate the resulting fiscal-shock dataset.

**What we built**: a 154-row manifest in `R/pull_malaysia.R` (one row per (year, document series) tuple within the pilot window), covering five document series mapped onto Romer & Romer's source taxonomy. Of the 154 rows, **99 have content sourced**, all manually downloaded by the human and routed to canonical local paths; 55 remain pending, all of them confirmed digital dead-ends (pre-mid-1990s government documents that exist only in physical archives).

**What we did not build**: a fully automated URL→PDF pipeline. The anti-bot infrastructure on Malaysian government sites (AWS WAF on BNM, intermittent geo-blocking on the MoF archive) plus the fragmentary state of older archives means programmatic acquisition is brittle. Instead, we engineered a clear hand-off pattern between human-driven discovery and Claude-driven assortment, manifest tracking, and quality gates.

**Out of scope for this document**: text extraction, chunking, codebook deployment, expert validation. Those are downstream.

## 2. Romer & Romer source taxonomy → Malaysian analogs

R&R (2010) use sources for three distinct functions:

- **(M) Motivation** — narrative explaining *why* a fiscal action was taken; the codebook needs this language to classify exogenous vs. endogenous
- **(I) Identification** — systematic listing of all tax/fiscal law changes; used to enumerate "what to look at"
- **(Q) Quantification** — revenue/spending estimates and implementation timing

R&R put particular weight on executive-branch documents because, in the US system, "the impetus for changes in taxes typically comes from the president" (Romer & Romer 2009a, p. 3). The Malaysian executive sits in Parliament (the Finance Minister is often the PM or a senior PM-aligned figure), so the executive/legislative boundary is structurally different. Below we map each R&R source onto a Malaysian analog and note how the structural difference matters.

### Mapping table

| R&R source | Function | Malaysian analog | Rationale |
|---|---|---|---|
| *Economic Report of the President* | M (primary), I, Q | **MoF Economic Report / *Tinjauan Ekonomi*** (renamed *Tinjauan Ekonomi* in 2018) | Annual document, released alongside the Budget, explicitly discusses motivation and revenue effects of the prior year's fiscal actions. Closest functional analog to ERP. |
| *Annual Report of the Treasury* | I (primary), Q | **Federal Government Financial Statement** (Jabatan Akauntan Negara, post-2009 digital) — *weak match* | Malaysia's audited fiscal statements lack the narrative motivation content that R&R extract from the US Treasury report. We treat the Economic Report's public-finance chapter as the de facto Treasury analog. |
| *Budget of the United States Government* | I, Q | **Budget Speech / *Ucapan Bajet*** + **Estimates of Federal Expenditure and Revenue** | The Budget Speech is the motivation-rich anchor; the Estimates booklets are the quantification companion. Malaysian convention bundles narrative and quantification into the Budget Speech in a way that the US splits between SOTU and the Budget document. |
| Presidential speeches/statements (SOTU, signing) | M | **Budget Speech**, supplementary speeches when announced | Because the Malaysian Finance Minister is frequently the PM (Anwar Ibrahim since 2022; Najib 2008-13; Mahathir 2001-03 etc.), the Budget Speech absorbs much of the motivation content that the US splits across SOTU + Budget Message + signing statements. We **do not need a separate SOTU analog**. |
| Ways & Means / Senate Finance Committee reports | M, Q | **Parliamentary Hansard (Dewan Rakyat)** — budget debate transcripts | Imperfect match. Malaysia lacks dedicated tax-policy committees analogous to W&M / SFC. The closest legislative-motivation source is the budget debate Hansard. (See §4 for limitations: the Budget Select Committee was only established in December 2018, so it cannot anchor a 1980-2017 series.) |
| Conference reports / Joint Committee on Taxation | Q | *(no analog)* | Malaysia is parliamentary; budget bills do not pass through a bicameral conference. |
| Congressional Budget Office reports (post-1974) | Q (independent) | **Bank Negara Malaysia Annual Report** + **IMF Article IV** | BNM as central bank publishes an annual fiscal-and-public-finance chapter with independent technical estimates. IMF Article IV provides external triangulation. Neither is a perfect CBO analog but both serve the independent-technical role. |
| Social Security Bulletin / OASI Trustees Report | M, Q (specialized) | *(deprioritized for Phase 2)* | Malaysia's EPF/SOCSO/KWAP publish annual reports but contribution-rate changes are announced through the Budget Speech and effected through the EPF Act Third Schedule. The specialized social-insurance source class is collapsed into the Budget Speech for our purposes. |

### Additional Malaysian sources (no R&R precedent)

R&R only treat tax-side fiscal policy. Our project covers fiscal policy more broadly, including spending-side actions, so we added:

| Malaysian source | Function | Rationale |
|---|---|---|
| **Five-Year Malaysia Plans + Mid-Term Reviews (RMK-1 through RMK-13)** | M, I, Q (spending-side) | Each plan sets development-expenditure envelopes; MTRs explicitly justify mid-cycle revisions and are dense with motivation language. No US analog because the US has no equivalent formal medium-term planning document. |
| **Crisis booklets** (NERP 1998, 2009 mini-budget, COVID stimulus packages PRIHATIN/PENJANA/PEMERKASA/PEMULIH/NRP) | M, I, Q (event-specific) | One-shot fiscal-action documents released at crisis junctures. R&R's narrative method would have captured these as natural-language descriptions of discrete fiscal shocks. |

### Series we considered and dropped

- **Bank Negara Malaysia Economic and Monetary Review** (separate publication from BNM AR, started 2020 when BNM split the Annual Report into institutional and macro/fiscal halves): potentially richer than the post-2020 BNM AR for our purposes, but introduces a series-discontinuity at 2020. Set aside for Phase 3 consideration; the BNM AR remains the canonical macro/fiscal source.
- **Auditor General reports (LKAN)**: post-hoc audit of spending execution; rich for irregularities but does not originate fiscal motivation language. Out of scope.
- **EPF / SOCSO / KWAP annual reports**: pre-2008 not available digitally; contribution-rate changes are announced through the Budget Speech anyway. Deprioritized.
- **World Bank Malaysia Economic Monitor**: only exists from 2010; not a primary source. Useful as a future cross-check, not in the corpus.

## 3. Coverage matrix

### Year × series grid (within pilot window 1980-2022)

`R` = manually downloaded and ready; `P` = pending (confirmed unavailable digitally). The initial pass marked PRIHATIN/PENJANA 2020 as `A` (auto-fetched direct PDF) but those hosts have since drifted; both rows are now `R`. No Malaysian row currently relies on `auto`.

| Year | BNM AR | Budget Speech | Econ Report | Crisis | RMK |
|---|:---:|:---:|:---:|:---:|:---:|
| 1980 | P | P | P | – | – |
| 1981 | P | P | P | – | R (Plan-4) |
| 1982 | P | P | P | – | – |
| 1983 | P | P | P | – | – |
| 1984 | P | P | P | – | P (MTR-4) |
| 1985 | P | P | P | – | – |
| 1986 | P | P | P | – | R (Plan-5) |
| 1987 | P | P | P | – | – |
| 1988 | P | P | P | – | – |
| 1989 | P | P | P | – | P (MTR-5) |
| 1990 | P | P | P | – | – |
| 1991 | P | P | P | – | R (Plan-6) |
| 1992 | P | P | P | – | – |
| 1993 | P | P | P | – | P (MTR-6) |
| 1994 | P | P | P | – | – |
| 1995 | P | P | R | – | – |
| 1996 | P | P | R | – | R (Plan-7) |
| 1997 | R | P | R | – | – |
| 1998 | R | P | R | R (NERP) | – |
| 1999 | R | R | R | – | R (MTR-7) |
| 2000 | R | R | R | – | – |
| 2001 | R | R | R | – | R (Plan-8) |
| 2002 | R | R | R | – | – |
| 2003 | R | R | R | – | R (MTR-8) |
| 2004 | R | R | R | – | – |
| 2005 | R | R | R | – | – |
| 2006 | R | R | R | – | R (Plan-9) |
| 2007 | R | R | R | – | – |
| 2008 | R | R | R | – | R (MTR-9) |
| 2009 | R | R | R | R (Mini-Bgt) | – |
| 2010 | R | R | R | – | – |
| 2011 | R | R | R | – | R (Plan-10) |
| 2012 | R | R | R | – | – |
| 2013 | R | R | R | – | P (MTR-10) |
| 2014 | R | R | R | – | – |
| 2015 | R | R | R | – | – |
| 2016 | R | R | R | – | R (Plan-11) |
| 2017 | R | R | R | – | – |
| 2018 | R | R | R | – | R (MTR-11) |
| 2019 | R | R | R | – | – |
| 2020 | R | R | R | R×2 (PRIHATIN, PENJANA) | – |
| 2021 | R | R | R | R×4 (PERMAI, PEMERKASA, PEMULIH, NRP) | R (Plan-12) |
| 2022 | R | R | R | – | – |

### Per-series totals (in scope, within 1980-2022)

| Series | Total rows | Ready | Pending | Pending years |
|---|---:|---:|---:|---|
| BNM Annual Report | 43 | 26 | 17 | 1980-1996 |
| Budget Speech | 43 | 24 | 19 | 1980-1998 |
| Economic Report | 43 | 28 | 15 | 1980-1994 |
| Crisis booklets | 8 | 8 | 0 | — |
| RMK Plans + MTRs | 17 | 13 | 4 | MTR-4 (1984), MTR-5 (1989), MTR-6 (1993), MTR-10 (2013) |
| **Total** | **154** | **99** | **55** | |

### Bonus material (outside pilot window, sorted on disk)

Acquired during the pass but not in the manifest because the pilot window stops at 2022 / starts at 1980:

- BNM AR: 2023, 2024, 2025 (3 files)
- Budget Speech: 2023, 2024, 2025 (3 files)
- Economic Report: 2023, 2024, 2025 (3 files)
- RMK: RMK-1 plan (1966), RMK-2 plan+MTR (1971+1973), RMK-3 plan (1976), RMK-13 plan (2026), RMK-12 MTR (2023) (6 files)
- Set aside as `_inbox/_excluded/`: BNM Economic & Monetary Review 2023 (1 file, awaiting decision on separate series treatment)

Window extension is a one-line edit in `R/build_country_configs.R` if Phase 3 or future expansion wants these bonus files plugged in.

### Language coverage

| Series | EN canonical | BM canonical | Both available |
|---|---:|---:|---:|
| BNM Annual Report (1997-2022 ready) | 26 | 0 | 0 |
| Budget Speech (1999-2022 ready, 24 files) | 15 | 9 | 0 |
| Economic Report (1995-2022 ready, 28 files) | 7 | 21 | 7 (2014-2020) |
| Crisis booklets (8 files) | 4 | 4 | 0 |
| RMK (13 files) | 11 | 2 (Plan-2, Plan-4) | 0 |

The Budget Speech BM cluster (2000-2008 plus 2012, 2015) is the largest cross-language risk for codebook deployment.

The Economic Report 2014-2020 EN+BM parallel pairs are a deliberately-preserved substrate for a cross-language transfer experiment: identical content in both languages allows a within-document ablation of model performance.

## 4. Methodological caveats

These are paper-relevant and should appear, in compressed form, in the methodology section of any publication that draws on this corpus.

### 4.1 Cross-language transfer is untested

Of the 99 ready documents, **38 are BM-only** in the canonical position (9 Budget Speeches, 21 Economic Reports, 4 crisis documents, 2 RMK plans, 2 RMK MTRs). The codebooks C1 and C2 were validated entirely on US English data (44 labeled acts, English-only sources). Claude's BM comprehension is strong but not evaluated for fiscal-policy reasoning.

The 7 Economic Reports with EN+BM parallel versions (2014-2020) are the recommended substrate for a within-corpus cross-language ablation before drawing conclusions about Malaysian fiscal motivation from BM-only segments.

### 4.2 Pre-1995 hard wall

For three of the five series (BNM AR pre-1997, Budget Speech pre-1999, Economic Report pre-1995), no digital sources exist. The user confirmed this through multiple search passes across MoF archives, BNM archives, Sinar Project (Malaysia's open-government archive), Wayback Machine, and academic mirrors. Three options for the Phase 2 paper:

1. **Scope the pilot window** to 1995-2022 (28 years) and present the dataset as that range
2. **Physical archive expedition** (MOSTI Library, Perpustakaan Negara Malaysia, MoF print collection) — feasible, weeks-to-months effort, not done
3. **Accept the gap** with explicit documentation

Default for this project: option 3 (1980-2022 nominal window, pre-1995 documented as gap).

### 4.3 OCR-required documents

Several documents in the corpus are scanned PDFs without a text layer and will require OCR (via Tesseract integrated through `python/pymupdf_extract.py`) at text extraction time:

- NERP 1998 (197 pages, fully scanned)
- RMK-1 (1966), RMK-3 (1976) — scanned chapter PDFs concatenated to single document
- Pre-1996 BNM Annual Reports (1997-2002 came as chapter PDFs of varying quality)
- Large modern files: BNM AR 2022 (83 MB), 2023 (61 MB), 2024 (111 MB) are image-heavy

OCR introduces a known quality degradation (~95-98% character accuracy with Tesseract on clean modern scans, lower on older or stained documents) that the codebook evaluation must account for. The H&K S2 evaluation already tolerates moderate OCR noise on US ERPs of similar vintage.

#### Mixed-content PDFs and per-page OCR rescue

The initial extractor used a document-level OCR detector (first-5-pages heuristic, threshold ~500 chars/page) that produced silent failures on mixed-content PDFs in the MoF Economic Report series. `MY_ECON_REPORT-2001.pdf` is a 233-page document whose first 25 pages are text-extractable but pages 26-84 are scanned full-page chart inserts; the first-5-pages average (~3,700 chars) marked the whole document as text-based, leaving 59 image-only pages with `n_chars = 0`. Test (iv) of `notebooks/verify_country_body.qmd` flagged 18% of sampled Malaysia pages as suspicious (criterion `n_chars < 100 | special_char_rate > 0.10 | non_ascii_rate > 0.05` on a sample of 5 docs × 50 pages per country), well above the pre-registered 5% target.

Commit `741ebc0` moved OCR to a per-page rescue mechanism in `python/pymupdf_extract.py`:

1. Extract native text for every page (cheap; microseconds per page)
2. Route individual pages where native `n_chars < 100 AND page.get_images() > 0` through Tesseract
3. On per-page OCR failure, preserve the native text rather than overwrite with an error sentinel

The `has_images` guard is conservative by design. Cosmetically-short pages with no raster image (covers, blank versos, vector-drawn section dividers) contain nothing for OCR to recover, so the rescue skips them rather than waste cycles producing gibberish from decorative artwork. After re-extraction MY_ECON_REPORT-2001 went from 25/50 to 0/50 suspicious pages in the Test (iv) sample, and Malaysia's corpus-wide rate fell from 18% to 7.6%. Two new schema fields propagate through the body tibble for downstream diagnostics: `n_pages_ocr` (integer count per document) and `pages_ocr` (logical vector parallel to `text`).

#### Residual 7.6% suspicious-page floor

The residual 7.6% (19 of 250 sampled pages, May 2026) is essentially the cosmetic floor of a well-structured PDF corpus:

| Category | Share of residual | Example |
|---|---:|---|
| Cover, title, or section-divider pages with no embedded image | 84% | BNM AR 2021 p.1 `"2021\nAnnual Report"` (19 chars); ER 2010 section dividers (60-78 chars); Budget Speech 2021 p.3 `"Budget 2021"` (12 chars) |
| Blank verso pages, n_chars = 0 | overlap with above | Vector-drawn dividers or genuinely blank backs of section pages |
| OCR-quality gibberish on a decorative image plate | 5% (1 page) | BNM AR 2021 p.3, a full-bleed decorative plate that Tesseract rendered as `"\| - Si\n:\nae\n\| Pea"` |

The `special_char_rate > 0.10` and `non_ascii_rate > 0.05` criteria are essentially dormant on the post-rescue corpus (1 hit each, both on the single gibberish page). The `n_chars < 100` criterion is the only active trigger and fires predominantly on legitimate layout artifacts. Failures concentrate in four documents (MY_ECON_REPORT-2010, MY_BNM_AR-2021, MY_BUDGET_SPEECH-2021, MY_ECON_REPORT-2015-BM); all four are dominated by structural short pages rather than extraction defects.

The pre-registered 5% target was set with US ERPs in mind, which are uniformly born-digital from 1946 onward with consistent layout. The 7.6% Malaysia floor should be read as PASS conditional on splitting the metric in subsequent reporting between (a) legitimately short pages with no raster-image content (cosmetic floor; expected ≤8% for an emerging-market PDF corpus that mixes scanned legacy material with modern designed booklets) and (b) OCR-quality defects on rescued pages (target ≤5%). Under that decomposition the Malaysia OCR-quality defect rate is 0.4%. Phase 3 countries should plan to report this split rather than a single combined rate.

### 4.4 Legislative-motivation gap

The R&R source taxonomy includes House Ways and Means / Senate Finance Committee reports as the primary legislative-motivation source. Malaysia has no clean analog:

- The Budget Select Committee (Jawatankuasa Pilihan Khas Belanjawan) was only established in **December 2018**, so it cannot serve a 1980-2017 panel
- The Public Accounts Committee post-dates expenditure execution; its function is audit, not motivation
- Parliamentary Hansard (Dewan Rakyat budget debates) is the closest substitute, but pre-2000 Hansard is scanned-image PDFs without OCR, and the corpus is large (3,684 PDFs in the Malaysian Hansard Corpus 1959-2020 per Mohamed et al. 2021)

For Phase 2 we treat the Budget Speech as carrying the bulk of legislative-motivation content, accepting that we lose the committee-level nuance R&R extract from W&M / SFC reports. Phase 3 should evaluate whether Hansard ingestion is worth the OCR cost.

### 4.5 Speech transcript vs. branded-booklet format heterogeneity

The crisis-booklet series contains documents of two distinct formats:

- **Branded booklets** (PRIHATIN, PENJANA): glossy designed PDFs with charts, tables, and infographics, typically 30-60 pages
- **Speech transcripts** (PERMAI, PEMERKASA, PEMULIH): verbatim text of the PM's announcement address, 15-25 pages

Both are valid R&R primary sources (R&R explicitly cite presidential speeches alongside policy documents) but the codebook will see structurally different inputs. Worth flagging if the C1 measure-identification recall differs systematically across the two formats.

## 5. Acquisition workflow (Phase 3 playbook)

This section is the replicable how-to for the next country.

### 5.1 Manifest schema

The country URL manifest, generated by `R/pull_malaysia.R` and consumed by the deployment pipeline, has the following columns:

| Column | Type | Purpose |
|---|---|---|
| `year` | int | Fiscal year covered by the document |
| `package_id` | char | Stable ID, e.g. `MY_BNM_AR-2010`, `MY_RMK-7_MTR-1999` |
| `pdf_url` | char | Direct PDF URL (for `auto`); landing page URL (for `manual_pending`); absolute local path (for `manual_ready`) |
| `country` | char | "malaysia" |
| `source` | char | Domain or organization issuing the document |
| `body` | char | Document series human-readable name |
| `doc_language` | char | "en" / "ms" |
| `access_status` | char | `auto` / `manual_pending` / `manual_ready` |
| `local_path` | char | Expected drop path under `data/manual/<country>/<series>/<filename>.pdf` |
| `notes` | char | Free-form context (landing-page-only, anti-bot caveat, etc.) |

### 5.2 The three access states

The `access_status` value drives downstream behavior:

- **`auto`** — `pdf_url` is a verified direct PDF URL that the deployment pipeline fetches via `urllib`. Tested with Python `urllib.request.urlretrieve` and Tesseract OCR fallback. Only viable for sites without anti-bot infrastructure. The Malaysia pass initially marked PRIHATIN-2020 (PMO host) and PENJANA-2020 (`penjana.treasury.gov.my`) as `auto`, but both hosts subsequently drifted (PMO 404, Treasury subdomain unreliable) and the rows were re-sourced manually; no Malaysian row currently relies on `auto`. The mechanism is retained in the schema for Phase 3 countries whose hosts are friendlier.
- **`manual_pending`** — `pdf_url` points to a landing page (or is `NA`). The dashboard renders this as a clickable link with the expected drop path; the human follows the link, downloads the PDF, and saves it to `here::here(local_path)`. On the next `tar_make(country_urls)`, the resolver detects the local file and flips the row to `manual_ready`.
- **`manual_ready`** — `pdf_url` has been rewritten to the absolute local path. The extraction pipeline treats it identically to an `auto` URL (the Python extractor handles both via a `pdf_path.startswith(("http://", "https://"))` check).

The resolver (`resolve_manual_paths` in `R/pull_malaysia.R`) lets local files override `auto` URLs: if a `local_path` file exists, it wins regardless of starting status. This insulates the corpus from upstream site outages (e.g., the EPU site going down) once a manual copy is in place.

### 5.3 The `_inbox` → assort pattern

The acquisition loop has two roles. The human drives discovery and download; Claude handles file naming, deduplication, and routing.

1. **Human downloads** PDFs from any source (no need to rename) into `data/manual/<country>/_inbox/`
2. **Claude inspects** each file: filename parse + first-page text (or OCR if scanned) to identify
   - Document series (Budget Speech vs Economic Report vs etc.)
   - Year (fiscal year, not delivery date — see §6 for the trap)
   - Language (filename hints + first-page keywords)
   - Primary vs secondary (see §6)
3. **Claude routes** each file to `data/manual/<country>/<series>/<canonical_filename>.pdf`
   - Single PDFs: simple move + rename
   - Chapter-sectioned originals (BNM AR 1997-2002, RMK 1st-7th, Economic Report 1995-2020): concatenate with `pymupdf.insert_pdf()` using a priority-ordering heuristic (foreword → numbered chapters → annex → budget chapter → forecast/stats)
4. **Files routed to `_excluded/`** when they don't fit the corpus (state-level budgets, secondary analyses, unrelated documents). Kept for audit trail; never deleted.
5. **Per-series MANIFEST.csv** tracks language and source filename: one row per file, columns `year, language/canonical_lang, source_filename`. Committed to git as the replicability record (the PDFs themselves are gitignored).
6. **Manifest rebuild + dashboard render**: `tar_make(country_urls)` flips statuses based on file presence; `quarto render notebooks/verify_<country>_urls.qmd` shows the updated state with clickable links for remaining pending rows.

### 5.4 PyMuPDF concatenation pattern

For chapter-sectioned source documents:

```python
import os, re, pymupdf

def file_role(name):
    n = name.lower()
    if re.search(r"kata.?pendahuluan|foreword|mukadimah|preface", n): return 1
    if re.search(r"kandongan|kandungan|contents", n): return 2
    if re.search(r"acronym|glosari|akronim", n): return 3
    if re.search(r"bahagian.?(satu|dua|tiga)", n): return 100  # BM sections
    m = re.search(r"(chapter|chapt|bab)[\s_-]*(\d+|[ivxl]+)", n)
    if m:
        s = m.group(2)
        return 100 + (int(s) if s.isdigit() else roman_to_int(s))
    if re.search(r"economy|ekonomi", n): return 800
    if re.search(r"budget|bajet", n): return 810
    if re.search(r"forecast|annex|perangkaan", n): return 900
    return 990  # everything else, at the end alphabetically

files = sorted(os.listdir(src_dir), key=file_role)
out = pymupdf.open()
for f in files:
    with pymupdf.open(os.path.join(src_dir, f)) as src:
        out.insert_pdf(src)
out.save(out_path)
```

PyMuPDF was chosen over the R `pdftools::pdf_combine` because QPDF (which `pdf_combine` wraps) hit `QPDFCrypto_native has no random data provider` errors in our dev container for older scanned PDFs. PyMuPDF handles those without crypto-RNG dependencies.

### 5.5 Dashboard for human verification

`notebooks/verify_<country>_urls.qmd` is a Quarto notebook that reads the manifest target and renders three `gt` tables:

- **Auto** — direct URLs that the pipeline fetches (informational)
- **Manual-ready** — files dropped, ready for extraction (confirmation)
- **Manual-pending, grouped by series** — the work queue. Each row has a clickable link (using `gt::fmt_markdown` on a hand-built `<a href target="_blank">`) plus the drop path.

Important Quarto detail: the per-series loop chunk must use `#| results: asis` and emit gt tables as raw HTML via `gt::as_raw_html(tbl) |> cat()`, otherwise the loop output gets HTML-escaped into a `<pre><code>` block. This was a real bug we hit and fixed.

### 5.6 Per-series MANIFEST.csv schema

Each series subdirectory under `data/manual/<country>/` contains a `MANIFEST.csv`. The schema varies by series because the metadata that matters differs:

- **Budget Speech**: `year, language, source_filename` — language (BM/EN) is the cross-language risk signal
- **Economic Report**: `year, canonical_lang, has_en, has_bm` — supports the cross-language parallel pair tracking
- **BNM AR, RMK**: no MANIFEST yet (would be a future addition; the filenames carry all current metadata)

These manifests are git-tracked even though the underlying PDFs are not. The acquisition record persists in version control while the corpus itself stays local.

## 6. "Wrong document" trap inventory

The traps below cost the human and Claude real time in this acquisition. We capture them here so that Phase 3 (and future Malaysia re-acquisitions when a year is updated) can avoid re-paying that cost. Each entry: name, why it happens, how to spot it, how to disambiguate.

### Trap 1: State-level vs federal budgets

**Why it happens**: Malaysia is a federation with 13 states + 3 federal territories. Each state (Sabah, Sarawak, Penang, Selangor, Perak, etc.) issues its own annual budget through its State Legislative Assembly. Search engines treat "Budget Speech 2026" or "Belanjawan 2009" indiscriminately.

**Examples we hit**:
- `teks-ucapan-bajet-2009-perak.pdf` → Perak State Budget 2009, *not* the federal Budget Speech 2009 (which was delivered by Abdullah Ahmad Badawi as PM on 29 August 2008 for FY2009)
- `SABAH BUDGET SPEECH YEAR 2026` (Datuk Seri Masidi at Sabah Legislative Assembly) → Sabah State Budget, not federal

**How to spot**:
- Speaker title: **federal** = "PERDANA MENTERI DAN MENTERI KEWANGAN" (PM and Finance Minister); state = "Deputy Chief Minister / Minister of Finance" of the state, or state-specific minister title
- Delivery venue: **federal** = "DEWAN RAKYAT" (federal lower house); state = "State Legislative Assembly" or "Dewan Undangan Negeri"
- Bill name: **federal** = "Rang Undang-Undang Perbekalan ([Year])" (federal Supply Bill); state = "[State] Supply Bill"
- Title prefix: state speeches usually have the state name (Sabah, Perak, etc.) explicitly in the title

**Disambiguate**: always check page 1 for "PERDANA MENTERI" + "DEWAN RAKYAT" + "Rang Undang-Undang Perbekalan" before accepting a Budget Speech.

### Trap 2: Supplementary vs regular budgets

**Why it happens**: Malaysia, like most parliamentary systems, occasionally tables supplementary appropriation bills mid-year for unbudgeted spending (often during crises). These are formally Budget Speeches but they cover *additional* spending, not the regular annual budget.

**Example we hit**:
- Najib's 10 March 2009 speech: "RANG UNDANG-UNDANG PERBEKALAN **TAMBAHAN** (2009)" → supplementary Supply Bill announcing the RM60bn mini-budget GFC stimulus. Not the regular FY2009 budget speech.

**How to spot**:
- The word **"TAMBAHAN"** in the Supply Bill name (Malay for "supplementary"). Present = supplementary.
- The speech text usually opens with crisis framing ("krisis kewangan", "stimulus") rather than a normal annual budget preamble.

**Disambiguate**: the regular FY[Y] Budget Speech is delivered in **October of year Y-1** by the sitting Finance Minister. Supplementary speeches happen at off-cycle times (March, May, etc.). If the date is non-October, suspect a supplementary or a mini-budget — route to `stimulus/` not `budget_speech/`.

### Trap 3: Secondary sources marketed as primary

**Why it happens**: Search engines surface think-tank summaries, accounting firm briefings, academic case studies, and consultant slides above primary government documents — especially for older events where the original government PDF is harder to find. These secondary documents *describe* government actions accurately but inject the analyst's own filtering of motivation language, which violates R&R's "policymakers' own words" requirement.

**Examples we hit**:
- `The Malaysian Governments Response to the Economic Crisis (1).pdf` — Watanabe et al. (1999), published by JICA on Yale's YPFS mirror. Looks like the NERP, isn't.
- `PERMAI Assistance Package Highlights_Crowe.pdf` — Crowe (accounting firm) summary of PERMAI 2021
- `C__Internet_myiemorgmy_..._Circular No 25-PEMULIH Package-akk.pdf` — Institution of Engineers Malaysia internal circular summarizing PEMULIH for IEM members

**How to spot**:
- Publisher field on page 1 or 2: anything other than the Malaysian federal government (MoF, PMO, MoEcon, EPU, BNM) is a red flag
- "Highlights," "Summary," "Analysis," "Briefing" in the title or section headers
- Foreword from a non-government author (CEO, partner, professor)

**Disambiguate**: the primary source is signed/spoken by the relevant minister; the page 1 should establish the speaker (PM, Finance Minister) and the venue (Dewan Rakyat) and the formal bill or package title.

**Recovery**: if the primary is truly not findable, document the gap in the manifest rather than substituting a secondary. The methodological cost of substituting is asymmetric: a third-party summary can systematically bias motivation classification because the analyst has already filtered "why" through their own frame.

### Trap 4: Adjacent-publication confusion

**Why it happens**: government departments publish many documents at similar times with similar branding. The right document for our corpus is often the *less prominent* of the set because the most-publicized version may be a summary, executive briefing, or PR document.

**Examples we hit**:
- **VNR (Voluntary National Review) 2021** is Malaysia's report to the UN on Sustainable Development Goals progress — submitted by EPU at the UN High-Level Political Forum. Not a fiscal stimulus document, despite being a 2021 government publication.
- **Bank Negara Annual Report** vs **BNM Economic and Monetary Review** post-2020: these are now two separate publications. The Annual Report became more institutional/financial-sector-focused; the EMR took over the macro/fiscal narrative role. Easy to grab one expecting the other.

**How to spot**:
- Title: VNR explicitly says "Voluntary National Review" + the SDG branding (red, blue, green icons); fiscal-stimulus documents say "Package," "Pakej," "Plan," "Stimulus"
- Issuing body: VNR is issued by EPU (planning); fiscal stimuli by PMO/MoF
- Length: VNRs are 100+ pages; PMO stimulus speeches are 15-25 pages, full stimulus booklets are 30-60 pages

**Disambiguate**: read the foreword and the table of contents. Fiscal stimuli discuss specific RM allocations, line items, and effective dates. Adjacent publications discuss broader policy framings without the dollar-amount granularity.

### Trap 5: Year convention (fiscal vs delivery)

**Why it happens**: Malaysian Budget Speech for fiscal year Y is *delivered* in October of year Y-1. The Budget covers the next calendar year. So:
- "Budget 2026" was delivered 10 October 2025
- "Budget 2009" was delivered 29 August 2008 (early due to political tensions)

The Hansard date stamp and the speech metadata reference the delivery date, but R&R-style fiscal-shock identification uses the *fiscal year covered*. Inconsistent year-keying corrupts the time series.

**How to spot**:
- The bill name in the speech preamble always carries the fiscal year: "Rang Undang-Undang Perbekalan (2025)" → fiscal year 2025
- The title also typically carries the fiscal year: "Budget 2025 Speech" → fiscal year 2025

**Disambiguate**: always key the manifest row by the **fiscal year referenced in the bill name**, not the date the speech was delivered. Confirm by cross-checking against the Hansard record date.

### Trap 6: Counterintuitive language tags in filenames

**Why it happens**: Malaysian government filenames mix BM and EN abbreviations, sometimes following Malay conventions even for English content.

**Examples we hit**:
- `teks_ucapan_bajet_2013_BI.pdf` → 2013 Budget Speech. `BI` = "Bahasa Inggeris" = English. **Not** Bahasa Malaysia.
- `ub23-BI.pdf`, `ub24-BI.pdf`, `ub25-en.pdf` → Budget Speech 2023/24/25. `ub` is Malay-coded (Ucapan Bajet) but the `-BI` or `-en` suffix indicates English.
- `Teks2006.pdf`, `Teks2008.pdf` → "Teks" = "Text" in BM, BM versions

**How to spot**:
- `BI` suffix = English
- `BM`, `ms`, `Bahasa Malaysia`, or no language tag with a BM-coded base name = Malay
- Filename heuristic is brittle; falling back to first-page keyword scan (`Mr. Speaker` vs `Tuan Yang Dipertua`, `Supply Bill` vs `Rang Undang-Undang Perbekalan`, `BUDGET SPEECH` vs `UCAPAN BAJET`) is the reliable disambiguator

**Disambiguate**: when the filename is ambiguous, read the first 200 characters of page 1 and check for English vs Malay anchor phrases.

### Trap 7: Booklet format vs speech transcript

**Why it happens**: PMO and MoF release fiscal-stimulus packages in two formats — designed marketing booklets (PRIHATIN, PENJANA) and bare speech-text transcripts (PERMAI, PEMERKASA, PEMULIH). Both are valid R&R primary sources but the structural differences may matter for chunk extraction and codebook recall.

**Examples we hit**:
- We initially searched for the PERMAI "Booklet" expecting a PRIHATIN-style designed document. The actual release was a speech transcript in the same template as the PEMERKASA and PEMULIH transcripts the user found shortly after.

**How to spot**:
- Speech transcript: opens "TEKS UCAPAN YAB [PM name] ... PERDANA MENTERI ..."; ~15-25 pages of plain prose
- Booklet: glossy cover page, multi-column layout, charts and tables, "Foreword by the PM" on an inside page, ~30-60 pages

**Disambiguate**: search terms for stimulus packages should include both `"TEKS UCAPAN" [package_name]` and `[package_name] booklet`. Both formats are valid; route to `stimulus/` regardless.

## 7. Sources, anti-bot encounters, effort

### Where each series came from

| Series | Primary archive (when accessible) | Fallbacks used |
|---|---|---|
| BNM Annual Report | bnm.gov.my (browser-only, behind AWS WAF) | None — direct download via browser session |
| Budget Speech | belanjawan.mof.gov.my/en/archive (2014+); mof.gov.my/portal/arkib/budget/bs_Main.html (legacy 2010-2022) | Per-year archive landing pages; Hansard fallback discussed but not used |
| Economic Report | belanjawan.mof.gov.my (recent); mof.gov.my/portal/arkib/ekonomi (1995-2013) | None |
| Crisis booklets | pmo.gov.my (PRIHATIN booklet, browser-clicked); penjana.treasury.gov.my (PENJANA booklet, browser-clicked); pmo.gov.my speech archive (PERMAI/PEMERKASA/PEMULIH transcripts); search for NRP and NERP | Yale eliScholar for NERP-era documents |
| RMK Plans | epu.gov.my landing pages; rmke12.epu.gov.my (RMK-12 portal) | TalentCorp mirror for RMK-11 MTR; direct browser download for older plans |

### Anti-bot encounters

- **Bank Negara Malaysia** (`bnm.gov.my`) is protected by **AWS WAF** with a JavaScript challenge. Returns `HTTP 202` to programmatic clients (curl, urlretrieve, Python `requests`, R `httr2`). Browser sessions pass the challenge once and cache a cookie. We attempted scripted access but settled on human-clicked download as the reliable path. WAF protection extends to the direct PDF URLs (e.g., `bnm.gov.my/documents/.../ar2025_en_book.pdf`) — not just the landing pages.

- **MoF "official" archive** (`belanjawan.mof.gov.my/en/archive`) was reported by the user as "down" but responded HTTP 200 with 116KB of content from our dev container's network. Suggests a transient JavaScript render hiccup or a geo-block. Worth always retrying from a different network/browser before treating MoF as down.

- **EPU sites** (`epu.gov.my`, `rmke12.epu.gov.my`): occasionally return `ECONNREFUSED` to scripted clients but browser access works. Treat as anti-bot-fragile.

### Rough effort accounting

The acquisition pass was structured as eight rounds:

1. **R&R rationale gathering** (Claude, ~30 min): read the methodology paper sections on source selection
2. **Online research for Malaysia analogs** (3 parallel Claude agents, ~5 min): identified candidate document series
3. **Pipeline scaffolding** (Claude, ~1 hour): pull_malaysia.R, schema additions, dashboard notebook, gitignore
4. **BNM Annual Reports 1997-2025** (29 PDFs, mostly chapter-sectioned for 1997-2002): ~30 min user time
5. **Budget Speeches 1999-2025** (27 PDFs across mixed naming conventions): ~45 min user time, 1 wrong-document trap (Perak state budget)
6. **Economic Reports 1995-2025** (~70 PDFs concatenated into 31 documents): ~1 hour user time
7. **Five-Year Plans + MTRs** (19 PDFs covering RMK-1 through RMK-13): ~45 min user time, 3 admin circulars excluded
8. **Crisis booklets** (6 PDFs): ~45 min user time, 4 wrong-document traps before getting the right ones

Total: roughly 4-5 hours user time, ~120 PDFs ingested into the manifest. The traps cost approximately 30-60 min cumulative (downloading wrong document, identifying the error, re-searching). The traps are also where this document earns its keep — once mapped, Phase 3 should avoid them.

### What Phase 3 should plan for

- Expect 4-6 hours per country of human acquisition time once the infrastructure is in place
- Expect 1-3 "wrong document" traps per series, most acutely in stimulus/crisis booklets and budget speeches (state-vs-federal)
- Expect a pre-1995 (or country-specific equivalent) digital wall for most older documents
- Expect anti-bot infrastructure on at least one major source per country
- Expect bilingual or multilingual corpora; design the per-series MANIFEST.csv to track language from day one

## Appendix: file naming conventions

For Phase 3 portability, the canonical filename conventions we used in Malaysia:

| Series | Pattern | Example |
|---|---|---|
| BNM Annual Report | `<year>.pdf` | `2010.pdf` |
| Budget Speech | `<year>.pdf` (canonical), `<year>_bm.pdf` (parallel) | `2015.pdf`, `2015_bm.pdf` |
| Economic Report | `<year>.pdf` (canonical, EN preferred), `<year>_bm.pdf` (parallel BM) | `2017.pdf`, `2017_bm.pdf` |
| RMK Plans | `rmk<NN>_plan_<year>.pdf` (NN zero-padded plan number) | `rmk07_plan_1996.pdf` |
| RMK MTRs | `rmk<NN>_mtr_<year>.pdf` | `rmk09_mtr_2008.pdf` |
| Crisis booklets | `<package_id_lowercase>_<year>.pdf` | `prihatin_2020.pdf`, `nerp_1998.pdf` |

Generic principle: filename should be content-addressable from the manifest row's `package_id` without requiring a separate lookup.
