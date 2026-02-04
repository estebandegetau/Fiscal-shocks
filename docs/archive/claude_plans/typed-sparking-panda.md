# Plan: Optimize PDF Extraction Pipeline

## Selected Approaches
- **Speed:** Lambda + PyMuPDF (rebuild container with Tesseract)
- **Chunking:** Sliding window with overlap

---

## Current Issues

### Issue 1: Documents Don't Fit LLM Context
- 2 documents = 668 pages = 520K tokens
- Claude 3.5 Sonnet context = 200K tokens
- **Need chunking/batching strategy**

### Issue 2: Extraction Speed Too Slow
- 2 documents in ~10 minutes = 5 min/doc average
- 350 documents × 5 min = ~29 hours locally
- **Need faster processing**

### Issue 3: Act Detection Rate Below Target
- 67% (2/3 acts found) vs 80% target
- Note: TEFRA (1982) may not be in ERP 1982 - this could be a data issue, not extraction issue

---

## Proposed Solutions

### Solution A: Speed - Deploy PyMuPDF+OCR to Lambda

**Approach:** Update Lambda container to use PyMuPDF+Tesseract instead of Docling

**Pros:**
- Reuse existing Lambda infrastructure
- Parallel processing across 350+ concurrent Lambda invocations
- ~15 minutes for entire corpus (vs 29 hours locally)
- Cost: ~$5-10 for full run

**Cons:**
- Requires rebuilding Docker image
- Lambda has 15-min timeout (should be enough for PyMuPDF - it's faster than Docling)
- Need to install Tesseract in container

**Implementation:**
1. Update `Dockerfile.lambda` to install Tesseract + PyMuPDF
2. Replace Docling handler with PyMuPDF handler
3. Redeploy Lambda
4. Use existing `pull_text_lambda.R` (it already handles S3 polling)

### Solution B: Speed - Increase Local Workers

**Approach:** Increase parallel workers from 4 to 8-16

**Current:** 4 workers, ~1.6 sec/page OCR
**With 8 workers:** Potentially 2x faster = ~14 hours
**With 16 workers:** Potentially 4x faster = ~7 hours

**Pros:**
- No infrastructure changes
- Simple: just change `workers = 8` or `workers = 16`

**Cons:**
- Memory-limited (each worker needs ~500MB)
- CPU-limited (diminishing returns past CPU count)
- Still 7-14 hours

**Check available resources:**
```bash
nproc  # CPU cores
free -h  # Available memory
```

### Solution C: Speed - AWS Batch (No Timeout)

**Approach:** Use AWS Batch for unlimited runtime

**Pros:**
- No 15-min timeout
- Spot instances = cheap (~$15-25 total)
- Can process largest documents

**Cons:**
- More complex setup
- Overkill if PyMuPDF fits in Lambda timeout

### Solution D: Chunking - Page-Based Batching

**Approach:** Process documents in page batches for LLM

**Strategy:**
```
For each document:
  1. Extract all pages (already done)
  2. Group pages into chunks of ~50 pages (~40K tokens)
  3. Send each chunk to Claude separately
  4. Aggregate results
```

**Implementation in downstream pipeline:**
- Modify `make_pages()` or add `make_chunks()` target
- Each chunk = 50 pages ≈ 40K tokens
- 668 pages ÷ 50 = 14 chunks for 2 documents

---

## Recommended Plan

### Phase 1: Speed Optimization (Pick One)

**Option A: Lambda + PyMuPDF** (Recommended if you want fastest)
- Estimated time: 15-30 minutes for full corpus
- Cost: ~$5-10
- Requires: Docker rebuild, Lambda redeploy

**Option B: More Local Workers** (Recommended for simplicity)
- Estimated time: 7-14 hours (overnight run)
- Cost: $0
- Requires: Just change `workers` parameter

### Phase 2: Chunking Strategy

Add chunking target to pipeline:
```r
tar_target(
  chunks,
  make_chunks(pages, max_tokens = 40000)  # ~50 pages per chunk
)
```

### Phase 3: Update Quality Metrics

The "Act name recall" failure may be a false positive:
- TEFRA was passed in 1982, but may not be discussed in ERP 1982
- Check if it appears in later ERPs
- Consider adjusting expected acts for each document

---

## Quick Decision Matrix

| Option | Time | Cost | Complexity |
|--------|------|------|------------|
| Local (4 workers) | 29 hours | $0 | Already done |
| Local (8 workers) | ~14 hours | $0 | Trivial |
| Local (16 workers) | ~7 hours | $0 | Trivial |
| Lambda + PyMuPDF | ~15 min | ~$5-10 | Medium |
| AWS Batch | ~30 min | ~$15-25 | High |

---

## Files to Modify

### If choosing Lambda approach:
1. `Dockerfile.lambda` - Replace Docling with PyMuPDF+Tesseract
2. `python/lambda_handler.py` - Use PyMuPDF extraction
3. `lambda_deploy.sh` - Rebuild and deploy

### If choosing more workers:
1. `_targets.R` - Change `workers = 4` to `workers = 8` or higher
2. `R/pull_text_local.R` - No changes needed

### For chunking (needed regardless):
1. `R/functions_stage01.R` or new file - Add `make_chunks()` function
2. `_targets.R` - Add chunks target

---

---

## Implementation Plan

### Step 1: Update Lambda Container for PyMuPDF + Tesseract

**File: `Dockerfile.lambda`**

Replace Docling dependencies with lighter PyMuPDF + Tesseract:

```dockerfile
FROM public.ecr.aws/lambda/python:3.11

# Install Tesseract OCR
RUN yum install -y tesseract tesseract-langpack-eng && yum clean all

# Install Python dependencies
COPY requirements-lambda.txt .
RUN pip install --no-cache-dir -r requirements-lambda.txt

# Copy handler
COPY python/lambda_handler.py ${LAMBDA_TASK_ROOT}/

CMD ["lambda_handler.handler"]
```

**File: `requirements-lambda.txt`** (new, simpler)
```
pymupdf>=1.26.0
boto3
```

### Step 2: Update Lambda Handler

**File: `python/lambda_handler.py`**

Replace Docling extraction with PyMuPDF+OCR logic from `pymupdf_extract.py`:

```python
import json
import boto3
import pymupdf
import tempfile
import os
from urllib.request import urlretrieve

s3 = boto3.client('s3')
BUCKET = os.environ.get('S3_BUCKET', 'fiscal-shocks-pdfs')

def handler(event, context):
    pdf_url = event['pdf_url']
    output_key = event['output_key']

    # Download PDF
    with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as f:
        urlretrieve(pdf_url, f.name)
        pdf_path = f.name

    # Extract with OCR
    doc = pymupdf.open(pdf_path)
    pages = []
    for page in doc:
        # Use OCR for scanned pages
        tp = page.get_textpage_ocr(language="eng", dpi=200, full=True)
        pages.append(page.get_text(textpage=tp))

    result = {
        "pages": pages,
        "n_pages": len(pages),
        "ocr_used": True
    }

    # Upload to S3
    s3.put_object(
        Bucket=BUCKET,
        Key=output_key,
        Body=json.dumps(result)
    )

    return {"status": "success", "n_pages": len(pages)}
```

### Step 3: Redeploy Lambda

```bash
./lambda_deploy.sh --build --deploy
```

### Step 4: Implement Sliding Window Chunking

**File: `R/make_chunks.R`** (new)

```r
#' Create sliding window chunks from pages
#'
#' @param pages_df Data frame with text column (list of page texts)
#' @param window_size Number of pages per chunk (default: 50)
#' @param overlap Number of overlapping pages (default: 10)
#' @param max_tokens Maximum tokens per chunk (default: 40000)
#'
#' @return Data frame with chunk_id, doc_id, pages, text
make_chunks <- function(pages_df,
                        window_size = 50,
                        overlap = 10,
                        max_tokens = 40000) {

  chunks <- purrr::map_dfr(seq_len(nrow(pages_df)), function(i) {
    doc <- pages_df[i, ]
    pages <- doc$text[[1]]
    n_pages <- length(pages)

    if (n_pages == 0) return(NULL)

    # Calculate chunk boundaries
    step <- window_size - overlap
    starts <- seq(1, n_pages, by = step)

    purrr::map_dfr(seq_along(starts), function(j) {
      start_page <- starts[j]
      end_page <- min(start_page + window_size - 1, n_pages)

      chunk_pages <- pages[start_page:end_page]
      chunk_text <- paste(chunk_pages, collapse = "\n\n---PAGE BREAK---\n\n")

      tibble::tibble(
        doc_id = doc$package_id %||% i,
        chunk_id = j,
        start_page = start_page,
        end_page = end_page,
        n_pages = end_page - start_page + 1,
        text = chunk_text,
        approx_tokens = nchar(chunk_text) / 4
      )
    })
  })

  chunks
}
```

### Step 5: Update `_targets.R`

Add chunking target:

```r
tar_target(
  chunks,
  make_chunks(
    us_body,
    window_size = 50,   # 50 pages per chunk
    overlap = 10,       # 10 page overlap
    max_tokens = 40000  # ~40K tokens per chunk
  )
)
```

---

## Verification

1. **Rebuild and deploy Lambda:**
   ```bash
   ./lambda_deploy.sh --build --deploy
   ```

2. **Test Lambda with single PDF:**
   ```r
   source("R/pull_text_lambda.R")
   result <- pull_text_lambda(
     "https://fraser.stlouisfed.org/files/docs/publications/ERP/1965/ERP_1965.pdf"
   )
   # Should complete in <5 minutes
   ```

3. **Run full extraction:**
   ```r
   tar_make(us_text)  # ~15-30 minutes for 350 docs
   ```

4. **Verify chunking:**
   ```r
   tar_make(chunks)
   chunks <- tar_read(chunks)
   # Check: all chunks < 50K tokens
   summary(chunks$approx_tokens)
   ```

5. **Test chunk with Claude:**
   ```r
   # Send one chunk to Claude API to verify it processes correctly
   ```

---

## Expected Outcomes

| Metric | Before | After |
|--------|--------|-------|
| Extraction time | 29 hours | ~15-30 min |
| Cost | $0 | ~$5-10 |
| Chunk size | 520K tokens | ~40K tokens |
| Chunks per doc | 1 (too big) | ~6-7 |
| LLM context fit | NO | YES |

---

## Fix: Tesseract OCR Not Working in Lambda

### Root Cause
The current Lambda deployment returns `[OCR Error: No tessdata specified and Tesseract is not installed]` because:

1. **Base image is Amazon Linux 2** (`public.ecr.aws/lambda/python:3.11`)
2. **EPEL installation is failing silently** - the fallback `/usr/bin/python2` method doesn't work reliably
3. **tessdata path may be wrong** - AL2 installs to `/usr/share/tesseract/tessdata` but this varies

### Solution: Fix EPEL Installation Method

**File: `Dockerfile.lambda`**

Replace the current Tesseract installation with the correct AL2 approach:

```dockerfile
FROM public.ecr.aws/lambda/python:3.11

# Install EPEL repository and Tesseract OCR on Amazon Linux 2
# Use amazon-linux-extras which is the standard AL2 method
RUN yum install -y amazon-linux-extras && \
    amazon-linux-extras install -y epel && \
    yum install -y tesseract tesseract-langpack-eng && \
    yum clean all

# Verify Tesseract installation (fail build if not working)
RUN which tesseract && tesseract --version && \
    ls -la /usr/share/tesseract/tessdata/eng.traineddata

# Build dependencies for PyMuPDF
RUN yum install -y gcc gcc-c++ make && \
    yum clean all

# Python dependencies
RUN pip install --upgrade pip && \
    pip install --no-cache-dir --prefer-binary pymupdf boto3

# Set tessdata path (AL2 default location)
ENV TESSDATA_PREFIX=/usr/share/tesseract/tessdata

# Copy handler
COPY python/lambda_handler.py ${LAMBDA_TASK_ROOT}/

CMD ["lambda_handler.handler"]
```

**Key changes:**
1. Install `amazon-linux-extras` package first (may not be pre-installed)
2. Use `amazon-linux-extras install -y epel` directly (not Python wrapper)
3. Add verification step that **fails the build** if Tesseract isn't properly installed
4. Verify tessdata file exists before setting path

### Alternative: Use Pre-built Tesseract Layer

If yum installation continues to fail, use the community-maintained [bweigel/aws-lambda-tesseract-layer](https://github.com/bweigel/aws-lambda-tesseract-layer):

1. Download latest release from GitHub
2. Deploy as a separate Lambda layer
3. Attach layer to Lambda function
4. Set `TESSDATA_PREFIX=/opt/tesseract/tessdata` (layer location)

### Verification Steps

1. **Build locally and verify Tesseract:**
```bash
docker build --platform linux/amd64 -t fiscal-shocks-pdf-extractor -f Dockerfile.lambda .
docker run -it --entrypoint bash fiscal-shocks-pdf-extractor
# Inside container:
which tesseract
tesseract --version
ls -la $TESSDATA_PREFIX
```

2. **Test OCR locally:**
```bash
docker run -p 9000:8080 fiscal-shocks-pdf-extractor
# In another terminal:
curl -X POST "http://localhost:9000/2015-03-31/functions/function/invocations" \
  -d '{"pdf_url":"https://fraser.stlouisfed.org/files/docs/publications/ERP/1965/ERP_1965.pdf","output_key":"test/ERP_1965.json"}'
```

3. **Check last page doesn't have OCR error:**
```r
result$text |> unlist() |> last()
# Should NOT contain "[OCR Error:"
```
