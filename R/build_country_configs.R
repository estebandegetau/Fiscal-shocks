#' Build country deployment configurations
#'
#' One named element per country. Each element keys a dynamic branch
#' in the deployment pipeline (`country_urls`, `country_text`, ...).
#' Adding a country = appending one entry here. Existing countries'
#' branches stay cached because dynamic branches hash independently.
#'
#' Initial registry: Malaysia only (per Phase 2 strategy plan).
#' Add `us = list(...)` to enable Phase 1 (US Full Production).
#'
#' Fields per element:
#'   - country: character ISO-style identifier (lowercase)
#'   - country_iso: character ISO 3166-1 alpha-2 code (e.g. "MY", "US")
#'     substituted into C1 v0.7.0's `{country_iso}` token at prompt-
#'     construction time. Per-measure `country` enum becomes
#'     `[<country_iso>, OTHER]` at runtime.
#'   - pilot_year_min, pilot_year_max: integer pilot window (hardcoded
#'     filter applied inside the country-specific URL fetcher)
#'   - primary_language: character (ISO 639-1) used as the default
#'     `doc_language` if the URL fetcher does not override it
#'   - notes: free-form context for downstream review and skill prompts
#'
#' @return Named list, one element per country
#' @export
build_country_configs <- function() {
  list(
    malaysia = list(
      country = "malaysia",
      country_iso = "MY",
      pilot_year_min = 1980L,
      pilot_year_max = 2025L,
      primary_language = "en",
      notes = paste(
        "Pilot per docs/phase_1/malaysia_strategy.md.",
        "Political stable window 1980-2022.",
        "English documents preferred; Hansard is bilingual (English + Bahasa Malaysia)."
      )
    )
  )
}
