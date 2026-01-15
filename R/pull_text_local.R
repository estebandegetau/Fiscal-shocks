#' Extract PDF text locally using PyMuPDF with OCR
#'
#' @description
#' Extracts text from PDFs using PyMuPDF with automatic OCR detection for scanned documents.
#' This function calls the Python script `python/pymupdf_extract.py` and caches results
#' locally for efficient re-runs.
#'
#' @param pdf_url Character string or vector of PDF URLs to extract
#' @param output_dir Directory to store extracted JSON files (default: "data/extracted")
#' @param workers Number of parallel Python workers for OCR (default: 4)
#' @param ocr_dpi DPI for OCR rendering (default: 200, higher = better quality but slower)
#' @param use_cache Whether to use cached results if available (default: TRUE)
#'
#' @return A tibble with columns:
#'   - text: list of character vectors (one per page)
#'   - n_pages: integer count of pages
#'   - ocr_used: logical indicating if OCR was needed
#'   - extraction_time: numeric seconds taken for extraction
#'   - extracted_at: POSIXct timestamp
#'
#' @details
#' This function requires:
#' - Python with pymupdf package installed
#' - tesseract-ocr system package for OCR support
#'
#' The function:
#' 1. Checks for cached results in output_dir
#' 2. Downloads PDF if URL provided
#' 3. Detects if OCR is needed (scanned vs text-based PDF)
#' 4. Extracts text with parallel OCR if needed
#' 5. Saves results as JSON for caching
#' 6. Returns tibble compatible with pull_text_lambda() output
#'
#' @examples
#' \dontrun{
#' # Single PDF
#' result <- pull_text_local("https://example.com/doc.pdf")
#'
#' # Multiple PDFs
#' urls <- c("https://example.com/doc1.pdf", "https://example.com/doc2.pdf")
#' results <- pull_text_local(urls)
#'
#' # With targets pipeline
#' tar_target(
#'   us_text,
#'   pull_text_local(us_urls_vector, workers = 4)
#' )
#' }
#'
#' @export
pull_text_local <- function(
    pdf_url,
    output_dir = here::here("data/extracted"),
    workers = 4,
    ocr_dpi = 200,
    use_cache = TRUE
) {

  # Validate input

if (missing(pdf_url) || is.null(pdf_url) || length(pdf_url) == 0) {
    stop("pdf_url is required and cannot be empty")
  }

  # Filter out any empty URLs
  pdf_url <- pdf_url[nzchar(as.character(pdf_url))]

  if (length(pdf_url) == 0) {
    warning("All provided URLs were empty")
    return(tibble::tibble(
      text = list(character(0)),
      n_pages = 0L,
      ocr_used = FALSE,
      extraction_time = NA_real_,
      extracted_at = Sys.time()
    ))
  }

  # Create output directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    message("Created output directory: ", output_dir)
  }

  # Path to Python script
  python_script <- here::here("python/pymupdf_extract.py")

  if (!file.exists(python_script)) {
    stop("Python extraction script not found: ", python_script)
  }

  # Helper function to generate cache filename from URL
  url_to_cache_file <- function(url) {
    # Use MD5 hash of URL for consistent, filesystem-safe filenames
    url_hash <- digest::digest(url, algo = "md5")
    file.path(output_dir, paste0(url_hash, ".json"))
  }

  # Helper function to extract a single PDF
  extract_single_pdf <- function(url, index, total) {
    cache_file <- url_to_cache_file(url)

    # Check cache first
    if (use_cache && file.exists(cache_file)) {
      message(sprintf("[%d/%d] Using cached: %s", index, total, basename(url)))
      tryCatch({
        result <- jsonlite::read_json(cache_file)
        return(result)
      }, error = function(e) {
        message("  Cache file corrupted, re-extracting...")
        file.remove(cache_file)
      })
    }

    message(sprintf("[%d/%d] Extracting: %s", index, total, basename(url)))

    # Build Python command arguments
    args <- c(
      python_script,
      "--input", shQuote(url),
      "--output", shQuote(cache_file),
      "--workers", as.character(workers),
      "--ocr-dpi", as.character(ocr_dpi)
    )

    # Call Python script
    exit_code <- system2(
      "python",
      args = args,
      stdout = "",  # Suppress stdout (progress goes to stderr)
      stderr = ""   # Show stderr for progress
    )

    # Check if extraction succeeded
    if (exit_code != 0 || !file.exists(cache_file)) {
      warning(sprintf("Extraction failed for: %s (exit code: %d)", url, exit_code))
      return(list(
        text = "",
        pages = list(),
        n_pages = 0,
        ocr_used = FALSE,
        extraction_time_seconds = NA_real_,
        extracted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
      ))
    }

    # Read and return result
    tryCatch({
      jsonlite::read_json(cache_file)
    }, error = function(e) {
      warning(sprintf("Failed to parse JSON for: %s - %s", url, e$message))
      list(
        text = "",
        pages = list(),
        n_pages = 0,
        ocr_used = FALSE,
        extraction_time_seconds = NA_real_,
        extracted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
      )
    })
  }

  # Process all PDFs
  message(sprintf("Processing %d PDF(s)...", length(pdf_url)))
  start_time <- Sys.time()

  results <- purrr::imap(pdf_url, function(url, index) {
    extract_single_pdf(url, index, length(pdf_url))
  })

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  message(sprintf("Completed %d PDF(s) in %.1f seconds", length(pdf_url), elapsed))

  # Convert results to tibble
  # Match format of pull_text_lambda() for compatibility
  output <- tibble::tibble(
    text = purrr::map(results, function(r) {
      # Return pages as list of character strings
      pages <- r$pages
      if (is.null(pages) || length(pages) == 0) {
        return(list(r$text %||% ""))
      }
      as.list(pages)
    }),
    n_pages = purrr::map_int(results, function(r) {
      as.integer(r$n_pages %||% 0)
    }),
    ocr_used = purrr::map_lgl(results, function(r) {
      isTRUE(r$ocr_used)
    }),
    extraction_time = purrr::map_dbl(results, function(r) {
      r$extraction_time_seconds %||% NA_real_
    }),
    extracted_at = Sys.time()
  )

  # Validate output
  successful <- sum(output$n_pages > 0)
  message(sprintf("Extraction complete: %d/%d successful", successful, nrow(output)))

  if (successful == 0) {
    warning("No PDFs were successfully extracted. Check Python environment and network connectivity.")
  }

  return(output)
}
