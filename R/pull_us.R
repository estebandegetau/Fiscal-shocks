
get_erp_pdf_urls <- function(start_year = 1946,
                             end_year = year(today())
                         ) {
    years <- seq.int(start_year, end_year)

    urls <- sprintf(
        "https://www.govinfo.gov/content/pkg/ERP-%d/pdf/ERP-%d.pdf",
        years, years
    )

    out <- tibble(
        year       = years,
        package_id = paste0("ERP-", years),
        pdf_url    = urls,
        country = "US",
        source = "govinfo.gov",
        body = "Economic Report of the President"
    )


    return(out)

}

get_erp_early_pdf_urls <- function(start_year = 1946,
                             end_year = 1995
                         ) {
    years <- seq.int(start_year, end_year)

    urls <- sprintf(
        "https://fraser.stlouisfed.org/files/docs/publications/ERP/%d/ERP_%d.pdf",
        years, years
    )

    out <- tibble(
        year       = years,
        package_id = paste0("ERP-", years),
        pdf_url    = urls,
        country = "US",
        source = "fraser.stlouisfed.org",
        body = "Economic Report of the President"
    )

    return(out)

}

get_erp_earliest_pdf_urls <- function(start_year = 1946,
                             end_year = 1995
                         ) {
    # Note: First ERP was January 1947, not 1946
    # Use 1947 as actual start year regardless of parameter
    actual_start <- max(start_year, 1947)
    years <- seq.int(actual_start, end_year)

    # Fraser FRED uses inconsistent naming patterns:
    # 1947-1949: ERP_YYYY_Month.pdf (year first)
    # 1950-1952: ERP_Month_YYYY.pdf (month first)

    # Split into two groups
    years_1947_1949 <- years[years >= 1947 & years <= 1949]
    years_1950_1952 <- years[years >= 1950 & years <= 1952]

    # Pattern 1: Year first (1947-1949)
    urls_1947_1949 <- NULL
    if (length(years_1947_1949) > 0) {
        jan_1947_1949 <- sprintf(
            "https://fraser.stlouisfed.org/files/docs/publications/ERP/%d/ERP_%d_January.pdf",
            years_1947_1949, years_1947_1949
        )
        mid_1947_1949 <- sprintf(
            "https://fraser.stlouisfed.org/files/docs/publications/ERP/%d/ERP_%d_Midyear.pdf",
            years_1947_1949, years_1947_1949
        )
        urls_1947_1949 <- tibble(
            year       = rep(years_1947_1949, 2),
            package_id = paste0("ERP-", rep(years_1947_1949, 2), c(rep("-January", length(years_1947_1949)), rep("-Midyear", length(years_1947_1949)))),
            pdf_url    = c(jan_1947_1949, mid_1947_1949)
        )
    }

    # Pattern 2: Month first (1950-1952)
    urls_1950_1952 <- NULL
    if (length(years_1950_1952) > 0) {
        jan_1950_1952 <- sprintf(
            "https://fraser.stlouisfed.org/files/docs/publications/ERP/%d/ERP_January_%d.pdf",
            years_1950_1952, years_1950_1952
        )
        mid_1950_1952 <- sprintf(
            "https://fraser.stlouisfed.org/files/docs/publications/ERP/%d/ERP_Midyear_%d.pdf",
            years_1950_1952, years_1950_1952
        )
        urls_1950_1952 <- tibble(
            year       = rep(years_1950_1952, 2),
            package_id = paste0("ERP-", rep(years_1950_1952, 2), c(rep("-January", length(years_1950_1952)), rep("-Midyear", length(years_1950_1952)))),
            pdf_url    = c(jan_1950_1952, mid_1950_1952)
        )
    }

    # Combine both patterns
    out <- bind_rows(urls_1947_1949, urls_1950_1952) |>
        mutate(
            country = "US",
            source = "fraser.stlouisfed.org",
            body = "Economic Report of the President"
        )

    return(out)

}

get_annual_report_early_pdf_urls <- function(start_year = 1946,
                             end_year = 1980
                         ) {
    years <- seq.int(start_year, end_year)

    urls <- sprintf(
        "https://fraser.stlouisfed.org/files/docs/publications/treasar/AR_TREASURY_%d.pdf",
        years
    )

    out <- tibble(
        year       = years,
        package_id = paste0("AR_TREASURY-", years),
        pdf_url    = urls,
        country = "US",
        source = "fraser.stlouisfed.org",
        body = "Annual Report of the Treasury"
    )

    return(out)

}

get_annual_report_late_pdf_urls <- function(start_year = 1981,
                             end_year = lubridate::year(lubridate::today())
                         ) {
    years <- seq.int(start_year, end_year)

    urls <- sprintf(
        "https://home.treasury.gov/system/files/261/FSOC%dAnnualReport.pdf",
        years
    )

    out <- tibble(
        year       = years,
        package_id = paste0("AR_TREASURY-", years),
        pdf_url    = urls,
        country = "US",
        source = "home.treasury.gov",
        body = "Annual Report of the Treasury"
    )

    return(out)

}

get_budget_pdf_urls <- function(start_year = 1946,
                             end_year = lubridate::year(lubridate::today())
                         ) {
    years <- seq.int(start_year, end_year)

    urls <- sprintf(
        "https://fraser.stlouisfed.org/files/docs/publications/usbudget/BUDGET-%d-BUD.pdf",
        years
    )

    out <- tibble(
        year       = years,
        package_id = paste0("BUDGET-", years),
        pdf_url    = urls,
        country = "US",
        source = "fraser.stlouisfed.org",
        body = "Budget of the United States Government"
    )

    return(out)

}

get_budget_2000s_pdf_urls <- function(start_year = 2005,
                                      end_year = 2009) {

    years <- seq.int(start_year, end_year)
    sections <- 5:30

    urls <- tibble(
        year = years
    ) |>
        cross_join(
            tibble(
                section = sections
            )
        ) |>
        mutate(
            pdf_url = str_c(
                "https://fraser.stlouisfed.org/files/docs/publications/usbudget/",
                year,
                "/BUDGET-",
                year,
                "-BUD-",
                section,
                ".pdf"
            )
        )

    out <- urls |>
        mutate(
            package_id = paste0("BUDGET-", year),
            country = "US",
            source = "fraser.stlouisfed.org",
            body = "Budget of the United States Government"
        ) |>
        select(year, package_id, pdf_url, country, source, body)

    return(out)
}

get_budget_early_pdf_urls <- function(start_year = 1946,
                             end_year = lubridate::year(lubridate::today())
                         ) {
    years <- seq.int(start_year, end_year)

    urls <- sprintf(
        "https://fraser.stlouisfed.org/files/docs/publications/usbudget/bus_%d.pdf",
        years
    )

    out <- tibble(
        year       = years,
        package_id = paste0("BUDGET-", years),
        pdf_url    = urls,
        country = "US",
        source = "fraser.stlouisfed.org",
        body = "Budget of the United States Government"
    )

    return(out)

}

#' Get CBO Budget and Economic Outlook report URLs
#'
#' Returns a tribble of known PDF URLs for the annual CBO Budget and
#' Economic Outlook reports (1976-2022). URLs are curated manually
#' because CBO uses non-standard, publication-ID-based URL patterns
#' that changed multiple times over the decades.
#'
#' @param min_year Earliest year to include (default 1976, first CBO outlook)
#' @param max_year Latest year to include (default 2022)
#' @return A tibble with columns: year, package_id, pdf_url, country, source, body
get_cbo_outlook_urls <- function(min_year = 1976, max_year = 2022) {
  # CBO was established 1974; first Budget Outlook was January 1976.
  # URL patterns changed across eras:
  #   - 1976-1995: /sites/default/files/{congress}/reports/{filename}.pdf
  #   - 1996-2008: /sites/default/files/cbofiles/{path}/{filename}.pdf
  #   - 2009-2017: /sites/default/files/{congress}/reports/{filename}.pdf
  #   - 2018-2022: /system/files/{date}/{id}-Outlook-{year}.pdf
  # Each row is one annual outlook report (the January/February primary edition).
  # URLs curated from cbo.gov publication pages. Early years (1976-1984)

  # point to the best available equivalent since CBO did not publish a

  # single unified "outlook" report until 1985.
  cbo_urls <- tribble(
    ~year, ~pdf_url,
    # Early CBO era (1976-1980): separate budget projections + economic outlook
    1976, "https://www.cbo.gov/sites/default/files/94th-congress-1975-1976/reports/1976_03_15_options.pdf",
    1977, "https://www.cbo.gov/sites/default/files/94th-congress-1975-1976/reports/1976_12_fiscal.pdf",
    1978, "https://www.cbo.gov/sites/default/files/95th-congress-1977-1978/reports/1977_12_puppy.pdf",
    1979, "https://www.cbo.gov/sites/default/files/95th-congress-1977-1978/reports/78-cbo-001_0.pdf",
    1980, "https://www.cbo.gov/sites/default/files/96th-congress-1979-1980/reports/80doc03b.pdf",
    # Transitional period (1981-1984)
    1981, "https://www.cbo.gov/sites/default/files/96th-congress-1979-1980/reports/80doc06b.pdf",
    1982, "https://www.cbo.gov/sites/default/files/97th-congress-1981-1982/reports/doc03b-entire_1.pdf",
    1983, "https://www.cbo.gov/sites/default/files/98th-congress-1983-1984/reports/19830215forecast.pdf",
    1984, "https://www.cbo.gov/sites/default/files/98th-congress-1983-1984/reports/84doc04b.pdf",
    # Unified series: "Economic and Budget Outlook" (1985-2000)
    1985, "https://www.cbo.gov/sites/default/files/99th-congress-1985-1986/reports/85-cbo-001.pdf",
    1986, "https://www.cbo.gov/sites/default/files/99th-congress-1985-1986/reports/doc05b-entire_1.pdf",
    1987, "https://www.cbo.gov/sites/default/files/100th-congress-1987-1988/reports/doc01b-entire_0.pdf",
    1988, "https://www.cbo.gov/sites/default/files/100th-congress-1987-1988/reports/88-cbo-0110.pdf",
    1989, "https://www.cbo.gov/sites/default/files/101st-congress-1989-1990/reports/89-cbo-032.pdf",
    1990, "https://www.cbo.gov/sites/default/files/101st-congress-1989-1990/reports/90-cbo-006.pdf",
    1991, "https://www.cbo.gov/sites/default/files/102nd-congress-1991-1992/reports/91-cbo-002.pdf",
    1992, "https://www.cbo.gov/sites/default/files/102nd-congress-1991-1992/reports/1992_01_econoutlook.pdf",
    1993, "https://www.cbo.gov/sites/default/files/103rd-congress-1993-1994/reports/93doc03.pdf",
    1994, "https://www.cbo.gov/sites/default/files/103rd-congress-1993-1994/reports/doc06_0.pdf",
    1995, "https://www.cbo.gov/sites/default/files/cbofiles/ftpdocs/55xx/doc5506/doc07-entire.pdf",
    1996, "https://www.cbo.gov/sites/default/files/104th-congress-1995-1996/reports/entirereport_7.pdf",
    1997, "https://www.cbo.gov/sites/default/files/cbofiles/attachments/Eb01-97.pdf",
    1998, "https://www.cbo.gov/sites/default/files/105th-congress-1997-1998/reports/eb01-98.pdf",
    1999, "https://www.cbo.gov/sites/default/files/106th-congress-1999-2000/reports/eb0199.pdf",
    # "Budget and Economic Outlook" (2000+)
    2000, "https://www.cbo.gov/sites/default/files/106th-congress-1999-2000/reports/eb0100.pdf",
    2001, "https://www.cbo.gov/sites/default/files/107th-congress-2001-2002/reports/entire-report.pdf",
    2002, "https://www.cbo.gov/sites/default/files/107th-congress-2001-2002/reports/entirereport_4.pdf",
    2003, "https://www.cbo.gov/sites/default/files/108th-congress-2003-2004/reports/entirereport_witherrata.pdf",
    2004, "https://www.cbo.gov/sites/default/files/108th-congress-2003-2004/reports/01-26-budgetoutlook-entirereport.pdf",
    2005, "https://www.cbo.gov/sites/default/files/109th-congress-2005-2006/reports/01-25-budgetoutlook.pdf",
    2006, "https://www.cbo.gov/sites/default/files/109th-congress-2005-2006/reports/01-26-budgetoutlook.pdf",
    2007, "https://www.cbo.gov/sites/default/files/110th-congress-2007-2008/reports/01-24-budgetoutlook.pdf",
    2008, "https://www.cbo.gov/sites/default/files/cbofiles/ftpdocs/77xx/doc7731/01-24-budgetoutlook.pdf",
    2009, "https://www.cbo.gov/sites/default/files/111th-congress-2009-2010/reports/01-07-outlook.pdf",
    2010, "https://www.cbo.gov/sites/default/files/111th-congress-2009-2010/reports/01-26-outlook.pdf",
    2011, "https://www.cbo.gov/sites/default/files/112th-congress-2011-2012/reports/01-26fy2011outlook.pdf",
    2012, "https://www.cbo.gov/sites/default/files/cbofiles/attachments/01-31-2012_Outlook.pdf",
    2013, "https://www.cbo.gov/sites/default/files/cbofiles/attachments/43907-BudgetOutlook.pdf",
    2014, "https://www.cbo.gov/sites/default/files/cbofiles/attachments/45010-Outlook2014_Feb.pdf",
    2015, "https://www.cbo.gov/sites/default/files/114th-congress-2015-2016/reports/49892-Outlook2015.pdf",
    2016, "https://www.cbo.gov/sites/default/files/114th-congress-2015-2016/reports/51129-2016outlook.pdf",
    2017, "https://www.cbo.gov/sites/default/files/115th-congress-2017-2018/reports/52370-outlookonecolumn.pdf",
    2018, "https://www.cbo.gov/system/files/2019-04/53651-outlook-2.pdf",
    2019, "https://www.cbo.gov/system/files/2019-03/54918-Outlook-3.pdf",
    2020, "https://www.cbo.gov/system/files/2020-01/56020-CBO-Outlook.pdf",
    2021, "https://www.cbo.gov/system/files/2021-02/56970-Outlook.pdf",
    2022, "https://www.cbo.gov/system/files/2022-05/57950-Outlook.pdf"
  )

  cbo_urls |>
    mutate(
      package_id = paste0("CBO-", year),
      country = "US",
      source = "cbo.gov",
      body = "CBO Budget and Economic Outlook"
    ) |>
    filter(year >= min_year, year <= max_year) |>
    select(year, package_id, pdf_url, country, source, body)
}

#' Get Social Security Bulletin URLs
#'
#' Generates URLs for the Social Security Bulletin (SSB). The SSB was
#' published monthly (Vol 1-54, 1938-1991), then quarterly (1992+).
#'
#' Combined full-issue PDFs are only available from Vol 67 (2007) onward
#' at `https://www.ssa.gov/policy/docs/ssb/v{VOL}n{ISSUE}/ssb-v{VOL}n{ISSUE}.pdf`.
#' Earlier volumes only have individual article PDFs (not full-issue), so we
#' exclude them. This means SSB coverage starts at 2007, not 1945.
#'
#' Volume-to-year mapping:
#'
#' - Vols 1-63 (1938-2000): `year = vol + 1937` (annual volumes)
#' - Vols 64-66 (2001-2006): each spans 2 years (biennial volumes)
#' - Vols 67+ (2007+): `year = vol + 1940` (annual volumes again)
#'
#' @param min_year Earliest year (default 2007, first with combined PDFs)
#' @param max_year Latest year (default 2022)
#' @return A tibble with columns: year, package_id, pdf_url, country, source, body
get_ssb_urls <- function(min_year = 2007, max_year = 2022) {
  # Only generate URLs for Vol 67+ (2007+) where combined PDFs exist.
  # SSB publishes quarterly (4 issues/year) in this era.
  # Volume mapping: vol = year - 1940 for 2007+
  years <- seq.int(
    max(min_year, 2007),
    min(max_year, 2022)
  )

  tibble(year = years) |>
    cross_join(tibble(issue = 1:4)) |>
    mutate(
      volume = year - 1940L,
      pdf_url = sprintf(
        "https://www.ssa.gov/policy/docs/ssb/v%dn%d/ssb-v%dn%d.pdf",
        volume, issue, volume, issue
      ),
      package_id = sprintf("SSB-%d-Q%d", year, issue),
      country = "US",
      source = "ssa.gov",
      body = "Social Security Bulletin"
    ) |>
    select(year, package_id, pdf_url, country, source, body)
}

#' Get all US source document URLs
#'
#' Consolidates all US fiscal policy document URLs into a single tibble.
#' This is the single entry point for the targets pipeline (RR1: Source
#' Compilation). Calls all existing helper functions and includes inline
#' tribbles for non-standard URL patterns.
#'
#' @param min_year Earliest year (default 1946)
#' @param max_year Latest year (default 2022)
#' @return A tibble with columns: year, package_id, pdf_url, country, source, body
get_us_urls <- function(min_year = 1946, max_year = 2022) {
  # --- Economic Report of the President ---
  erp_govinfo <- get_erp_pdf_urls(
    start_year = 1996, end_year = max_year
  )
  erp_earliest <- get_erp_earliest_pdf_urls(
    start_year = min_year, end_year = 1952
  )
  erp_early <- get_erp_early_pdf_urls(
    start_year = 1953, end_year = 1986
  )
  # Non-standard Fraser filenames for 1987-1988
  erp_additional <- tribble(
    ~year, ~pdf_url,
    1987, "https://fraser.stlouisfed.org/files/docs/publications/ERP/1987/ER_1987.pdf",
    1988, "https://fraser.stlouisfed.org/files/docs/publications/ERP/1988/ER_1988.pdf"
  ) |>
    mutate(
      package_id = paste0("ERP-", year),
      country = "US",
      source = "fraser.stlouisfed.org",
      body = "Economic Report of the President"
    )

  # --- Annual Report of the Treasury ---
  treasury_early <- get_annual_report_early_pdf_urls(
    start_year = min_year, end_year = 1980
  )
  treasury_late <- get_annual_report_late_pdf_urls(
    start_year = 2018, end_year = max_year
  )
  # Non-standard Treasury URLs for 2011-2017 (FSOC bridge era)
  treasury_2010s <- tribble(
    ~year, ~pdf_url,
    2011, "https://home.treasury.gov/system/files/261/FSOCAR2011.pdf",
    2012, "https://home.treasury.gov/system/files/261/2012-Annual-Report.pdf",
    2013, "https://home.treasury.gov/system/files/261/FSOC-2013-Annual-Report.pdf",
    2014, "https://home.treasury.gov/system/files/261/FSOC-2014-Annual-Report.pdf",
    2015, "https://home.treasury.gov/system/files/261/2015-FSOC-Annual-Report.pdf",
    2016, "https://home.treasury.gov/system/files/261/FSOC2016AnnualReport.pdf",
    2017, "https://home.treasury.gov/system/files/261/FSOC_2017_Annual_Report.pdf"
  ) |>
    mutate(
      package_id = paste0("AR_TREASURY-", year),
      country = "US",
      source = "home.treasury.gov",
      body = "Annual Report of the Treasury"
    )

  # --- Budget of the United States Government ---
  budget_main <- get_budget_pdf_urls(
    start_year = 1996, end_year = max_year
  )
  budget_2000s <- get_budget_2000s_pdf_urls(
    start_year = 2006, end_year = 2009
  )
  budget_early <- get_budget_early_pdf_urls(
    start_year = min_year, end_year = 1995
  )
  # Non-standard Budget URLs (supplements, sectioned PDFs)
  budget_additional <- tribble(
    ~year, ~pdf_url,
    2005, "https://fraser.stlouisfed.org/files/docs/publications/usbudget/2005/BUDGET-2005-BUD.pdf",
    1997, "https://fraser.stlouisfed.org/files/docs/publications/usbudget/BUDGET-1997-BUDSUPP.pdf",
    1994, "https://fraser.stlouisfed.org/files/docs/publications/usbudget/bus_1994_sec1.pdf",
    1993, "https://fraser.stlouisfed.org/files/docs/publications/bus_supp_1993/bus_supp_1993.pdf",
    1992, "https://fraser.stlouisfed.org/files/docs/publications/usbudget/bus_1992_sec2.pdf",
    1992, "https://fraser.stlouisfed.org/files/docs/publications/usbudget/bus_1992_sec3.pdf",
    1992, "https://fraser.stlouisfed.org/files/docs/publications/usbudget/bus_1992_sec4.pdf",
    1992, "https://fraser.stlouisfed.org/files/docs/publications/usbudget/bus_1992_sec5.pdf",
    1992, "https://fraser.stlouisfed.org/files/docs/publications/usbudget/bus_1992_sec6.pdf",
    1991, "https://fraser.stlouisfed.org/files/docs/publications/usbudget/bus_1991_sec1.pdf"
  ) |>
    mutate(
      package_id = paste0("BUDGET-", year),
      country = "US",
      source = "fraser.stlouisfed.org",
      body = "Budget of the United States Government"
    )

  # --- CBO and SSB deferred: both domains require CAPTCHA verification ---
  # cbo <- get_cbo_outlook_urls(min_year = 1976, max_year = max_year)
  # ssb <- get_ssb_urls(min_year = min_year, max_year = max_year)

  # --- Consolidate all sources ---
  bind_rows(
    erp_govinfo, erp_earliest, erp_early, erp_additional,
    treasury_early, treasury_late, treasury_2010s,
    budget_main, budget_2000s, budget_early, budget_additional
  ) |>
    filter(year >= min_year, year <= max_year) |>
    arrange(body, year)
}