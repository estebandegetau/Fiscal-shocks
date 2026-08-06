# Render codebook YAML into manuscript exhibits
#
# The manuscript prints the codebooks verbatim so a reader can judge the
# construct rather than take our word for it. Everything here reads
# prompts/*.yml at render time, so the printed codebook cannot drift from the
# one the pipeline ran.

#' Read a codebook YAML
#' @param path Path to a codebook YAML under prompts/
#' @return The parsed `codebook` block
read_codebook <- function(path) {
  yaml::read_yaml(path)$codebook
}

#' The codebook's instruction block, as a markdown blockquote
#'
#' Prints the prompt text the model actually receives. Emit from a chunk with
#' `output: asis`.
#'
#' @param path Path to a codebook YAML
#' @return Invisible NULL (called for its output)
codebook_instructions_md <- function(path) {
  cb <- read_codebook(path)
  txt <- trimws(cb$instructions %||% "")
  # Blank lines inside a blockquote need their own marker or the quote breaks.
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  cat("\n")
  cat(paste0("> ", trimws(lines), collapse = "\n"), "\n\n", sep = "")
  invisible(NULL)
}

#' The codebook's class definitions
#'
#' One row per label with its definition, plus counts of the inclusion and
#' exclusion clarifications that sit under it. The clarifications themselves
#' are long; the appendix carries them verbatim.
#'
#' @param path Path to a codebook YAML
#' @return Tidy tibble
codebook_classes_table <- function(path) {
  cb <- read_codebook(path)
  classes <- cb$classes
  if (is.null(classes) || length(classes) == 0) return(tibble::tibble())

  # Codebook prose carries markdown emphasis for the model's benefit. Table
  # cells are not markdown-processed on the way to Typst, where a bare "**"
  # parses as an empty strong marker, so strip the markers here.
  plain <- function(x) {
    x <- gsub("\\*\\*(.*?)\\*\\*", "\\1", x)
    x <- gsub("\\s+", " ", x)
    trimws(x)
  }

  purrr::map(classes, function(cl) {
    tibble::tibble(
      Label          = cl$label %||% NA_character_,
      Definition     = plain(cl$label_definition %||% ""),
      `Inclusions`   = length(cl$clarification %||% list()),
      `Exclusions`   = length(cl$negative_clarification %||% list())
    )
  }) |>
    dplyr::bind_rows()
}

#' A codebook verbatim, as a fenced YAML block
#'
#' Used by the appendix. Emit from a chunk with `output: asis`.
#'
#' @param path Path to a codebook YAML
#' @return Invisible NULL (called for its output)
codebook_verbatim_md <- function(path) {
  cat("\n``` yaml\n")
  cat(readLines(path, warn = FALSE), sep = "\n")
  cat("\n```\n\n")
  invisible(NULL)
}
