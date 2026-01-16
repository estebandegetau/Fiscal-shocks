#' Create sliding window chunks from extracted pages
#'
#' Splits documents into overlapping chunks that fit within LLM context windows.
#' Uses a sliding window approach to ensure context continuity across chunk boundaries.
#'
#' @param pages_df Data frame with document metadata and text column (list of page texts)
#' @param window_size Number of pages per chunk (default: 50)
#' @param overlap Number of overlapping pages between consecutive chunks (default: 10)
#' @param max_tokens Maximum estimated tokens per chunk (default: 40000)
#' @param chars_per_token Assumed characters per token for estimation (default: 4)
#'
#' @return Data frame with columns:
#'   - doc_id: Document identifier
#'   - chunk_id: Chunk number within document
#'   - start_page: First page number in chunk (1-indexed)
#'   - end_page: Last page number in chunk
#'   - n_pages: Number of pages in chunk
#'   - text: Combined text from all pages in chunk
#'   - approx_tokens: Estimated token count
#'
#' @examples
#' \dontrun{
#' chunks <- make_chunks(us_body, window_size = 50, overlap = 10)
#' # Each chunk will have ~50 pages with 10-page overlap
#' }
#'
#' @export
make_chunks <- function(pages_df,
                        window_size = 50,
                        overlap = 10,
                        max_tokens = 40000,
                        chars_per_token = 4) {

  if (!is.data.frame(pages_df)) {
    stop("pages_df must be a data frame")
  }

  if (!"text" %in% names(pages_df)) {
    stop("pages_df must have a 'text' column containing list of page texts")
  }

  if (overlap >= window_size) {
    stop("overlap must be less than window_size")
  }

  # Process each document
  chunks <- purrr::map_dfr(seq_len(nrow(pages_df)), function(i) {
    doc <- pages_df[i, ]

    # Get document identifier
    doc_id <- if ("package_id" %in% names(doc)) {
      doc$package_id
    } else if ("doc_id" %in% names(doc)) {
      doc$doc_id
    } else {
      paste0("doc_", i)
    }

    # Get year if available
    doc_year <- if ("year" %in% names(doc)) doc$year else NA_integer_

    # Get pages - handle both list columns and character vectors
    pages <- doc$text[[1]]

    if (is.null(pages) || length(pages) == 0) {
      message(sprintf("Document %s has no pages, skipping", doc_id))
      return(NULL)
    }

    n_pages <- length(pages)

    # Calculate chunk boundaries using sliding window
    step <- window_size - overlap
    starts <- seq(1, n_pages, by = step)

    # Create chunks for this document
    doc_chunks <- purrr::map_dfr(seq_along(starts), function(j) {
      start_page <- starts[j]
      end_page <- min(start_page + window_size - 1, n_pages)

      # Get pages for this chunk
      chunk_pages <- pages[start_page:end_page]

      # Combine pages with clear separators
      chunk_text <- paste(chunk_pages, collapse = "\n\n--- PAGE BREAK ---\n\n")

      # Estimate token count
      approx_tokens <- nchar(chunk_text) / chars_per_token

      tibble::tibble(
        doc_id = doc_id,
        year = doc_year,
        chunk_id = j,
        start_page = start_page,
        end_page = end_page,
        n_pages = end_page - start_page + 1,
        text = chunk_text,
        approx_tokens = round(approx_tokens)
      )
    })

    doc_chunks
  })

  # Report summary
  if (nrow(chunks) > 0) {
    message(sprintf(
      "Created %d chunks from %d documents (avg %.1f chunks/doc, avg %.0f tokens/chunk)",
      nrow(chunks),
      nrow(pages_df),
      nrow(chunks) / nrow(pages_df),
      mean(chunks$approx_tokens)
    ))

    # Warn about chunks exceeding max_tokens
    over_limit <- sum(chunks$approx_tokens > max_tokens)
    if (over_limit > 0) {
      warning(sprintf(
        "%d chunks exceed max_tokens (%d). Consider reducing window_size.",
        over_limit, max_tokens
      ))
    }
  }

  chunks
}


#' Validate chunks fit within LLM context
#'
#' @param chunks Data frame from make_chunks()
#' @param max_tokens Maximum allowed tokens (default: 40000 for Claude with buffer)
#'
#' @return Logical indicating if all chunks fit
#'
#' @export
validate_chunks <- function(chunks, max_tokens = 40000) {
  if (!"approx_tokens" %in% names(chunks)) {
    stop("chunks must have 'approx_tokens' column")
  }

  over_limit <- chunks$approx_tokens > max_tokens
  n_over <- sum(over_limit)

  if (n_over > 0) {
    message(sprintf(
      "WARNING: %d/%d chunks (%.1f%%) exceed %d tokens",
      n_over, nrow(chunks), 100 * n_over / nrow(chunks), max_tokens
    ))

    # Show worst offenders
    worst <- chunks |>
      dplyr::filter(over_limit) |>
      dplyr::arrange(dplyr::desc(approx_tokens)) |>
      dplyr::slice_head(n = 5) |>
      dplyr::select(doc_id, chunk_id, n_pages, approx_tokens)

    message("Largest chunks:")
    print(worst)

    return(FALSE)
  }

  message(sprintf("All %d chunks fit within %d token limit", nrow(chunks), max_tokens))
  TRUE
}


#' Summarize chunks by document
#'
#' @param chunks Data frame from make_chunks()
#'
#' @return Summary data frame with document-level statistics
#'
#' @export
summarize_chunks <- function(chunks) {
  chunks |>
    dplyr::group_by(doc_id, year) |>
    dplyr::summarize(
      n_chunks = dplyr::n(),
      total_pages = sum(n_pages) - sum(n_pages - (end_page - start_page + 1)),
      total_tokens = sum(approx_tokens),
      avg_tokens_per_chunk = mean(approx_tokens),
      max_tokens = max(approx_tokens),
      .groups = "drop"
    ) |>
    dplyr::arrange(year, doc_id)
}
