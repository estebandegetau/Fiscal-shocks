#' Fetch Malaysia government document URLs (stub)
#'
#' Returns an **empty tibble** matching the schema of `get_us_urls()`
#' (year, package_id, pdf_url, country, source, body) plus `doc_language`.
#' The deployment pipeline runs end-to-end with zero documents until URLs
#' are populated; downstream targets gracefully handle empty inputs.
#'
#' Source identification is doc-research work, not coding. Populate by
#' adding per-source helpers (e.g., `get_malaysia_budget_urls()`) and
#' `dplyr::bind_rows()`-ing them in this function. Anticipated workflow
#' (see notes for a future URL-discovery skill) is to map R&R's source
#' taxonomy onto Malaysia's information landscape and HEAD-verify each
#' URL before committing it.
#'
#' R&R source taxonomy mapped onto Malaysia (provisional analogs):
#'
#' | R&R source | Malaysia analog | Status |
#' |---|---|---|
#' | Economic Report of the President | Bank Negara Malaysia Annual Report | TODO |
#' | Treasury Annual Report | Ministry of Finance Economic Outlook | TODO |
#' | Budget of the United States | Federal Budget speech + Estimates | TODO |
#' | House/Senate Committee Reports | Parliamentary Hansard (Dewan Rakyat) | TODO |
#' | CBO Reports | (no direct analog; consider IMF Article IV) | TODO |
#' | Social Security Bulletin | EPF / SOCSO reports | DEFERRED |
#'
#' @param min_year Integer earliest year to include (passed by dispatcher)
#' @param max_year Integer latest year to include (passed by dispatcher)
#' @return Tibble with columns matching `get_us_urls()` plus `doc_language`.
#'   Initially empty; pipeline downstream is empty-input safe.
#' @export
get_malaysia_urls <- function(min_year = 1980L, max_year = 2022L) {
  tibble::tibble(
    year         = integer(),
    package_id   = character(),
    pdf_url      = character(),
    country      = character(),
    source       = character(),
    body         = character(),
    doc_language = character()
  )
}
