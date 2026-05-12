#' Parse a manual-corpus PDF path into manifest-join metadata
#'
#' Pure path parser. Maps `data/manual/<country>/<series>/<filename>.pdf`
#' to a one-row tibble whose `package_id_inferred` joins back to the
#' manifest emitted by `get_<country>_urls()`.
#'
#' Used by `discover_country_pdfs()` (year-window filtering) and
#' `assemble_country_body()` (manifest join + orphan surfacing).
#'
#' Per-series patterns (regex on `tools::file_path_sans_ext(basename(path))`):
#'
#'   - `budget_speech`    : `^(\d{4})$`           → `MY_BUDGET_SPEECH-<year>`
#'   - `economic_report`  : `^(\d{4})(_bm)?$`     → `MY_ECON_REPORT-<year>`
#'                                                  (suffix `-BM` for `_bm`)
#'   - `bnm_annual_report`: `^(\d{4})$`           → `MY_BNM_AR-<year>`
#'   - `rmk`              : `^rmk(\d{2})_(plan|mtr)_(\d{4})$`
#'                                                → `MY_RMK-<NN>_<TYPE>-<year>`
#'   - `stimulus`         : `^([a-z][a-z_]*?)_(\d{4})$`
#'                                                → `MY_<TOKEN>-<year>`
#'
#' @param path Absolute or here::here-relative PDF path
#' @return One-row tibble with columns:
#'   `abs_path, country, series_folder, filename, base_year, variant,
#'   doc_language, package_id_inferred`. Unparseable filenames produce
#'   `base_year = NA_integer_` and `package_id_inferred = NA_character_`.
#' @export
parse_pdf_path <- function(path) {
  abs_path <- normalizePath(path, mustWork = FALSE)
  filename <- basename(abs_path)
  series_folder <- basename(dirname(abs_path))
  country <- basename(dirname(dirname(abs_path)))
  stem <- tools::file_path_sans_ext(filename)

  out <- tibble::tibble(
    abs_path = abs_path,
    country = country,
    series_folder = series_folder,
    filename = filename,
    base_year = NA_integer_,
    variant = NA_character_,
    doc_language = "en",
    package_id_inferred = NA_character_
  )

  parsed <- switch(
    series_folder,
    budget_speech = parse_year_only(stem, "MY_BUDGET_SPEECH"),
    economic_report = parse_year_with_bm(stem, "MY_ECON_REPORT"),
    bnm_annual_report = parse_year_only(stem, "MY_BNM_AR"),
    rmk = parse_rmk(stem),
    stimulus = parse_stimulus(stem),
    NULL
  )

  if (is.null(parsed)) return(out)

  out$base_year <- parsed$base_year
  out$variant <- parsed$variant
  out$doc_language <- parsed$doc_language
  out$package_id_inferred <- parsed$package_id_inferred
  out
}

parse_year_only <- function(stem, prefix) {
  m <- stringr::str_match(stem, "^(\\d{4})$")
  if (is.na(m[, 1])) return(NULL)
  year <- as.integer(m[, 2])
  list(
    base_year = year,
    variant = NA_character_,
    doc_language = "en",
    package_id_inferred = sprintf("%s-%d", prefix, year)
  )
}

parse_year_with_bm <- function(stem, prefix) {
  m <- stringr::str_match(stem, "^(\\d{4})(_bm)?$")
  if (is.na(m[, 1])) return(NULL)
  year <- as.integer(m[, 2])
  is_bm <- !is.na(m[, 3])
  list(
    base_year = year,
    variant = if (is_bm) "bm" else NA_character_,
    doc_language = if (is_bm) "bm" else "en",
    package_id_inferred = if (is_bm)
      sprintf("%s-%d-BM", prefix, year)
    else
      sprintf("%s-%d", prefix, year)
  )
}

parse_rmk <- function(stem) {
  m <- stringr::str_match(stem, "^rmk(\\d{2})_(plan|mtr)_(\\d{4})$")
  if (is.na(m[, 1])) return(NULL)
  rmk_n <- as.integer(m[, 2])  # strip zero-padding to match manifest
  list(
    base_year = as.integer(m[, 4]),
    variant = NA_character_,
    doc_language = "en",
    package_id_inferred = sprintf(
      "MY_RMK-%d_%s-%s", rmk_n, toupper(m[, 3]), m[, 4]
    )
  )
}

parse_stimulus <- function(stem) {
  m <- stringr::str_match(stem, "^([a-z][a-z_]*?)_(\\d{4})$")
  if (is.na(m[, 1])) return(NULL)
  token <- toupper(m[, 2])
  list(
    base_year = as.integer(m[, 3]),
    variant = NA_character_,
    doc_language = "en",
    package_id_inferred = sprintf("MY_%s-%s", token, m[, 3])
  )
}
