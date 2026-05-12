#' Fetch Malaysia government document URLs
#'
#' Returns a tibble of Malaysia document URLs spanning the five document
#' series mapped onto R&R's source taxonomy (motivation / identification /
#' quantification roles). Schema matches `get_us_urls()` plus three columns
#' for the manual-download pathway (`access_status`, `local_path`, `notes`).
#'
#' Document-series mapping (R&R role in parens):
#'
#' | Series | R&R role | Function |
#' |---|---|---|
#' | Economic Report / Tinjauan Ekonomi | M+I+Q | `get_malaysia_economic_report_urls()` |
#' | Budget Speech / Ucapan Bajet | M | `get_malaysia_budget_speech_urls()` |
#' | Bank Negara Malaysia Annual Report | M+Q | `get_malaysia_bnm_annual_report_urls()` |
#' | Five-Year Malaysia Plans + MTRs | M+I+Q (spending) | `get_malaysia_rmk_urls()` |
#' | Crisis booklets (NERP, COVID, etc.) | M+I+Q (event) | `get_malaysia_stimulus_urls()` |
#'
#' Access modes (manual-only for non-US per the filesystem-driven extraction
#' policy; `pdf_url` is acquisition-hint only — extraction is filesystem-driven
#' via `discover_country_pdfs()`):
#'   - `manual_ready` (file present at `local_path`): the PDF has been
#'     downloaded; the file-discovery target picks it up
#'   - `manual_pending` (file absent): the row appears in the verification
#'     dashboard with its landing URL and notes so a human can fetch it
#'
#' Window: 1980-2022 (Phase 2 pilot). Pre-1995 coverage is gappy —
#' most pre-1995 series rows are emitted as `manual` placeholders.
#'
#' @param min_year Integer earliest year to include (default 1980)
#' @param max_year Integer latest year to include (default 2022)
#' @return Tibble with columns: year, package_id, pdf_url, country, source,
#'   body, doc_language, access_status, local_path, notes
#' @export
get_malaysia_urls <- function(min_year = 1980L, max_year = 2022L) {
  econ_report  <- get_malaysia_economic_report_urls(min_year, max_year)
  budget       <- get_malaysia_budget_speech_urls(min_year, max_year)
  bnm_ar       <- get_malaysia_bnm_annual_report_urls(min_year, max_year)
  rmk          <- get_malaysia_rmk_urls(min_year, max_year)
  stimulus     <- get_malaysia_stimulus_urls(min_year, max_year)

  all_urls <- dplyr::bind_rows(econ_report, budget, bnm_ar, rmk, stimulus) |>
    dplyr::filter(year >= min_year, year <= max_year) |>
    dplyr::arrange(body, year, package_id)

  resolve_manual_paths(all_urls)
}

#' Resolve manual-download rows against the local PDF dump
#'
#' For rows with `access_status == "manual"`, set `manual_ready` if the
#' PDF exists at `here::here(local_path)`, otherwise `manual_pending`.
#' The `pdf_url` field is preserved as an acquisition hint for the
#' verify_malaysia_urls dashboard but is no longer read by the extractor —
#' filesystem discovery (`discover_country_pdfs()`) drives extraction.
#'
#' @param urls Tibble with `access_status` and `local_path` columns
#' @return Same tibble with `access_status` resolved to `manual_ready` or
#'   `manual_pending`
#' @keywords internal
resolve_manual_paths <- function(urls) {
  if (nrow(urls) == 0L) return(urls)

  rel_path <- urls$local_path
  has_local <- !is.na(rel_path) & nzchar(rel_path) &
               vapply(rel_path, function(p) {
                 !is.na(p) && nzchar(p) && file.exists(here::here(p))
               }, logical(1))

  urls$access_status <- dplyr::if_else(has_local, "manual_ready", "manual_pending")
  urls
}

# ============================================================================
# Series 1: MoF Economic Report / Tinjauan Ekonomi
# Role: M + I + Q (motivation, identification, quantification — primary)
# Coverage: 1995-2022 digital (MoF arkib + belanjawan portal); 1980-94 print
# ============================================================================

#' MoF Economic Report / Tinjauan Ekonomi URLs
#'
#' The flagship Malaysian fiscal-narrative document. Released annually
#' alongside the Budget. Bilingual (BM + EN editions). Two archives:
#'
#'   - `belanjawan.mof.gov.my/en/archive` for 2014-2022
#'   - `mof.gov.my/portal/arkib/ekonomi/ek_main.html` for older issues
#'
#' Both archives use bespoke per-year URL paths that don't follow a clean
#' pattern, so we emit the archive landing as the manual-pending URL and
#' rely on the human dashboard for click-and-drop. Pre-1995 issues are
#' physical-only (MOSTI library 1985-86 confirmed; earlier may exist).
#'
#' @keywords internal
get_malaysia_economic_report_urls <- function(min_year, max_year) {
  years <- seq(min_year, max_year)
  arkib_landing <- "https://www.mof.gov.my/portal/arkib/ekonomi/ek_main.html"
  belanjawan_landing <- "https://belanjawan.mof.gov.my/en/archive"

  tibble::tibble(
    year = as.integer(years),
    package_id = sprintf("MY_ECON_REPORT-%d", years),
    pdf_url = ifelse(years >= 2014, belanjawan_landing, arkib_landing),
    country = "malaysia",
    source = ifelse(years >= 2014,
                    "belanjawan.mof.gov.my",
                    "mof.gov.my"),
    body = "Economic Report / Tinjauan Ekonomi",
    doc_language = "en",
    access_status = "manual",
    local_path = sprintf("data/manual/malaysia/economic_report/%d.pdf",
                         years),
    notes = ifelse(
      years >= 1995,
      "Digital archive landing page; navigate to year and download.",
      "Pre-1995: physical archive only (MOSTI / Perpustakaan Negara)."
    )
  )
}

# ============================================================================
# Series 2: Budget Speech / Ucapan Bajet
# Role: M (motivation — primary, given Malaysia's parliamentary system
# concentrates fiscal motivation in this single annual address).
# Coverage: 2014-2022 digital direct; 1980-2013 via Hansard / older arkib
# ============================================================================

#' Budget Speech / Ucapan Bajet URLs
#'
#' Annual Finance Minister address to Dewan Rakyat. Bilingual; English
#' translations released alongside BM original. The 2014+ archive on
#' `belanjawan.mof.gov.my` hosts year-specific PDFs; pre-2014 speeches
#' are reprinted in Hansard for the day of budget reading.
#'
#' Years 2014-2022 use the verified MoF archive landing. Pre-2014
#' speeches are emitted as manual-pending with notes pointing to Hansard
#' as fallback retrieval path.
#'
#' @keywords internal
get_malaysia_budget_speech_urls <- function(min_year, max_year) {
  years <- seq(min_year, max_year)
  belanjawan_landing <- "https://belanjawan.mof.gov.my/en/archive"

  tibble::tibble(
    year = as.integer(years),
    package_id = sprintf("MY_BUDGET_SPEECH-%d", years),
    pdf_url = belanjawan_landing,
    country = "malaysia",
    source = "belanjawan.mof.gov.my",
    body = "Budget Speech / Ucapan Bajet",
    doc_language = "en",
    access_status = "manual",
    local_path = sprintf("data/manual/malaysia/budget_speech/%d.pdf",
                         years),
    notes = ifelse(
      years >= 2014,
      "Verified on belanjawan.mof.gov.my/en/archive; click year link.",
      paste("Pre-2014 speech: try parlimen.gov.my Hansard for the day of",
            "budget reading; or treasury.gov.my legacy arkib.")
    )
  )
}

# ============================================================================
# Series 3: Bank Negara Malaysia Annual Report
# Role: M + Q. "Unexpected high-value" source per source-mapping research:
# every BNM AR has a dedicated public-finance chapter discussing fiscal
# actions and rationales. Independent voice (central bank), useful as a
# cross-check against MoF/Treasury narrative.
# Coverage: 1997-2022 digital on bnm.gov.my; 1980-96 print only
# ============================================================================

#' Bank Negara Malaysia Annual Report URLs
#'
#' The BNM landing page (`bnm.gov.my/bnm-annual-report`) lists every AR.
#' Year-specific URLs follow the pattern `bnm.gov.my/-/bnm-annual-report-<year>`
#' which is an HTML page containing the PDF download. Programmatic access
#' returns 403 (anti-bot); browser access works. We emit each year as
#' manual with the year-specific landing URL.
#'
#' @keywords internal
get_malaysia_bnm_annual_report_urls <- function(min_year, max_year) {
  years <- seq(min_year, max_year)

  tibble::tibble(
    year = as.integer(years),
    package_id = sprintf("MY_BNM_AR-%d", years),
    pdf_url = sprintf("https://www.bnm.gov.my/-/bnm-annual-report-%d",
                      years),
    country = "malaysia",
    source = "bnm.gov.my",
    body = "Bank Negara Malaysia Annual Report",
    doc_language = "en",
    access_status = "manual",
    local_path = sprintf("data/manual/malaysia/bnm_annual_report/%d.pdf",
                         years),
    notes = ifelse(
      years >= 1997,
      paste("Year-specific landing page; PDF download on the page.",
            "Programmatic fetch blocked (403); use browser."),
      "Pre-1997: print-only (Yale eliScholar may mirror selected years)."
    )
  )
}

# ============================================================================
# Series 4: Five-Year Malaysia Plans + Mid-Term Reviews
# Role: M + I + Q on the spending side. Each plan sets development-
# expenditure envelopes; MTRs explicitly justify mid-cycle revisions and
# carry high motivation density. Full 1980-2022 coverage (RMK-3 onward).
# ============================================================================

#' Five-Year Malaysia Plan + MTR URLs
#'
#' Hardcoded list of plan and MTR documents falling in the pilot window.
#' Only RMK-12 has a verified direct PDF (rmke12.epu.gov.my).
#' Earlier plans and most MTRs are emitted as manual rows with EPU
#' landing URLs. Plans hand off to year-of-tabling for the manifest.
#'
#' @keywords internal
get_malaysia_rmk_urls <- function(min_year, max_year) {
  rmk_table <- tibble::tribble(
    ~plan,        ~year, ~doc_type, ~landing_url,
                                                                ~direct_pdf,
                                                                              ~local_filename,
    "RMK-1",      1966L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/first-malaysia-plan-1966-1970",
      NA_character_,                                              "rmk01_plan_1966.pdf",
    "RMK-2",      1971L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/second-malaysia-plan-1971-1975",
      NA_character_,                                              "rmk02_plan_1971.pdf",
    "RMK-2",      1973L, "mtr",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/mid-term-review-second-malaysia-plan-1971-1975",
      NA_character_,                                              "rmk02_mtr_1973.pdf",
    "RMK-3",      1976L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/third-malaysia-plan-1976-1980",
      NA_character_,                                              "rmk03_plan_1976.pdf",
    "RMK-4",      1981L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/fourth-malaysia-plan-1981-1985",
      NA_character_,                                              "rmk04_plan_1981.pdf",
    "RMK-4",      1984L, "mtr",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/mid-term-review-fourth-malaysia-plan-1981-1985",
      NA_character_,                                              "rmk04_mtr_1984.pdf",
    "RMK-5",      1986L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/fifth-malaysia-plan-1986-1990",
      NA_character_,                                              "rmk05_plan_1986.pdf",
    "RMK-5",      1989L, "mtr",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/mid-term-review-fifth-malaysia-plan-1986-1990",
      NA_character_,                                              "rmk05_mtr_1989.pdf",
    "RMK-6",      1991L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/sixth-malaysia-plan-1990-1995",
      NA_character_,                                              "rmk06_plan_1991.pdf",
    "RMK-6",      1993L, "mtr",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/mid-term-review-sixth-malaysia-plan-1990-1995",
      NA_character_,                                              "rmk06_mtr_1993.pdf",
    "RMK-7",      1996L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/seventh-malaysia-plan-1996-2000",
      NA_character_,                                              "rmk07_plan_1996.pdf",
    "RMK-7",      1999L, "mtr",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/mid-term-review-seventh-malaysia-plan-1996-2000",
      NA_character_,                                              "rmk07_mtr_1999.pdf",
    "RMK-8",      2001L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/eight-malaysia-plan-2001-2005",
      NA_character_,                                              "rmk08_plan_2001.pdf",
    "RMK-8",      2003L, "mtr",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/mid-term-review-eighth-malaysia-plan-2001-2005",
      NA_character_,                                              "rmk08_mtr_2003.pdf",
    "RMK-9",      2006L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/ninth-malaysia-plan-2006-2010",
      NA_character_,                                              "rmk09_plan_2006.pdf",
    "RMK-9",      2008L, "mtr",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/mid-term-review-ninth-malaysia-plan-2006-2010",
      NA_character_,                                              "rmk09_mtr_2008.pdf",
    "RMK-10",     2011L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/tenth-malaysia-plan-2011-2015",
      NA_character_,                                              "rmk10_plan_2011.pdf",
    "RMK-10",     2013L, "mtr",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/mid-term-review-tenth-malaysia-plan-2011-2015",
      NA_character_,                                              "rmk10_mtr_2013.pdf",
    "RMK-11",     2016L, "plan",
      "https://www.epu.gov.my/en/economic-developments/development-plans/rmk/eleventh-malaysia-plan-2016-2020",
      NA_character_,                                              "rmk11_plan_2016.pdf",
    "RMK-11",     2018L, "mtr",
      "https://www.ekonomi.gov.my/en/economic-developments/development-plans/rmk/mid-term-review-eleventh-malaysia-plan-2016-2020",
      "https://www.talentcorp.com.my/clients/TalentCorp_2016_7A6571AE-D9D0-4175-B35D-99EC514F2D24/contentms/img/publication/Mid-Term%20Review%20of%2011th%20Malaysia%20Plan.pdf",
                                                                  "rmk11_mtr_2018.pdf",
    "RMK-12",     2021L, "plan",
      "https://rmke12.epu.gov.my/en",
      "https://rmke12.epu.gov.my/file/download/2021092722_twelfth_malaysia_plan.pdf",
                                                                  "rmk12_plan_2021.pdf",
    "RMK-12",     2023L, "mtr",
      "https://rmke12.epu.gov.my/en",
      NA_character_,                                              "rmk12_mtr_2023.pdf",
    "RMK-13",     2026L, "plan",
      "https://rmke13.ekonomi.gov.my/",
      NA_character_,                                              "rmk13_plan_2026.pdf"
  )

  rmk_table |>
    dplyr::mutate(
      package_id = sprintf("MY_%s_%s-%d",
                           toupper(plan),
                           toupper(doc_type),
                           year),
      pdf_url = dplyr::coalesce(direct_pdf, landing_url),
      country = "malaysia",
      source = ifelse(grepl("ekonomi.gov.my", pdf_url),
                      "ekonomi.gov.my",
                      ifelse(grepl("epu.gov.my", pdf_url),
                             "epu.gov.my",
                             "talentcorp.com.my")),
      body = "Five-Year Malaysia Plan / Mid-Term Review",
      doc_language = "en",
      access_status = "manual",
      local_path = sprintf("data/manual/malaysia/rmk/%s", local_filename),
      notes = dplyr::case_when(
        !is.na(direct_pdf) ~ "Direct PDF verified.",
        doc_type == "plan" ~ paste("EPU plan landing page; navigate to",
                                   "downloads section."),
        doc_type == "mtr"  ~ paste("EPU MTR landing page; navigate to",
                                   "downloads section.")
      )
    ) |>
    dplyr::select(year, package_id, pdf_url, country, source, body,
                  doc_language, access_status, local_path, notes)
}

# ============================================================================
# Series 5: Standalone crisis booklets (NERP, COVID stimulus, mini-budgets)
# Role: M + I + Q event-specific. High-value because each booklet is a
# discrete fiscal-action document with explicit motivation language.
# ============================================================================

#' Standalone fiscal-event booklet URLs
#'
#' Verified direct PDFs for COVID-era stimulus packages, plus manual
#' placeholders for NERP 1998 (Asian Financial Crisis) and the 2009
#' mini-budget (GFC response). NERP digital availability is unclear;
#' research agents found references via IMF Occasional Paper No. 207
#' and Yale YPFS but not a confirmed direct PDF on a .gov.my host.
#'
#' @keywords internal
get_malaysia_stimulus_urls <- function(min_year, max_year) {
  stim_table <- tibble::tribble(
    ~year, ~package_id,           ~direct_pdf,
                                                                              ~landing_url,
                                                                                                          ~source,                       ~local_filename,
                                                                                                                                                              ~note,
    1998L, "MY_NERP-1998",        NA_character_,
                                                                              "https://elischolar.library.yale.edu/cgi/viewcontent.cgi?article=15434&context=ypfs-documents",
                                                                                                          "elischolar.library.yale.edu", "nerp_1998.pdf",
                                                                                                                                                              "NERP via Yale YPFS mirror; no .gov.my host found.",
    2009L, "MY_MINI_BUDGET-2009", NA_character_,
                                                                              "https://www.treasury.gov.my/index.php/en/archives",
                                                                                                          "treasury.gov.my",             "mini_budget_2009.pdf",
                                                                                                                                                              "GFC response (Mar 2009); search Treasury arkib.",
    2020L, "MY_PRIHATIN-2020",
                                  "https://www.pmo.gov.my/wp-content/uploads/2020/04/Booklet-PRIHATIN-EN.pdf",
                                                                              "https://www.pmo.gov.my/",
                                                                                                          "pmo.gov.my",                  "prihatin_2020.pdf",
                                                                                                                                                              "Direct PDF verified.",
    2020L, "MY_PENJANA-2020",
                                  "https://penjana.treasury.gov.my/pdf/PENJANA-Booklet-En.pdf",
                                                                              "https://penjana.treasury.gov.my/index-en.html",
                                                                                                          "penjana.treasury.gov.my",     "penjana_2020.pdf",
                                                                                                                                                              "Direct PDF verified.",
    2021L, "MY_PERMAI-2021",      NA_character_,
                                                                              "https://www.pmo.gov.my/",
                                                                                                          "pmo.gov.my",                  "permai_2021.pdf",
                                                                                                                                                              "Jan 2021 RM15bn package; navigate from PMO landing.",
    2021L, "MY_PEMERKASA-2021",   NA_character_,
                                                                              "https://www.pmo.gov.my/",
                                                                                                          "pmo.gov.my",                  "pemerkasa_2021.pdf",
                                                                                                                                                              "Mar 2021 RM20bn package; navigate from PMO landing.",
    2021L, "MY_PEMULIH-2021",     NA_character_,
                                                                              "https://www.pmo.gov.my/",
                                                                                                          "pmo.gov.my",                  "pemulih_2021.pdf",
                                                                                                                                                              "Jun 2021 RM150bn package; navigate from PMO landing.",
    2021L, "MY_NRP-2021",         NA_character_,
                                                                              "https://www.pmo.gov.my/",
                                                                                                          "pmo.gov.my",                  "nrp_2021.pdf",
                                                                                                                                                              "National Recovery Plan; Muhyiddin's COVID roadmap announced 15 Jun 2021."
  )

  stim_table |>
    dplyr::mutate(
      pdf_url = dplyr::coalesce(direct_pdf, landing_url),
      country = "malaysia",
      body = "Crisis booklet / fiscal stimulus package",
      doc_language = "en",
      access_status = "manual",
      local_path = sprintf("data/manual/malaysia/stimulus/%s",
                           local_filename),
      notes = note
    ) |>
    dplyr::select(year, package_id, pdf_url, country, source, body,
                  doc_language, access_status, local_path, notes)
}
