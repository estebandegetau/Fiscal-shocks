
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
    years <- seq.int(start_year, end_year)

    url_1 <- sprintf(
        "https://fraser.stlouisfed.org/files/docs/publications/ERP/%d/ERP_January_%d.pdf",
      
        years, years
    )
    url_2 <- sprintf(
        "https://fraser.stlouisfed.org/files/docs/publications/ERP/%d/ERP_Midyear_%d.pdf",
        years, years
    )
    url_3 <- sprintf(
        "https://fraser.stlouisfed.org/files/docs/publications/ERP/%d/ERP_%d_January.pdf",
        years, years
    )
    url_4 <- sprintf(
        "https://fraser.stlouisfed.org/files/docs/publications/ERP/%d/ERP_%d_Midyear.pdf",
        years, years
    )

    out <- tibble(
        year       = rep(years, 4),
        package_id = paste0("ERP-", rep(years, 4)),
        pdf_url    = c(url_1, url_2, url_3, url_4),
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