#' Dispatch country-specific URL fetcher
#'
#' Returns a tibble of document URLs for one country, matching the schema
#' of `get_us_urls()`: year, package_id, pdf_url, country, source, body.
#' Adds `doc_language` from config if the country fetcher does not provide it.
#' Also defaults the manual-download columns (`access_status`, `local_path`,
#' `notes`) so country fetchers that emit auto-only URLs (e.g. `get_us_urls()`)
#' produce a uniform downstream schema.
#'
#' Called inside a `pattern = map(country_configs)` dynamic branch so that
#' adding a country = adding a `switch` case + a `pull_<country>.R` file.
#'
#' @param config One element of `build_country_configs()`
#' @return Tibble of URLs for the configured country with columns
#'   `year, package_id, pdf_url, country, source, body, doc_language,
#'   access_status, local_path, notes`.
#' @export
get_country_urls <- function(config) {
  urls <- switch(
    config$country,
    us       = get_us_urls(min_year = config$pilot_year_min,
                           max_year = config$pilot_year_max),
    malaysia = get_malaysia_urls(min_year = config$pilot_year_min,
                                 max_year = config$pilot_year_max),
    stop("Unknown country in config: ", config$country)
  )

  if (!"doc_language" %in% names(urls)) {
    urls$doc_language <- config$primary_language
  }
  if (!"access_status" %in% names(urls)) {
    urls$access_status <- "auto"
  }
  if (!"local_path" %in% names(urls)) {
    urls$local_path <- NA_character_
  }
  if (!"notes" %in% names(urls)) {
    urls$notes <- NA_character_
  }

  urls
}
