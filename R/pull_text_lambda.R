#' Extract PDF text using AWS Lambda + Docling
#'
#' @description
#' Triggers AWS Lambda functions in parallel to extract text from PDFs using Docling.
#' Results are uploaded to S3 and polled until complete.
#'
#' @param pdf_url Character string or vector of PDF URLs to extract
#' @param bucket S3 bucket name for storing results (default: from AWS_S3_BUCKET env var or "fiscal-shocks-pdfs")
#' @param lambda_function Lambda function name (default: from LAMBDA_FUNCTION_NAME env var or "fiscal-shocks-pdf-extractor")
#' @param poll_interval Seconds to wait between S3 polling attempts (default: 30)
#' @param max_wait_time Maximum seconds to wait for all extractions (default: 600 = 10 minutes)
#' @param do_table_structure Enable table structure extraction (default: TRUE)
#'
#' @return A tibble with columns:
#'   - text: list of character vectors (one per page)
#'   - tables: list of table structures for Model C (markdown + cells)
#'   - n_pages: integer count of pages
#'   - n_tables: integer count of extracted tables
#'   - extracted_at: POSIXct timestamp
#'
#' @details
#' This function requires:
#' - AWS credentials configured via environment variables or ~/.aws/credentials
#' - paws.storage and paws.compute packages installed
#' - Lambda function deployed with Docling extraction code
#'
#' The function:
#' 1. Invokes Lambda asynchronously for each PDF
#' 2. Lambda extracts text and uploads JSON to S3
#' 3. R polls S3 until all JSONs appear
#' 4. Parses JSONs and returns tibble
#'
#' @examples
#' \dontrun{
#' # Single PDF
#' result <- pull_text_lambda("https://example.com/doc.pdf")
#'
#' # Multiple PDFs with targets
#' tar_target(
#'   us_text,
#'   pull_text_lambda(us_urls_vector),
#'   pattern = map(us_urls_vector),
#'   iteration = "vector"
#' )
#' }
#'
#' @export
pull_text_lambda <- function(
    pdf_url,
    bucket = Sys.getenv("AWS_S3_BUCKET", unset = "fiscal-shocks-pdfs"),
    lambda_function = Sys.getenv("LAMBDA_FUNCTION_NAME", unset = "fiscal-shocks-pdf-extractor"),
    poll_interval = 30,
    max_wait_time = 600,
    do_table_structure = TRUE
) {

  # Validate input
  if (missing(pdf_url) || is.null(pdf_url) || length(pdf_url) == 0 || all(!nzchar(as.character(pdf_url)))) {
    warning("pdf_url is missing or empty")
    return(tibble::tibble(
      text = list(NA_character_),
      n_pages = 0L,
      extracted_at = Sys.time()
    ))
  }

  # Filter out any empty URLs
  pdf_url <- pdf_url[nzchar(as.character(pdf_url))]

  # Load required packages
  if (!requireNamespace("paws.storage", quietly = TRUE)) {
    stop("Package 'paws.storage' is required. Install with: install.packages('paws.storage')")
  }
  if (!requireNamespace("paws.compute", quietly = TRUE)) {
    stop("Package 'paws.compute' is required. Install with: install.packages('paws.compute')")
  }

  # Initialize AWS clients
  s3 <- paws.storage::s3()
  lambda <- paws.compute::lambda()

  # Generate S3 output key from URL
  # Format: extracted/{year}/{source}/{filename}.json
  generate_s3_key <- function(url) {
    # Extract filename from URL
    filename <- basename(url)
    # Remove .pdf extension and add .json
    filename_json <- paste0(tools::file_path_sans_ext(filename), ".json")

    # Try to extract year and source from URL
    year <- stringr::str_extract(url, "\\d{4}") %||% "unknown"
    source <- dplyr::case_when(
      stringr::str_detect(url, "govinfo|erp") ~ "erp",
      stringr::str_detect(url, "treasury") ~ "treasury",
      stringr::str_detect(url, "budget") ~ "budget",
      TRUE ~ "other"
    )

    file.path("extracted", year, source, filename_json)
  }

  # Invoke Lambda function
  invoke_lambda <- function(url) {
    s3_key <- generate_s3_key(url)

    payload <- list(
      pdf_url = url,
      output_key = s3_key,
      do_table_structure = do_table_structure
    )

    tryCatch({
      response <- lambda$invoke(
        FunctionName = lambda_function,
        InvocationType = "Event",  # Async invocation
        Payload = jsonlite::toJSON(payload, auto_unbox = TRUE)
      )

      # Return S3 key for polling
      list(url = url, s3_key = s3_key, status = "invoked")

    }, error = function(e) {
      warning("Failed to invoke Lambda for URL: ", url, " - ", e$message)
      list(url = url, s3_key = s3_key, status = "failed", error = e$message)
    })
  }

  # Invoke Lambdas for all URLs
  message("Invoking Lambda for ", length(pdf_url), " PDF(s)...")

  # Sequential invocation is fine - Lambda handles parallelism on AWS side

  # Each invoke() with InvocationType="Event" returns instantly (~100ms)
  # 350 invocations × 100ms = ~35 seconds, then AWS runs all in parallel
  invocations <- purrr::map(pdf_url, invoke_lambda, .progress = TRUE)

  # Extract S3 keys to poll
  s3_keys <- purrr::map_chr(invocations, "s3_key")

  # Poll S3 for results
  message("Polling S3 for results (max wait: ", max_wait_time, "s)...")

  start_time <- Sys.time()
  results <- vector("list", length(s3_keys))
  names(results) <- s3_keys

  while (any(purrr::map_lgl(results, is.null))) {
    # Check timeout
    if (as.numeric(difftime(Sys.time(), start_time, units = "secs")) > max_wait_time) {
      warning("Timeout reached. ", sum(purrr::map_lgl(results, is.null)), " PDFs incomplete.")
      break
    }

    # Check each missing key
    for (i in seq_along(s3_keys)) {
      if (!is.null(results[[i]])) next  # Already retrieved

      key <- s3_keys[i]

      # Try to get object from S3
      obj <- tryCatch({
        s3$get_object(Bucket = bucket, Key = key)
      }, error = function(e) NULL)

      if (!is.null(obj)) {
        # Parse JSON
        json_text <- rawToChar(obj$Body)
        parsed <- jsonlite::fromJSON(json_text)
        results[[i]] <- parsed
      }
    }

    # Progress update
    n_complete <- sum(!purrr::map_lgl(results, is.null))
    if (n_complete < length(results)) {
      message(n_complete, "/", length(results), " complete. Waiting ", poll_interval, "s...")
      Sys.sleep(poll_interval)
    }
  }

  # Convert results to tibble
  parse_result <- function(result, url) {
    if (is.null(result)) {
      # Timeout or failed
      return(tibble::tibble(
        text = list(NA_character_),
        tables = list(NULL),
        n_pages = 0L,
        n_tables = 0L,
        extracted_at = Sys.time()
      ))
    }

    if (!is.null(result$error) && nzchar(result$error)) {
      warning("Extraction error for ", url, ": ", result$error)
      return(tibble::tibble(
        text = list(NA_character_),
        tables = list(NULL),
        n_pages = 0L,
        n_tables = 0L,
        extracted_at = Sys.time()
      ))
    }

    pages <- result$pages
    if (!is.character(pages) || length(pages) == 0) {
      return(tibble::tibble(
        text = list(NA_character_),
        tables = list(NULL),
        n_pages = 0L,
        n_tables = 0L,
        extracted_at = Sys.time()
      ))
    }

    # Extract tables (structured data for Model C)
    tables_data <- result$tables
    if (is.null(tables_data) || length(tables_data) == 0) {
      tables_data <- list()
    }

    tibble::tibble(
      text = list(pages),
      tables = list(tables_data),
      n_pages = as.integer(result$n_pages),
      n_tables = as.integer(result$n_tables %||% length(tables_data)),
      extracted_at = Sys.time()
    )
  }

  # Map results back to URLs
  output <- purrr::map2_dfr(results, pdf_url, parse_result)

  message("Extraction complete: ", sum(output$n_pages > 0), "/", nrow(output), " successful")

  return(output)
}
