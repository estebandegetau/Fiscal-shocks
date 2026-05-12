#' Discover PDFs for a country, filtered by year window
#'
#' Walks `data/manual/<country>/<series>/*.pdf` (one level deep, no recursion
#' into underscore-prefixed staging folders like `_inbox/`), parses each
#' filename via `parse_pdf_path()`, and returns the absolute paths whose
#' parsed `base_year` falls inside `[year_min, year_max]`.
#'
#' Used as the `command` of a `tarchetypes::tar_files()` target; each
#' returned path becomes one `format = "file"` branch (content-hashed).
#' Re-evaluated on every `tar_make()`, so adding a PDF or extending the
#' year window auto-extends the branch set.
#'
#' Unparseable filenames are dropped with a warning. Files outside the
#' year window are silently dropped (the year window is the scope authority).
#'
#' @param country Lowercase country slug (`"malaysia"`, ...)
#' @param year_min Integer earliest year to include (inclusive)
#' @param year_max Integer latest year to include (inclusive)
#' @return Sorted character vector of absolute PDF paths
#' @export
discover_country_pdfs <- function(country, year_min, year_max) {
  base <- here::here("data/manual", country)
  if (!dir.exists(base)) return(character(0))

  series_dirs <- list.dirs(base, recursive = FALSE, full.names = TRUE)
  series_dirs <- series_dirs[!grepl("/_", series_dirs)]
  if (length(series_dirs) == 0L) return(character(0))

  paths <- unlist(lapply(series_dirs, list.files,
                         pattern = "\\.pdf$",
                         full.names = TRUE,
                         recursive = FALSE))
  if (length(paths) == 0L) return(character(0))

  parsed <- purrr::map(paths, parse_pdf_path) |> dplyr::bind_rows()

  unparseable <- is.na(parsed$base_year)
  if (any(unparseable)) {
    warning("Skipping unparseable PDF filenames: ",
            paste(parsed$filename[unparseable], collapse = ", "),
            call. = FALSE)
  }

  in_window <- !unparseable &
               parsed$base_year >= year_min &
               parsed$base_year <= year_max

  sort(parsed$abs_path[in_window])
}
