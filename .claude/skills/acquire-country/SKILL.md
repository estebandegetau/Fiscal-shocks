---
name: acquire-country
description: Build a primary-source fiscal-document corpus for a new country (Phase 3 deployment). Walks through R&R-role → country-analog mapping, search terms + year coverage per series, infrastructure emission, and the iterative inbox→assort loop with full first-page trap inspection. Methodology codified in `docs/phase_1/malaysia_acquisition.md`.
user-invocable: true
---

# Acquire-Country Skill

Build the primary-source corpus for a new country in Phase 3 (Indonesia, Thailand, Philippines, Vietnam, or others). Replicates the Malaysia acquisition methodology with explicit human decision points and full trap inspection.

## When to Use

Invoke `/acquire-country` when starting fiscal-document acquisition for a country that does not yet have:

- `R/pull_<country>.R` (series-specific URL builders)
- An entry in `R/build_country_configs.R`
- `data/manual/<country>/` scaffold

For continuing an in-progress acquisition (adding documents to a country already configured), skip directly to **Phase E** below.

## Critical Rules

1. **Take the R&R informational requirements as given.** The five-role taxonomy (M/I/Q across executive, legislative, technical, planning, crisis-event sources) was derived in the Malaysia work and lives in [docs/phase_1/malaysia_acquisition.md §2](../../docs/phase_1/malaysia_acquisition.md). Do not re-derive it from R&R's papers.
2. **Human drives discovery, Claude drives routing.** Search and download are human-led (anti-bot, geo-locks, JavaScript challenges make programmatic harvest unreliable). File inspection, trap classification, manifest tracking, and infrastructure emission are Claude-led.
3. **Display state in chat, not in notebooks.** No Quarto dashboard. State summaries are markdown tables rendered each turn.
4. **Full first-page inspection per dropped file.** Every PDF the human drops into `_inbox/` gets a first-page read (OCR if scanned) checked against the seven-trap inventory before routing. No exceptions.
5. **One archive landing URL per series at most.** Per-year URL lists are not useful (anti-bot, archive churn). Surface search terms first; offer one anchor URL per series.

## Procedure

### Phase A: Initialization

1. Ask the user which country to acquire.
2. Check for existing infrastructure:
   - `R/pull_<country>.R` exists? → skip to Phase E (continuation mode)
   - No file → continue with Phase B (new-country mode)
3. Ask the pilot window (default: 1980-2022 to match Malaysia; user may shorten if pre-1990s archives are known empty).
4. Confirm the primary language (default: country's official language, e.g. "id" for Indonesia, "th" for Thailand). Note that English may also be widely available; the manifest stores `doc_language` per row.

#### PAUSE POINT 1

Present:

```
Initializing acquisition for <country>.

- Pilot window: <min>-<max>
- Primary language: <lang_code>
- Existing scaffold: <none / found>

Proceed to document-series mapping? (yes/no)
```

Do not proceed without explicit confirmation.

### Phase B: Document-series mapping

For the new country, propose the five canonical R&R-derived document series, named with the country-specific issuing institution. The five role-buckets (as established in the Malaysia work) are:

| R&R role | Series-bucket | What to look for |
|---|---|---|
| M+I+Q (executive narrative) | "Economic Report" | Annual document from Ministry of Finance/Treasury, accompanies the Budget, contains motivation + revenue effects |
| M (legislative announcement) | "Budget Speech" | Annual address by Finance Minister to lower house presenting the Supply Bill |
| M+Q (independent technical) | "Central Bank Annual Report" | Annual report from country's central bank with a dedicated public-finance chapter |
| M+I+Q (spending plans) | "Development Plans" | Medium-term planning documents if the country has them (e.g., five-year plans in Indonesia, NESDB plans in Thailand). May not exist; flag if absent. |
| M+I+Q (crisis events) | "Crisis booklets" | One-shot documents at fiscal-shock junctures (Asian Financial Crisis, GFC, COVID stimulus packages) |

For each, identify the country-specific issuing institution. Examples for reference (do not assume — research per country):

- Indonesia: Kementerian Keuangan (MoF), Bank Indonesia, Bappenas (planning)
- Thailand: Ministry of Finance, Bank of Thailand, NESDB/NESDC (planning), Budget Bureau
- Philippines: Department of Finance, BSP (Bangko Sentral), NEDA (planning), DBM
- Vietnam: Ministry of Finance, State Bank of Vietnam, MPI (planning)

Present the proposed mapping as a table with columns: `R&R role | Series bucket | Country institution | Document name (local + English)`.

#### PAUSE POINT 2

Stop and present:

```
Proposed document series for <country>:

[table]

Adjust any of these before we move to feasibility assessment? 
(e.g., 'Vietnam has no formal development plans series — drop that row')
```

The user may add, remove, rename, or merge series. Iterate until they confirm.

### Phase C: Auto-feasibility & search planning

For each confirmed series, determine and present:

1. **Auto-fetch feasibility** — one of:
   - `Likely auto` — the issuing institution's site has direct PDF URLs without anti-bot
   - `Mixed` — recent years auto-fetchable, older years require manual download
   - `Manual` — anti-bot, search-UI-only, or fragmented archives

   Indicators of "manual": JavaScript-only sites, CAPTCHA/WAF, year-by-year navigation required, sites known to redesign frequently. Use WebFetch on the institution's main page to probe (one quick check; do not exhaustively crawl).

2. **Search terms** — provide 3-5 search-engine queries, both in English and the country's primary language. Use the local-language acronyms of relevant institutions/documents (e.g., "Ucapan Belanjawan", "Tinjauan Ekonomi" in BM).

3. **Year coverage** — best-effort range based on when the series started (institutional founding date or oldest known archive year).

4. **One archive landing URL** — the main institutional landing page for the series. Not per-year URLs. If you cannot identify one with high confidence, write "search-discoverable" instead.

Display the resulting table:

```
Series                  | Auto? | Years covered | Search terms                 | Anchor URL
------------------------|-------|---------------|------------------------------|------------
Economic Report         | Mixed | 1995-2024     | "...", "..."                 | ...
Budget Speech           | Mixed | 1999-2025     | "...", "..."                 | ...
Central Bank AR         | Manual| 1997-2024     | "...", "..."                 | ... (WAF)
Development Plans       | Manual| 1966-2025     | "...", "..."                 | ...
Crisis booklets         | Mixed | event-by-event| "...", "..."                 | (PMO/MoF)
```

Then for each series, a short paragraph: *what to expect, what traps are likely, what disambiguation is critical* (drawing from [malaysia_acquisition.md §6](../../docs/phase_1/malaysia_acquisition.md)).

#### PAUSE POINT 3

```
Per-series plan above. The human takes it from here for download:

1. Use the search terms to find documents
2. Drop them in data/manual/<country>/_inbox/ (will create scaffold next)
3. Tell me when a batch is ready and I'll route them

Ready to emit infrastructure and create the inbox? (yes/no)
```

### Phase D: Infrastructure emission

Once the series plan is confirmed:

1. **Create the directory scaffold**: `data/manual/<country>/` with subdirectories per series (one per confirmed series in Phase B). Plus `_inbox/` and `_inbox/_excluded/`.

2. **Generate `R/pull_<country>.R`** following the template in `R/pull_malaysia.R`:
   - One series-helper function per confirmed series (e.g., `get_<country>_econ_report_urls()`)
   - Each helper emits a tibble with the canonical schema (`year, package_id, pdf_url, country, source, body, doc_language, access_status, local_path, notes`)
   - For series with no known direct PDFs, emit all rows as `access_status = "manual"` with the anchor URL as `pdf_url` (landing page; user clicks through)
   - For series with verified direct PDFs (rare; e.g., Malaysia's PRIHATIN/PENJANA), set `access_status = "auto"` with `direct_pdf` populated
   - Include the `resolve_manual_paths()` helper (copy from `pull_malaysia.R` — it's country-agnostic)
   - Master `get_<country>_urls()` binds all series, filters by window, applies `resolve_manual_paths`

3. **Append country config to `R/build_country_configs.R`**:

   ```r
   <country> = list(
     country = "<country>",
     pilot_year_min = <min>L,
     pilot_year_max = <max>L,
     primary_language = "<lang_code>",
     notes = "<one-line context>"
   )
   ```

4. **Add dispatcher case to `R/get_country_urls.R`** if `<country>` is not in the existing `switch()`:

   ```r
   <country> = get_<country>_urls(min_year = config$pilot_year_min,
                                   max_year = config$pilot_year_max),
   ```

5. **Write `data/manual/<country>/README.md`** documenting the drop convention for this country (subdirectories list, filename pattern per series).

6. **Run** `Rscript -e 'targets::tar_make(country_urls, callr_function = NULL)'` to build the new branch and confirm the manifest assembles cleanly with all rows as `manual_pending`.

7. **Present** the initial state summary (Phase F format).

#### PAUSE POINT 4

```
Infrastructure for <country> is in place:

- R/pull_<country>.R created (<N> series-helper functions)
- Country added to build_country_configs.R and get_country_urls.R
- data/manual/<country>/ scaffold created with <K> series subdirs + _inbox/
- Initial manifest: <total> rows, all manual_pending

Ready for you to start dropping PDFs into data/manual/<country>/_inbox/.
When a batch is ready (or you want to see state), tell me.
```

### Phase E: Inbox → assort loop (iterative)

This is the recurring loop the user invokes by saying "I dropped a batch" or similar. Repeat until the user signals the acquisition is complete.

For each invocation:

1. **List `data/manual/<country>/_inbox/`** — single PDFs at the top level, plus any subdirectories (which are usually chapter-sectioned source documents that need concatenation).

2. **For each file (single or directory)**, run the **trap-inspection pass**:
   - **Read first page** of the PDF (or the first chapter file for a directory). Use `pdftools::pdf_text()` first; if empty (scanned), use the Python OCR path (`pymupdf` with `get_textpage_ocr`) or render to image + tesseract.
   - **Classify against the seven-trap inventory** ([malaysia_acquisition.md §6](../../docs/phase_1/malaysia_acquisition.md)):
     1. **State vs federal** — venue must be the federal lower house, speaker the federal Finance Minister or PM
     2. **Supplementary vs regular** — check for "Tambahan" (Malay) / "supplementary" / "additional" markers in the Supply Bill name
     3. **Secondary vs primary** — issuing body must be the federal government (not JICA, IMF, accounting firms, professional associations, academic institutions)
     4. **Adjacent publication** — VNR-style SDG reports, statutory financial statements, audit reports masquerading as fiscal-narrative documents
     5. **Year convention** — match the fiscal year covered, not the delivery date
     6. **Language tag** — verify language by first-page anchor phrases, not filename
     7. **Format heterogeneity** — branded booklet vs speech transcript are both valid; route to the correct series
   - **Match to a manifest row** by inferred (series, year). If no match (e.g., out-of-window year, or new package_id like a stimulus you didn't anticipate), surface this to the user.

3. **For directories (chapter-sectioned source PDFs)**:
   - Apply the priority-ordering heuristic from `pull_malaysia.R`'s concat helper (foreword → numbered chapters → annex → budget → forecast/stats)
   - Concatenate with `pymupdf.insert_pdf()` (PyMuPDF is more robust than R's `pdftools::pdf_combine` for older scanned PDFs — QPDF can fail with `no random data provider` in the dev container)

4. **Present the inspection report** to the user before routing:

   ```
   Inspecting <N> items in _inbox/:
   
   | File / Dir | Inferred series | Year | Language | Trap flags | Action |
   |---|---|---|---|---|---|
   | foo.pdf | Budget Speech | 2015 | BM | none | route to budget_speech/2015.pdf |
   | bar/ (12 chapters) | Economic Report | 2018 | EN | none | concat → economic_report/2018.pdf |
   | baz.pdf | (ambiguous) | ? | ? | possible secondary (issued by Crowe) | needs review |
   ```

5. **For ambiguous or trap-flagged items**, stop and ask the user. Do not route until disambiguation is confirmed.

6. **After routing**, update the per-series `MANIFEST.csv` (language tracking) if applicable, rebuild the manifest, and present the updated state summary (Phase F).

#### PAUSE POINT 5 (per batch)

After routing a batch, present:

```
Routed <N> files (<K> traps flagged, <M> excluded).

[State summary — Phase F format]

What's next? (more files, switch series, or stop here?)
```

### Phase F: State summary (renderable on demand)

This is the live snapshot. Render it after every routing batch, after Phase D, and whenever the user asks "where are we?".

```
Acquisition status — <country>

| Series          | auto | ready | pending | total | % ready |
|-----------------|-----:|------:|--------:|------:|--------:|
| Economic Report |    0 |    20 |       8 |    28 |    71% |
| Budget Speech   |    0 |    15 |       8 |    23 |    65% |
| Central Bank AR |    0 |    12 |      11 |    23 |    52% |
| Development     |    0 |     5 |       2 |     7 |    71% |
| Crisis          |    2 |     2 |       3 |     7 |    57% |
| **Total**       |    2 |    54 |      32 |    88 |    63% |

Language coverage (where applicable):
- <breakdown per series with bilingual content>

Currently in _inbox/_excluded/ (kept for audit, not routed):
- <list of rejected files with reason>

Top pending priorities:
- <years and series still pending that are likely gettable>
- <known dead-ends, e.g., pre-1995 print-only>
```

### Phase G: Completion

When the user signals "done" or the only remaining manual_pending rows are confirmed dead-ends:

1. **Final state summary** (Phase F format) plus an explicit "what's left" inventory.

2. **Write `docs/phase_1/<country>_acquisition.md`** — a country-specific acquisition record mirroring `docs/phase_1/malaysia_acquisition.md` but with the actual country data. Use the same seven-section structure (purpose, mapping, coverage, caveats, workflow, traps, sources/effort).

3. **Suggest a commit message** for the human:

   ```
   Add <country> URL enumeration + acquisition record
   
   - R/pull_<country>.R: <N> series helpers
   - data/manual/<country>/ scaffold + READMEs + MANIFEST.csv per series
   - docs/phase_1/<country>_acquisition.md: methodology record
   ```

4. **Suggest next step**: `tar_make(country_text)` to extract text from the new country's PDFs. Note OCR cost upfront if scanned documents are present.

#### PAUSE POINT 6

```
Acquisition for <country> is complete:

- <total> manifest rows
- <ready_count> ready (<%>)
- <pending_count> pending, of which <dead_end_count> are confirmed dead-ends

Acquisition record drafted at docs/phase_1/<country>_acquisition.md.
Suggested commit and next step printed above.

Anything else before we close out this acquisition?
```

## What This Skill Does NOT Do

- **Does not re-derive the R&R role mapping** — it's settled. See [malaysia_acquisition.md §2](../../docs/phase_1/malaysia_acquisition.md).
- **Does not run text extraction** — that's `tar_make(country_text)`, a separate operation. The skill ends when files are in canonical paths.
- **Does not search for or download PDFs** — the human drives discovery (anti-bot reality).
- **Does not commit changes** — the user commits when satisfied with the acquisition state.
- **Does not produce a Quarto dashboard** — state is displayed in chat per the Malaysia retrospective.
- **Does not emit per-year landing-page URLs** — only one anchor URL per series at most.
- **Does not auto-route files with trap flags or ambiguous identity** — those go to the user before routing.

## Error Handling

- **Country already configured (Phase A check)** — skip to Phase E (continuation mode); confirm with the user first.
- **`tar_make(country_urls)` fails in Phase D** — likely a syntax error in the generated `pull_<country>.R`. Read the error, fix the helper, retry. Do not move on until the manifest assembles.
- **First-page text is empty for a dropped file** — try OCR via `pymupdf` + Tesseract before flagging as ambiguous. If OCR also fails, ask the user what the file is.
- **PDF crypto errors during concatenation** — switch from `pdftools::pdf_combine` to PyMuPDF's `insert_pdf` (the Malaysia run hit `QPDFCrypto_native has no random data provider` on older scanned files).
- **Anti-bot 403/202 during a feasibility probe** — that's the signal: mark the series as `Manual` and move on. Don't spend time fighting it.
- **User drops a file that doesn't match any series** — could be (a) a series we missed during Phase B, (b) an event-specific document (new stimulus), (c) something out of scope. Surface, don't guess.

## Reference: trap inventory (summary)

Full inventory in [malaysia_acquisition.md §6](../../docs/phase_1/malaysia_acquisition.md). One-liners for inline reference:

1. **State vs federal** — state-level budgets (Sabah, Perak) marketed identically to federal in search results
2. **Supplementary vs regular** — supplementary Supply Bills look like regular Budget Speeches but are crisis-event documents
3. **Secondary vs primary** — JICA, Crowe, IEM, academic summaries describing government actions ≠ government primary sources
4. **Adjacent publication** — VNR (SDG report) vs fiscal stimulus; BNM AR vs Economic & Monetary Review post-2020
5. **Year convention** — fiscal year covered, not delivery date (Budget 2026 delivered Oct 2025)
6. **Language tag** — BI = Bahasa Inggeris = English (Malay-language filenames sometimes English content)
7. **Format heterogeneity** — branded booklet (PRIHATIN, PENJANA) vs speech transcript (PERMAI, PEMERKASA, PEMULIH) — both valid

## Reference: Malaysia infrastructure as template

When emitting `R/pull_<country>.R`, lift the structure from `R/pull_malaysia.R`:

- One helper per series (`get_malaysia_economic_report_urls()`, `get_malaysia_budget_speech_urls()`, etc.)
- All emit identical 10-column tibble
- Master `get_malaysia_urls()` binds rows + filters window + applies `resolve_manual_paths()`
- `resolve_manual_paths()` is country-agnostic — copy verbatim
- File-naming conventions:
  - `<year>.pdf` for annual series
  - `rmk<NN>_plan_<year>.pdf` / `rmk<NN>_mtr_<year>.pdf` for plans-with-MTRs pattern
  - `<package_id_lowercase>_<year>.pdf` for crisis booklets

The Python concat helper from the Malaysia work:

```python
import os, re, pymupdf

def file_role(name):
    n = name.lower()
    if re.search(r"foreword|preface|mukadimah", n): return 1
    if re.search(r"contents|kandungan", n): return 2
    if re.search(r"acronym|glosari|abbreviat", n): return 3
    m = re.search(r"(chapter|chapt|bab)[\s_-]*(\d+|[ivxl]+)", n)
    if m:
        s = m.group(2)
        return 100 + (int(s) if s.isdigit() else roman_to_int(s))
    if re.search(r"economy|economic|ekonomi", n): return 800
    if re.search(r"budget|bajet", n): return 810
    if re.search(r"forecast|annex|perangkaan", n): return 900
    return 990
```

Adjust the regex roots to the new country's language(s) (e.g., Spanish for "capítulo", Thai for "บท").

## Composability

This skill is standalone. It does not delegate to other skills.

After completion, the user typically runs:

- `tar_make(country_text)` — text extraction (no skill needed)
- `tar_make(country_c1_predictions, country_c2a_evidence)` — codebook deployment (no skill needed; uses existing pipeline)
- `/log-iteration` if iterating on codebook calibration for the new country

## Companion Document

The full methodology, trap inventory, language considerations, and effort accounting from the Malaysia run are in [docs/phase_1/malaysia_acquisition.md](../../docs/phase_1/malaysia_acquisition.md). Read it before invoking this skill for a new country; it is the manual that this skill operationalizes.
