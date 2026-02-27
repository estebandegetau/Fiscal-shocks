pull_text <- function(pdf_url) {

    # Validate input
    if (missing(pdf_url) || is.null(pdf_url) || !nzchar(as.character(pdf_url))) {
        warning("pdf_url is missing or empty")
        return(tibble::tibble(
            text = list(NA_character_),
            n_pages = 0L,
            extracted_at = Sys.time()
        ))
    }

    # Create a temporary file (safe filename with .pdf extension)
    temp_file <- tempfile(fileext = ".pdf")

    # Ensure temporary file is removed when the function exits
    on.exit({
        if (file.exists(temp_file)) unlink(temp_file)
    }, add = TRUE)

    # Download the PDF
    dl_ok <- tryCatch({
        utils::download.file(as.character(pdf_url), temp_file, mode = "wb", quiet = TRUE)
        TRUE
    }, error = function(e) {
        warning(paste("Failed to download PDF from", pdf_url, ":", e$message))
        FALSE
    })

    if (!isTRUE(dl_ok) || !file.exists(temp_file) || file.info(temp_file)$size == 0) {
        warning(paste("Downloaded file is missing or empty for URL:", pdf_url))
        return(tibble::tibble(
            text = list(NA_character_),
            n_pages = 0L,
            extracted_at = Sys.time()
        ))
    }

    # Extract text from PDF using pdftools
    text <- tryCatch({
        pdftools::pdf_text(temp_file)
    }, error = function(e) {
        warning(paste("Failed to extract text from PDF:", e$message))
        NA_character_
    })

    # Determine number of pages robustly
    n_pages <- 0L
    if (is.character(text) && length(text) > 0 && !(length(text) == 1 && is.na(text))) {
        n_pages <- length(text)
    } else {
        # ensure text is a NA_character_ for consistency
        text <- NA_character_
    }

    # Combine input variables with extracted text metadata
    res <- tibble::tibble(
        text = list(text),  # Store as list column
        n_pages = as.integer(n_pages),
        extracted_at = Sys.time()
    )

    return(res)
}
