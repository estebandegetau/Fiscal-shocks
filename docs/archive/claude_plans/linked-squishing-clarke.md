# Implementation Plan: Verification Notebook & Documentation Updates

## Overview

This plan covers two tasks to complete before implementing Days 2-3 of Phase 0:

1. **Create `verify_body.qmd`**: A comprehensive verification notebook for testing extraction quality of `us_body` target
2. **Update Phase 0 documentation**: Archive Lambda-based approach, document actual local PyMuPDF implementation

## Context

We recently extracted US document text locally using PyMuPDF (with OCR fallback) instead of the planned AWS Lambda + Docling approach due to persistent Lambda OCR bugs. Before proceeding with LLM training data preparation (Days 2-3), we need to verify extraction quality and update documentation to reflect the actual implementation.

### Key Data Structures

**`us_body` target structure:**
- Columns from `us_urls`: year, package_id, pdf_url, country, source, body
- Columns from `us_text`: text (list-column), n_pages, ocr_used, extraction_time, extracted_at
- `text` column: list-column where each element is a list of character vectors (one per page)
- `body` categories: "Economic Report of the President", "Budget of the United States Government", "Annual Report of the Treasury"
- Years: 1946-present
- Sources: govinfo.gov, fraser.stlouisfed.org, home.treasury.gov

---

## Task 1: Create `notebooks/verify_body.qmd`

### Objective

Create a country-agnostic verification notebook that validates:
1. PDF URL resolution and page counts
2. Boundary document quality (earliest/latest per source)
3. Known act validation (documents contain expected fiscal acts from `us_labels.csv`)
4. Temporal and source coverage completeness
5. Text quality indicators (OCR quality, readable content)
6. Anomaly detection (duplicates, unusual patterns)

### Implementation Details

**File to create:** `/workspaces/Fiscal-shocks/notebooks/verify_body.qmd`

**Section Structure:**

```yaml
# YAML Header
title: "Document Extraction Verification: {params$country}"
subtitle: "Data completeness and parsing quality checks"
params:
  country: "US"
  body_target: "us_body"
  labels_target: "us_labels"
  min_year: 1946
  max_year: !expr lubridate::year(Sys.Date())
```

**Test Sections:**

#### Section 1: Setup & Load Data
- Load required packages: tidyverse, targets, quanteda, kableExtra, DT, plotly
- Load `us_body` target using `tar_read()`
- Load `us_labels` for known act validation
- Define fiscal vocabulary terms

#### Section 2: Overview Statistics
- Display total documents, successful extractions, total pages
- Visualize pages extracted by year, source, and body (stacked bar chart)
- Show distribution of page counts (histogram + boxplot by body)

#### Section 3: Test (i) - PDF URL Resolution & Page Count Validation
**What to test:**
- Identify documents with `n_pages == 0` (failed extractions)
- Calculate success rate by source/body
- Show OCR usage distribution

**Outputs:**
- Table of failed extractions (if any)
- Success rate bar chart by source/body
- OCR usage stacked bar chart
- Page count distribution histogram

**Pass/Fail Criteria:**
- PASS: success_rate ≥ 95%
- WARN: success_rate 85-95%
- FAIL: success_rate < 85%

#### Section 4: Test (ii) - Boundary Document Verification
**What to test:**
- Identify earliest and latest document per source/body
- Extract sample pages (first, middle, last) from boundary documents
- Display truncated sample text (1000 chars) to verify readability

**Outputs:**
- Table: boundary documents (year, n_pages, ocr_used, boundary_type)
- Sample text displays for each boundary document
- Visual checkmarks for: readable text, contains expected metadata, has fiscal terms

**Pass/Fail Criteria:**
- PASS: All boundary docs have n_pages ≥ 10 and readable text
- WARN: Some boundary docs have n_pages < 10 or partial garbling
- FAIL: Boundary docs missing or unreadable

#### Section 5: Test (iii) - Known Act Validation
**What to test:**
- Join `us_labels` with `us_body` by year
- Search for act names in extracted text
- Search for labeled text passages (fuzzy match, 80% threshold for OCR tolerance)
- Calculate act name recall and passage recall

**Outputs:**
- Table: Act name | Year | Expected passages | Found passages | Recall rate | Status
- Sample matched passages with context (3-5 examples)
- Sample failures (passages not found)
- Overall metrics: act name recall %, passage recall %

**Pass/Fail Criteria:**
- PASS: act_name_recall ≥ 90% AND passage_recall ≥ 70%
- WARN: act_name_recall ≥ 80% OR passage_recall ≥ 50%
- FAIL: act_name_recall < 80% OR passage_recall < 50%

**Note:** Lower passage recall threshold accounts for OCR errors and paraphrasing

#### Section 6: Test (iv) - Temporal & Source Coverage
**What to test:**
- Create expected coverage grid (year × body)
- Mark known gaps (e.g., Treasury 1981-2010)
- Compare actual vs expected document counts
- Identify missing documents

**Outputs:**
- Heatmap: Year (x) × Body (y) with color = document count
  - Grey: not expected
  - Red: missing expected documents
  - Green: present
- Table of coverage gaps
- Summary: total years, expected docs, actual docs, coverage rate

**Pass/Fail Criteria:**
- PASS: coverage_rate ≥ 95%
- WARN: coverage_rate 85-95%
- FAIL: coverage_rate < 85%

#### Section 7: Test (v) - Text Quality Indicators
**What to test:**
- Character-level quality: special char rate, non-ASCII rate, whitespace rate
- Token counts per page
- Fiscal vocabulary presence (% pages with fiscal terms)
- Identify suspicious pages (too short, too many special chars, no fiscal terms)

**Outputs:**
- Distribution plots: tokens per page, special char rates, non-ASCII rates
- Table of low-quality documents (quality_score < 0.5)
- Sample suspicious pages (first 500 chars)
- Fiscal term coverage summary

**Pass/Fail Criteria:**
- PASS: < 5% suspicious pages AND > 70% pages with fiscal terms
- WARN: 5-10% suspicious OR 50-70% fiscal pages
- FAIL: ≥ 10% suspicious OR ≤ 50% fiscal pages

#### Section 8: Test (vi) - Anomaly Detection
**What to test:**
- Document anomalies: too short/long, missing structural elements, slow extraction
- Duplicate detection (hash first 5 pages)
- Year-level trends: sudden drops in total pages

**Outputs:**
- Table of anomalous documents with flags
- Line chart: total pages per year by body (highlight drops)
- Duplicate documents table
- Summary: count of each anomaly type

**Status:** INFO only (flags for manual review, doesn't fail)

#### Section 9: Summary Report & Pass/Fail Dashboard
**Outputs:**
- Consolidated test results table with color-coded status
- Overall status: PASS / WARN / FAIL
- Recommendations for next steps:
  - PASS → proceed with `tar_make(chunks)`
  - WARN → review flagged issues
  - FAIL → address critical issues before proceeding

### Parameterization for Reusability

The notebook is designed to be country-agnostic:
- Parameters: country, body_target, labels_target, min_year, max_year, expected_bodies, fiscal_vocab
- Adaptive logic: skips known act validation if labels not available
- Future use: create `verify_body_malaysia.qmd` with different parameters

### Critical Files Referenced

1. **Input data:**
   - `_targets/objects/us_body` (via `tar_read()`)
   - `_targets/objects/us_labels` (via `tar_read()`)

2. **Reference examples:**
   - `/workspaces/Fiscal-shocks/notebooks/test_lambda_output.qmd` (existing test patterns)
   - `/workspaces/Fiscal-shocks/R/cleaning.r` (text manipulation examples)

3. **Documentation:**
   - `/workspaces/Fiscal-shocks/docs/phase_0/plan_phase0.md` (success criteria)

---

## Task 2: Update Phase 0 Documentation

### Objective

Archive outdated AWS Lambda documentation and create new documentation reflecting the actual local PyMuPDF + OCR implementation.

### Background

Git history shows the Lambda approach failed due to OCR bugs:
```
765c28f: "This lambda handler works almost correctly, but has a persistent bug
         that prevents using OCR to extract the text from PDFs. Hence, we
         extracted locally."
6fb649f: "pymudpdf extraction working correctly"
```

**Current approach:** Local PyMuPDF extraction with OCR fallback (using `pull_text_local()` in R)

### Documentation Update Strategy

#### Phase 1: Archive Lambda Documentation (HIGH Priority)

**Create archive directory:**
```
docs/phase_0/archived_lambda/
```

**Move these files to archive:**
1. `lambda_deployment_guide.md` (523 lines - comprehensive Lambda deployment)
2. `lambda_targets_integration.md` (494 lines - R integration code)
3. `QUICKSTART_LAMBDA.md` (118 lines - quick reference)
4. `DEPLOYMENT_OPTIONS.md` (155 lines - Lambda Docker deployment)

**Add deprecation notice to each:**
```markdown
# ⚠️ DEPRECATED - Archived for Historical Reference

This document described the AWS Lambda + Docling approach for PDF extraction,
which was attempted but abandoned due to persistent OCR bugs that prevented
text extraction from scanned PDFs.

**Current implementation:** Local PyMuPDF extraction with OCR fallback.
See `LOCAL_PYMUPDF_EXTRACTION.md` for current approach.

**Reason for deprecation:** Lambda + OCR had unresolved bugs (commit 765c28f).
Local PyMuPDF extraction works correctly (commit 6fb649f).

---

[Original content follows...]
```

#### Phase 2: Update Existing Documentation (HIGH Priority)

**File: `docs/phase_0/plan_phase0.md`**

**Lines 41-97: Replace "Days 1-2: Cloud PDF Extraction" section**

New section title: `### **Days 1-2: Local PDF Extraction with PyMuPDF**`

**Content to include:**
- **Objective:** Replace slow laptop-based Docling with faster local PyMuPDF + OCR
- **Solution:** Local Python script using PyMuPDF (fitz) with OCR fallback via pytesseract
- **Architecture:**
  ```
  350 PDF URLs → pull_text_local() → parallel workers → PyMuPDF extraction →
  OCR fallback (if needed) → JSON cache → R tibble
  ```
- **Key files:**
  - `R/pull_text_local.R`: R wrapper for parallel extraction
  - `python/extract_pymupdf.py`: Python extraction script (if exists, or inline)
- **Configuration:**
  - Workers: 6 parallel processes
  - OCR DPI: 200 (for scanned documents)
  - Output: `data/extracted/` directory with JSON cache
- **Performance:**
  - Extraction time: ~X minutes for 350 PDFs (measured in test_lambda_output.qmd)
  - Cost: $0 (local processing)
- **Integration with Targets:**
  ```r
  tar_target(
    us_text,
    pull_text_local(
      pdf_url = us_urls_vector,
      output_dir = here::here("data/extracted"),
      workers = 6,
      ocr_dpi = 200
    )
  )
  ```

**Lines 96: Update cost estimate**
- Change from "~$6.04" to "~$0 (local extraction, no cloud costs)"

**File: `docs/phase_0/days_1-2_implementation_summary.md`**

**Complete rewrite needed:**

**New title:** `# Days 1-2: Local PDF Extraction Implementation Summary`

**Sections to include:**
1. **Overview:**
   - Abandoned AWS Lambda approach due to OCR bugs
   - Implemented local PyMuPDF extraction with OCR fallback
   - Successfully extracted 350 PDFs locally

2. **Architecture:**
   - Diagram showing: URL → `pull_text_local()` → parallel workers → PyMuPDF → OCR → JSON → tibble

3. **Key Features:**
   - ✅ Parallel processing (6 workers)
   - ✅ OCR fallback for scanned PDFs
   - ✅ JSON caching for reproducibility
   - ✅ No cloud dependencies
   - ✅ Zero extraction costs

4. **Implementation:**
   - File: `R/pull_text_local.R`
   - Dependencies: PyMuPDF (fitz), pytesseract
   - Output structure: tibble with text (list-column), n_pages, ocr_used, extraction_time, extracted_at

5. **Performance:**
   - Include actual metrics from verification tests
   - Extraction time per document
   - OCR usage rate

6. **Why This Approach:**
   - Lambda OCR bug (commit 765c28f)
   - Simpler deployment (no AWS setup)
   - Faster iteration (local testing)
   - Actually works (commit 6fb649f)

**File: `docs/phase_0/COST_ESTIMATES_REVISED.md`**

**Lines 52-69: Update Lambda cost section**

Replace with:
```markdown
### PDF Extraction Costs

**Approach:** Local PyMuPDF extraction with OCR fallback

| Component | Cost |
|-----------|------|
| Local computation | $0 (using existing hardware) |
| PyMuPDF library | $0 (open source) |
| Pytesseract OCR | $0 (open source) |
| Data storage | $0 (local disk) |
| **Total PDF extraction** | **$0** |

**Note:** Original plan estimated $6.04 for AWS Lambda extraction, but this approach
was abandoned due to OCR bugs. Local extraction eliminates cloud costs entirely.
```

**Lines 227-232: Update recommended changes**

Add note:
```markdown
**Update (Dec 2024):** Lambda extraction approach was abandoned. All cost estimates
should remove AWS Lambda costs ($6.04) and note that extraction is now performed
locally at zero cost.
```

#### Phase 3: Create New Documentation (MEDIUM Priority)

**New file: `docs/phase_0/LOCAL_PYMUPDF_EXTRACTION.md`**

**Content outline:**
1. **Overview:** Local PyMuPDF extraction approach
2. **Requirements:**
   - Python dependencies: PyMuPDF, pytesseract, Pillow
   - System dependencies: tesseract-ocr
   - R packages: here, tidyverse, furrr (for parallel processing)
3. **Setup Instructions:**
   - Installing Python dependencies
   - Installing Tesseract OCR
   - Configuring parallel workers
4. **Usage:**
   - Basic usage: `pull_text_local(pdf_url, output_dir, workers, ocr_dpi)`
   - Output structure explanation
   - Caching mechanism
5. **How It Works:**
   - PDF download (if needed)
   - PyMuPDF text extraction
   - OCR fallback detection (if no text found)
   - JSON caching for reproducibility
6. **Troubleshooting:**
   - OCR not working (tesseract not installed)
   - Slow extraction (reduce workers)
   - Memory issues (large PDFs)
7. **Performance Benchmarks:**
   - Link to verification results
   - Typical extraction times
   - OCR usage rates

**New file: `docs/phase_0/MIGRATION_FROM_LAMBDA.md`** (optional)

**Content:**
- Why we migrated (Lambda OCR bugs)
- What changed (architecture comparison)
- Code changes needed (minimal - just switch flag in `_targets.R`)
- Performance comparison (local vs Lambda)

### Documentation File Structure After Updates

```
docs/phase_0/
├── plan_phase0.md (UPDATED - Days 1-2 section rewritten)
├── days_1-2_implementation_summary.md (UPDATED - complete rewrite)
├── COST_ESTIMATES_REVISED.md (UPDATED - Lambda costs removed)
├── LOCAL_PYMUPDF_EXTRACTION.md (NEW - current approach)
├── MIGRATION_FROM_LAMBDA.md (NEW - optional historical context)
└── archived_lambda/ (NEW directory)
    ├── DEPRECATION_NOTICE.md (NEW - explains why archived)
    ├── lambda_deployment_guide.md (MOVED from parent)
    ├── lambda_targets_integration.md (MOVED from parent)
    ├── QUICKSTART_LAMBDA.md (MOVED from parent)
    └── DEPLOYMENT_OPTIONS.md (MOVED from parent)
```

### Critical Files to Update

**HIGH Priority (Days 1-2 content):**
1. `/workspaces/Fiscal-shocks/docs/phase_0/plan_phase0.md` (lines 41-97)
2. `/workspaces/Fiscal-shocks/docs/phase_0/days_1-2_implementation_summary.md` (complete rewrite)
3. `/workspaces/Fiscal-shocks/docs/phase_0/COST_ESTIMATES_REVISED.md` (lines 52-69, 227-232)

**MEDIUM Priority (new documentation):**
4. `/workspaces/Fiscal-shocks/docs/phase_0/LOCAL_PYMUPDF_EXTRACTION.md` (new file)
5. `/workspaces/Fiscal-shocks/docs/phase_0/archived_lambda/DEPRECATION_NOTICE.md` (new file)

**LOW Priority (archiving):**
6. Move 4 Lambda docs to `archived_lambda/` with deprecation headers

---

## Implementation Order

### Step 1: Create Verification Notebook (Task 1)
**Priority:** HIGH - needed before proceeding with Days 2-3

1. Create `notebooks/verify_body.qmd` with all 9 sections
2. Implement test logic following design specifications
3. Run notebook: `quarto render notebooks/verify_body.qmd`
4. Review results and ensure PASS status before proceeding

**Estimated time:** 3-4 hours

**Success criteria:**
- Notebook runs without errors
- All tests execute and display results
- Overall status is PASS or WARN (with justification)
- Dashboard displays clearly with color-coded status

### Step 2: Update Core Documentation (Task 2, Phase 1 & 2)
**Priority:** HIGH - needed for accurate Phase 0 record

1. Create `docs/phase_0/archived_lambda/` directory
2. Move 4 Lambda docs with deprecation notices
3. Rewrite Days 1-2 section in `plan_phase0.md`
4. Rewrite `days_1-2_implementation_summary.md`
5. Update cost estimates in `COST_ESTIMATES_REVISED.md`

**Estimated time:** 2-3 hours

**Success criteria:**
- Documentation accurately reflects current implementation
- All Lambda references are archived or updated
- Cost estimates reflect $0 extraction costs

### Step 3: Create New Documentation (Task 2, Phase 3)
**Priority:** MEDIUM - helpful for future reference

1. Create `LOCAL_PYMUPDF_EXTRACTION.md`
2. Optionally create `MIGRATION_FROM_LAMBDA.md`

**Estimated time:** 1-2 hours

**Success criteria:**
- New documentation clearly explains current approach
- Setup instructions are complete and accurate
- Troubleshooting section addresses common issues

---

## Verification Plan

### After Task 1 (Verification Notebook):
1. Run `quarto render notebooks/verify_body.qmd`
2. Review HTML output for:
   - All test sections completed
   - Dashboard shows test results
   - Sample text displays are readable
   - Pass/Fail criteria are evaluated correctly
3. Check that known acts from `us_labels.csv` are successfully found
4. Verify overall status (should be PASS if extraction was successful)

### After Task 2 (Documentation Updates):
1. Review updated files for accuracy:
   - `plan_phase0.md` Days 1-2 section describes local PyMuPDF
   - `days_1-2_implementation_summary.md` no longer mentions Lambda
   - Cost estimates show $0 for extraction
2. Verify archived Lambda docs have deprecation notices
3. Confirm new documentation is comprehensive and accurate

### Final Check:
- Run verification notebook again to ensure reproducibility
- Compare verification results with success criteria from Phase 0 plan
- Confirm ready to proceed with Days 2-3 (training data preparation)

---

## Notes & Considerations

### Design Decisions

1. **Separation of concerns:**
   - `test_lambda_output.qmd` → LLM performance testing (small sample)
   - `verify_body.qmd` → Full dataset verification (all 350 docs)

2. **Parameterization:**
   - Notebook uses params for country-agnostic reuse
   - Can create `verify_body_malaysia.qmd` with minimal changes

3. **Known act validation:**
   - Most valuable test (leverages ground truth)
   - Fuzzy matching tolerates OCR errors (80% threshold)

4. **Documentation strategy:**
   - Archive rather than delete (preserves historical context)
   - Deprecation notices explain why approach changed
   - New docs focus on current working implementation

### Potential Issues & Solutions

**Issue:** Known act validation may have low recall if OCR quality is poor
**Solution:** Adjust fuzzy match threshold in test, flag for manual review if < 70%

**Issue:** Some PDFs may have legitimately failed (404 errors, broken URLs)
**Solution:** Test (i) allows 0 pages if URL doesn't resolve, only fails if < 85% success

**Issue:** Documentation updates are extensive
**Solution:** Prioritize high-impact files (plan_phase0.md, days_1-2 summary), defer optional docs

**Issue:** Verification notebook may take long to run on 350 documents
**Solution:** Use caching (`cache: true` in YAML), store results in `_targets` if needed

---

## Success Criteria

### Task 1: Verification Notebook
- ✅ Notebook runs successfully: `quarto render notebooks/verify_body.qmd`
- ✅ All 9 test sections execute without errors
- ✅ Dashboard displays with color-coded status
- ✅ Known act validation achieves ≥ 80% recall
- ✅ Overall status is PASS or WARN (with documented reasons)

### Task 2: Documentation Updates
- ✅ Lambda docs archived with deprecation notices
- ✅ `plan_phase0.md` Days 1-2 section describes local PyMuPDF
- ✅ `days_1-2_implementation_summary.md` accurately reflects current approach
- ✅ Cost estimates updated to show $0 extraction costs
- ✅ New `LOCAL_PYMUPDF_EXTRACTION.md` provides setup instructions

### Overall
- ✅ Phase 0 documentation accurately reflects implementation
- ✅ Verification confirms extraction quality is sufficient for LLM processing
- ✅ Ready to proceed with Days 2-3 (training data preparation)

---

## Next Steps After This Plan

Once verification and documentation are complete:

1. **Proceed with Days 2-3:** Training data preparation
   - Align `us_labels.csv` with `us_shocks.csv`
   - Create train/val/test splits
   - Generate negative examples for Model A

2. **Update `_targets.R`:** Add verification target
   ```r
   tar_quarto(
     verify_body_report,
     "notebooks/verify_body.qmd"
   )
   ```

3. **Update project README:** Add verification step to workflow

4. **Consider automation:** Run verification notebook as part of CI/CD for future countries
