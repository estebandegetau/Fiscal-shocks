#' Dispatch country-specific URL fetcher
#'
#' Returns a tibble of document URLs for one country, matching the schema
#' of `get_us_urls()`: year, package_id, pdf_url, country, source, body.
#' Adds `doc_language` from config if the country fetcher does not provide it.
#'
#' Called inside a `pattern = map(country_configs)` dynamic branch so that
#' adding a country = adding a `switch` case + a `pull_<country>.R` file.
#'
#' @param config One element of `build_country_configs()`
#' @return Tibble of URLs for the configured country
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

  urls
}
