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

pull_text_docling <- function(
    pdf_url,
    python = Sys.getenv("DOCLING_PYTHON", unset = "python"),
    script = Sys.getenv("DOCLING_SCRIPT", unset = file.path("python", "docling_extract.py")),
    log_on_failure = TRUE,
    keep_artifacts = FALSE
) {

    if (missing(pdf_url) || is.null(pdf_url) || !nzchar(as.character(pdf_url))) {
        warning("pdf_url is missing or empty")
        return(tibble::tibble(
            text = list(NA_character_),
            n_pages = 0L,
            extracted_at = Sys.time()
        ))
    }

    temp_file <- tempfile(fileext = ".pdf")
    on.exit({
        if (file.exists(temp_file)) unlink(temp_file)
    }, add = TRUE)

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

    out_json <- tempfile(fileext = ".json")
    on.exit({
        if (!isTRUE(keep_artifacts) && file.exists(out_json)) unlink(out_json)
    }, add = TRUE)

    if (!file.exists(script)) {
        stop("Docling extractor script not found: ", script)
    }

    stdout_file <- tempfile(fileext = ".log")
    stderr_file <- tempfile(fileext = ".log")
    on.exit({
        if (!isTRUE(keep_artifacts) && file.exists(stdout_file)) unlink(stdout_file)
        if (!isTRUE(keep_artifacts) && file.exists(stderr_file)) unlink(stderr_file)
    }, add = TRUE)

    exit_status <- tryCatch({
        system2(
            command = python,
            args = c(
                shQuote(script),
                "--input", shQuote(temp_file),
                "--output", shQuote(out_json)
            ),
            stdout = stdout_file,
            stderr = stderr_file
        )
    }, error = function(e) {
        warning("Failed to run docling extractor: ", e$message)
        1L
    })

    if (!identical(exit_status, 0L) || !file.exists(out_json) || file.info(out_json)$size == 0) {
        if (isTRUE(log_on_failure)) {
            log_tail <- function(path, n = 80L) {
                if (!file.exists(path) || is.na(file.info(path)$size) || file.info(path)$size == 0) return(NULL)
                x <- tryCatch(readLines(path, warn = FALSE), error = function(e) NULL)
                if (is.null(x) || length(x) == 0) return(NULL)
                paste(tail(x, n = n), collapse = "\n")
            }

            stderr_tail <- log_tail(stderr_file)
            stdout_tail <- log_tail(stdout_file)

            msg <- paste0(
                "Docling extractor failed (status=", exit_status, "). ",
                "python=", shQuote(python), ", script=", shQuote(script), "."
            )
            if (isTRUE(keep_artifacts)) {
                msg <- paste0(
                    msg,
                    " stdout_log=", shQuote(stdout_file),
                    ", stderr_log=", shQuote(stderr_file),
                    ", out_json=", shQuote(out_json),
                    "."
                )
            }
            if (!is.null(stderr_tail) && nzchar(stderr_tail)) {
                msg <- paste0(msg, "\n--- stderr (tail) ---\n", stderr_tail)
            }
            if (!is.null(stdout_tail) && nzchar(stdout_tail)) {
                msg <- paste0(msg, "\n--- stdout (tail) ---\n", stdout_tail)
            }
            warning(msg, call. = FALSE)
        }
        return(tibble::tibble(
            text = list(NA_character_),
            n_pages = 0L,
            extracted_at = Sys.time()
        ))
    }

    parsed <- tryCatch({
        jsonlite::fromJSON(out_json)
    }, error = function(e) {
        warning("Failed to parse docling output JSON: ", e$message)
        NULL
    })

    pages <- NA_character_
    n_pages <- 0L
    if (is.list(parsed) && !is.null(parsed$error) && is.character(parsed$error) && nzchar(parsed$error)) {
        warning("Docling extractor returned an error: ", parsed$error)
    } else if (is.list(parsed) && !is.null(parsed$pages) && is.character(parsed$pages) && length(parsed$pages) > 0) {
        pages <- parsed$pages
        n_pages <- length(pages)
    }

    tibble::tibble(
        text = list(pages),
        n_pages = as.integer(n_pages),
        extracted_at = Sys.time()
    )
}
