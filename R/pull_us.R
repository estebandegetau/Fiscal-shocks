
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