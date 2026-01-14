# Integrating Lambda PDF Extraction with Targets Pipeline

## Overview

This guide shows how to update your `_targets.R` file to use the new Lambda-based PDF extraction instead of the slow local Docling extraction.

---

## Before (Local Docling Extraction)

**Current `_targets.R` excerpt:**

```r
# Current slow approach - 17+ hours for 350 PDFs
tar_target(
  us_text,
  command = {
    pull_text_docling(us_urls_vector)
  },
  pattern = map(us_urls_vector),
  iteration = "vector"
)
```

**Problems:**
- Each PDF spawns a new Python subprocess
- Sequential processing (one PDF at a time)
- 12+ hours runtime on laptop

---

## After (Lambda Extraction)

**Updated `_targets.R`:**

```r
# Load environment variables at the start of _targets.R
if (file.exists(".env")) {
  dotenv::load_dot_env()
}

# ... existing code ...

# New fast approach - 5-10 minutes for 350 PDFs
tar_target(
  us_text,
  pull_text_lambda(
    pdf_url = us_urls_vector,
    bucket = Sys.getenv("AWS_S3_BUCKET", "fiscal-shocks-pdfs"),
    lambda_function = Sys.getenv("LAMBDA_FUNCTION_NAME", "fiscal-shocks-pdf-extractor"),
    poll_interval = 30,
    max_wait_time = 600,
    do_table_structure = TRUE
  ),
  pattern = map(us_urls_vector),
  iteration = "vector"
)
```

**Benefits:**
- 350 parallel Lambda invocations
- 5-10 minutes total runtime
- Automatic retry and error handling

---

## Complete Example

Here's a complete example showing the full integration:

```r
# _targets.R

# Load packages
library(targets)
library(tarchetypes)
library(crew)

# Load environment variables for AWS credentials
if (file.exists(".env")) {
  dotenv::load_dot_env()
}

# Source all functions
lapply(list.files("R", pattern = "\\.R$", full.names = TRUE), source)

# Set target options
tar_option_set(
  packages = c(
    "tidyverse",
    "pdftools",
    "quanteda",
    "tidytext",
    "here",
    "rvest",
    "googledrive",
    "paws.storage",
    "paws.compute",
    "dotenv"
  ),
  controller = crew_controller_local(
    name = "local",
    workers = 4,
    seconds_idle = 10
  )
)

# Define pipeline
list(
  # ===== Stage 1: URL Collection =====

  tar_target(
    erp_urls,
    fetch_erp_urls()
  ),

  tar_target(
    budget_urls,
    fetch_budget_urls()
  ),

  tar_target(
    annual_report_urls,
    fetch_treasury_annual_report_urls()
  ),

  # Combine all URLs
  tar_target(
    us_urls_vector,
    c(erp_urls$pdf_url, budget_urls$pdf_url, annual_report_urls$pdf_url)
  ),

  # ===== Stage 2: PDF Extraction (LAMBDA VERSION) =====

  tar_target(
    us_text,
    pull_text_lambda(
      pdf_url = us_urls_vector,
      bucket = Sys.getenv("AWS_S3_BUCKET", "fiscal-shocks-pdfs"),
      lambda_function = Sys.getenv("LAMBDA_FUNCTION_NAME", "fiscal-shocks-pdf-extractor"),
      poll_interval = 30,
      max_wait_time = 600,
      do_table_structure = TRUE,
      use_parallel = TRUE
    ),
    pattern = map(us_urls_vector),
    iteration = "vector"
  ),

  # ===== Stage 3: Text Processing =====

  tar_target(
    us_urls,
    bind_rows(erp_urls, budget_urls, annual_report_urls) |>
      bind_cols(us_text) |>
      select(-pdf_url1)
  ),

  tar_target(
    relevance_keys,
    c(
      "tax", "revenue", "fiscal", "budget", "spending",
      "appropriation", "deficit", "surplus", "act", "bill",
      "legislation", "congress", "reform"
    )
  ),

  tar_target(
    pages,
    make_pages(us_urls, relevance_keys)
  ),

  tar_target(
    documents,
    make_documents(pages)
  ),

  tar_target(
    paragraphs,
    make_paragraphs(pages, relevance_keys)
  ),

  tar_target(
    relevant_paragraphs,
    make_relevant_paragraphs(paragraphs)
  ),

  # ===== Reference Data =====

  tar_target(
    us_shocks,
    read_csv(here("data/raw/us_shocks.csv")) |>
      clean_us_shocks(),
    format = "file"
  ),

  tar_target(
    us_labels,
    read_csv(here("data/raw/us_labels.csv")) |>
      clean_us_labels(us_shocks),
    format = "file"
  )
)
```

---

## Switching Between Local and Lambda

You can easily switch between local and Lambda extraction by creating a configuration flag:

```r
# At the top of _targets.R
USE_LAMBDA <- TRUE  # Set to FALSE for local extraction

# ... existing code ...

# PDF extraction target
tar_target(
  us_text,
  if (USE_LAMBDA) {
    pull_text_lambda(
      pdf_url = us_urls_vector,
      bucket = Sys.getenv("AWS_S3_BUCKET", "fiscal-shocks-pdfs"),
      lambda_function = Sys.getenv("LAMBDA_FUNCTION_NAME", "fiscal-shocks-pdf-extractor")
    )
  } else {
    pull_text_docling(us_urls_vector)
  },
  pattern = map(us_urls_vector),
  iteration = "vector"
)
```

---

## Testing the Integration

### 1. Test on Small Subset First

Before running on all 350 PDFs, test on a small subset:

```r
# In R console
library(targets)

# Load environment
dotenv::load_dot_env()

# Test on first 5 URLs
tar_option_set(
  packages = c("tidyverse", "paws.storage", "paws.compute")
)

source("R/pull_text_lambda.R")
source("R/pull_us.R")

# Get first 5 URLs
erp_urls <- fetch_erp_urls()
test_urls <- head(erp_urls$pdf_url, 5)

# Test extraction
test_results <- purrr::map_dfr(test_urls, pull_text_lambda)

# Check results
test_results
# A tibble: 5 × 3
#   text        n_pages extracted_at
#   <list>      <int>   <dttm>
# 1 <chr [100]>    100 2025-01-13 15:30:00
# 2 <chr [80]>      80 2025-01-13 15:30:15
# ...
```

### 2. Run Full Pipeline

Once testing succeeds:

```r
# Clean cache (optional)
tar_destroy()

# Run full pipeline
tar_make()

# Check progress
tar_progress()

# View network
tar_visnetwork()
```

### 3. Verify Results

```r
# Load extracted text
us_text <- tar_read(us_text)

# Summary statistics
summary(us_text$n_pages)
#   Min. 1st Qu.  Median    Mean 3rd Qu.    Max.
#      1      45      80      75     110     250

# Check for failures
failed <- us_text |> filter(n_pages == 0)
nrow(failed)
# [1] 0  # Ideally no failures
```

---

## Handling Extraction Failures

Some PDFs may fail to extract. Here's how to handle them:

```r
# In _targets.R, add a retry target
tar_target(
  us_text_with_retry,
  {
    # First attempt
    results <- pull_text_lambda(us_urls_vector)

    # Identify failures
    failed_idx <- which(results$n_pages == 0)

    if (length(failed_idx) > 0) {
      message("Retrying ", length(failed_idx), " failed extractions...")

      # Retry failed URLs
      retry_results <- purrr::map_dfr(
        us_urls_vector[failed_idx],
        ~ pull_text_lambda(.x, max_wait_time = 900)  # Longer timeout
      )

      # Replace failures with retries
      results[failed_idx, ] <- retry_results
    }

    results
  },
  pattern = map(us_urls_vector),
  iteration = "vector"
)
```

---

## Fallback Strategy

For maximum robustness, use Lambda with local fallback:

```r
tar_target(
  us_text_hybrid,
  {
    # Try Lambda first
    result <- tryCatch({
      pull_text_lambda(us_urls_vector)
    }, error = function(e) {
      warning("Lambda extraction failed: ", e$message)
      NULL
    })

    # Fallback to local if Lambda fails
    if (is.null(result) || result$n_pages == 0) {
      message("Falling back to local Docling extraction...")
      result <- pull_text_docling(us_urls_vector)
    }

    result
  },
  pattern = map(us_urls_vector),
  iteration = "vector"
)
```

---

## Monitoring Lambda Extraction

### Real-time Progress

The `pull_text_lambda()` function prints progress messages:

```
Invoking Lambda for 350 PDF(s)...
Polling S3 for results (max wait: 600s)...
70/350 complete. Waiting 30s...
140/350 complete. Waiting 30s...
210/350 complete. Waiting 30s...
280/350 complete. Waiting 30s...
350/350 complete. Waiting 30s...
Extraction complete: 347/350 successful
```

### CloudWatch Logs

View Lambda execution logs:

```bash
# Follow Lambda logs in real-time
aws logs tail /aws/lambda/fiscal-shocks-pdf-extractor --follow

# Filter for errors only
aws logs filter-pattern /aws/lambda/fiscal-shocks-pdf-extractor --filter-pattern "ERROR"
```

---

## Cost Tracking

Track Lambda costs within your pipeline:

```r
# In _targets.R
tar_target(
  extraction_cost_estimate,
  {
    n_pdfs <- length(us_urls_vector)
    avg_runtime_seconds <- 120  # 2 minutes average
    memory_gb <- 3
    cost_per_gb_second <- 0.0000166667

    total_cost <- n_pdfs * avg_runtime_seconds * memory_gb * cost_per_gb_second

    tibble(
      n_pdfs = n_pdfs,
      estimated_cost_usd = total_cost,
      timestamp = Sys.time()
    )
  }
)

# View cost estimate
tar_read(extraction_cost_estimate)
# A tibble: 1 × 3
#   n_pdfs estimated_cost_usd timestamp
#   <int>  <dbl>              <dttm>
# 1    350  6.04               2025-01-13 15:30:00
```

---

## Next Steps

After successful Lambda integration:

1. **Verify data quality**: Check that extracted text is complete and tables are preserved
2. **Compare with local**: Run local extraction on a few PDFs to validate Lambda results match
3. **Proceed to Days 2-3**: Training data preparation (see `docs/plan_phase0.md`)

---

## Troubleshooting

### "AWS credentials not configured"

**Solution**: Create `.env` file from `.env.example` and add credentials

### "Lambda function not found"

**Solution**: Run `./lambda_deploy.sh` first

### "S3 bucket does not exist"

**Solution**: The deployment script creates it automatically. Check AWS console or run:
```bash
aws s3 mb s3://fiscal-shocks-pdfs
```

### "Timeout after 600 seconds"

**Solution**: Increase `max_wait_time`:
```r
pull_text_lambda(us_urls_vector, max_wait_time = 1200)  # 20 minutes
```

### "Some PDFs failed to extract"

**Solution**: Check Lambda logs for specific errors, then retry individual PDFs:
```r
failed_urls <- us_urls_vector[us_text$n_pages == 0]
retry_results <- purrr::map_dfr(failed_urls, pull_text_lambda)
```

---

## Reference

- [Phase 0 Plan](plan_phase0.md)
- [Lambda Deployment Guide](lambda_deployment_guide.md)
- [Targets Manual](https://books.ropensci.org/targets/)
