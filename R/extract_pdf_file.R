#' Extract text from a single local PDF via PyMuPDF
#'
#' Thin R wrapper around `python/pymupdf_extract.py`. Caching is the
#' responsibility of `{targets}` (the calling target uses `format = "file"`
#' on the input path), so unlike `pull_text_local()` this function does
#' NOT maintain its own MD5-keyed JSON cache under `data/extracted/`.
#'
#' Used by per-file dynamic branches inside `tarchetypes::tar_map()` over
#' `country_configs`. One branch per PDF; PyMuPDF runs once and the
#' result is stored in the targets object cache.
#'
#' @param path Absolute path to a PDF file
#' @param ocr_dpi Integer OCR rendering DPI (default 200; same as US)
#' @param workers Integer parallel workers for OCR pages (default 6)
#' @return One-row tibble with columns `text` (list of per-page chars),
#'   `n_pages`, `ocr_used`, `extraction_time`, `extracted_at`. Missing
#'   files return the same schema with `n_pages = 0L`.
#' @export
extract_pdf_file <- function(path,
                             ocr_dpi = 200L,
                             workers = 6L) {
  empty_result <- tibble::tibble(
    text = list(character(0)),
    n_pages = 0L,
    ocr_used = FALSE,
    extraction_time = NA_real_,
    extracted_at = Sys.time()
  )

  if (!file.exists(path)) {
    warning("PDF not found, returning empty extraction: ", path,
            call. = FALSE)
    return(empty_result)
  }

  python_script <- here::here("python/pymupdf_extract.py")
  if (!file.exists(python_script)) {
    stop("Python extraction script not found: ", python_script)
  }

  tmp_json <- tempfile(fileext = ".json")
  on.exit(unlink(tmp_json), add = TRUE)

  args <- c(
    python_script,
    "--input", shQuote(path),
    "--output", shQuote(tmp_json),
    "--workers", as.character(workers),
    "--ocr-dpi", as.character(ocr_dpi)
  )

  exit_code <- system2("python", args = args, stdout = "", stderr = "")

  if (exit_code != 0 || !file.exists(tmp_json)) {
    warning(sprintf("Extraction failed for %s (exit code %d)", path, exit_code),
            call. = FALSE)
    return(empty_result)
  }

  result <- tryCatch(
    jsonlite::read_json(tmp_json),
    error = function(e) {
      warning(sprintf("Failed to parse extraction JSON for %s: %s",
                      path, e$message), call. = FALSE)
      NULL
    }
  )
  if (is.null(result)) return(empty_result)

  pages <- result$pages
  if (is.null(pages) || length(pages) == 0L) {
    pages <- list(result$text %||% "")
  }

  tibble::tibble(
    text = list(as.list(pages)),
    n_pages = as.integer(result$n_pages %||% length(pages)),
    ocr_used = isTRUE(result$ocr_used),
    extraction_time = result$extraction_time_seconds %||% NA_real_,
    extracted_at = Sys.time()
  )
}
