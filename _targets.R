# Created by use_targets().
# Follow the comments below to fill in this target script.
# Then follow the manual to check and run the pipeline:
#   https://books.ropensci.org/targets/walkthrough.html#inspect-the-pipeline
rm(list = ls())
gc()

# Load AWS credentials from .env file
if (file.exists(".env")) {
  dotenv::load_dot_env()
}

# Load packages required to define the pipeline:
pacman::p_load(
  targets,
  tarchetypes,
  here,
  quarto,
  tidyverse,
  crew
)
# library(tarchetypes) # Load other packages as needed.

# Set target options:
tar_option_set(
  packages = c(
    "rvest",
    "pdftools",
    "jsonlite",
    "tibble",
    "dplyr",
    "lubridate",
    "purrr",
    "stringr",
    "readr",
    "tidytext",
    "tidyr",
    "quanteda"
  ), # Packages that your targets need for their tasks.
  # format = "qs", # Optionally set the default storage format. qs is fast.
  #
  # Pipelines that take a long time to run may benefit from
  # optional distributed computing. To use this capability
  # in tar_make(), supply a {crew} controller
  # as discussed at https://books.ropensci.org/targets/crew.html.
  # Choose a controller that suits your needs. For example, the following
  # sets a controller that scales up to a maximum of two workers
  # which run as local R processes. Each worker launches when there is work
  # to do and exits if 60 seconds pass with no tasks to run.
  #
  #   controller = crew::crew_controller_local(workers = 2, seconds_idle = 60)
  controller = crew_controller_local(workers = 2),
  error = "trim"
  #
  # Alternatively, if you want workers to run on a high-performance computing
  # cluster, select a controller from the {crew.cluster} package.
  # For the cloud, see plugin packages like {crew.aws.batch}.
  # The following example is a controller for Sun Grid Engine (SGE).
  #
  #   controller = crew.cluster::crew_controller_sge(
  #     # Number of workers that the pipeline can scale up to:
  #     workers = 10,
  #     # It is recommended to set an idle time so workers can shut themselves
  #     # down if they are not running tasks.
  #     seconds_idle = 120,
  #     # Many clusters install R as an environment module, and you can load it
  #     # with the script_lines argument. To select a specific verison of R,
  #     # you may need to include a version string, e.g. "module load R/4.3.2".
  #     # Check with your system administrator if you are unsure.
  #     script_lines = "module load R"
  #   )
  #
  # Set other options as needed.
)

# Run the R scripts in the R/ folder with your custom functions:
tar_source()
# tar_source("other_functions.R") # Source other scripts as needed.

# Replace the target list below with your own:
max_year <- lubridate::year(lubridate::today())
min_year <- 1946

# Extraction method: TRUE = local PyMuPDF+OCR, FALSE = AWS Lambda+Docling
use_local_extraction <- TRUE

list(
  tar_target(
    name = relevance_keys,
    command = c(
      "fiscal",
      "tax",
      "taxes",
      "spending",
      "deficit",
      "debt",
      "gdp",
      "unemployment",
      "stimulus",
      "expenditure",
      "revenue",
      "excise",
      "appropriation",
      "corporate",
      "income",
      "payroll",
      "tariff",
      "levy",
      "act",
      "vat"
    )
  ),
  tar_target(
    us_shocks_file,
    here::here("data/raw/us_shocks.csv"),
    format = "file"
  ),
  tar_target(
    # Labels for US economic shocks
    us_shocks,
    read_csv(us_shocks_file) |>
      clean_us_shocks()
  ),
  tar_target(
    us_labels_file,
    here::here("data/raw/us_labels.csv"),
    format = "file"
  ),
  tar_target(
    # Labels for US documents
    us_labels,
    read_csv(us_labels_file) |>
      clean_us_labels(us_shocks)
  ),
  tar_target(
    erp_urls,
    get_erp_pdf_urls(
      start_year = 1996,
      end_year   = max_year
    ),
    iteration = "vector"
  ),
  tar_target(
    earliest_erp_urls,
    get_erp_earliest_pdf_urls(
      start_year = min_year,
      end_year   = 1952
    ),
    iteration = "vector"
  ),
  tar_target(
    early_erp_urls,
    get_erp_early_pdf_urls(
      start_year = 1953,
      end_year   = 1995
    ),
    iteration = "vector"
  ),
  tar_target(
    additional_erp_urls,
    tribble(
      ~year, ~pdf_url,
      1987, "https://fraser.stlouisfed.org/files/docs/publications/ERP/1987/ER_1987.pdf",
      1988, "https://fraser.stlouisfed.org/files/docs/publications/ERP/1988/ER_1988.pdf"
    ) |>
      mutate(
        package_id = paste0("ERP-", year),
        country = "US",
        source = "fraser.stlouisfed.org",
        body = "Economic Report of the President"
      ),
    iteration = "vector"
  ),
  tar_target(
    annual_report_early_urls,
    get_annual_report_early_pdf_urls(
      start_year = min_year,
      end_year   = 1980
    ),
    iteration = "vector"
  ),
  tar_target(
    annual_report_late_urls,
    get_annual_report_late_pdf_urls(
      start_year = 2018,
      end_year   = max_year
    ),
    iteration = "vector"
  ),
  tar_target(
    annual_report_2010s_urls,
    tribble(
      ~year, ~pdf_url,
      2011, "https://home.treasury.gov/system/files/261/FSOCAR2011.pdf",
      2012, "https://home.treasury.gov/system/files/261/2012-Annual-Report.pdf",
      2013, "https://home.treasury.gov/system/files/261/FSOC-2013-Annual-Report.pdf",
      2014, "https://home.treasury.gov/system/files/261/FSOC-2014-Annual-Report.pdf",
      2015, "https://home.treasury.gov/system/files/261/2015-FSOC-Annual-Report.pdf",
      2016, "https://home.treasury.gov/system/files/261/2015-FSOC-Annual-Report.pdf",
      2017, "https://home.treasury.gov/system/files/261/FSOC_2017_Annual_Report.pdf"
    ) |>
      mutate(
        package_id = paste0("AR_TREASURY-", year),
        country = "US",
        source = "home.treasury.gov",
        body = "Annual Report of the Treasury"
      ),
    iteration = "vector"
  ),
  tar_target(
    budget_urls,
    get_budget_pdf_urls(
      start_year = 1996,
      end_year   = max_year
    ),
    iteration = "vector"
  ),
  tar_target(
    budget_2000s_urls,
    get_budget_2000s_pdf_urls(
      start_year = 2006,
      end_year   = 2009
    ),
    iteration = "vector"
  ),
  tar_target(
    budget_early_pdf_urls,
    get_budget_early_pdf_urls(
      start_year = min_year,
      end_year   = 1995
    ),
    iteration = "vector"
  ),
  tar_target(
    additional_budget_urls,
    tribble(
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
      ),
    iteration = "vector"
  ),
  tar_target(
    name = us_urls,
    command = dplyr::bind_rows(
      erp_urls,
      early_erp_urls,
      earliest_erp_urls,
      additional_erp_urls,
      annual_report_early_urls,
      annual_report_late_urls,
      annual_report_2010s_urls,
      budget_urls,
      budget_2000s_urls,
      budget_early_pdf_urls,
      additional_budget_urls
    ) |>
      arrange(body, year),
    iteration = "vector"
  ),
  tar_target(
    us_urls_vector,
    command = {
      us_urls |>
        pull(pdf_url)
    },
    iteration = "vector"
  ),
  tar_target(
    us_text,
    if (use_local_extraction) {
      pull_text_local(
        pdf_url = us_urls_vector,
        output_dir = here::here("data/extracted"),
        workers = 6,
        ocr_dpi = 200
      )
    } else {
      pull_text_lambda(
        pdf_url = us_urls_vector,
        bucket = Sys.getenv("AWS_S3_BUCKET", "fiscal-shocks-pdfs"),
        lambda_function = Sys.getenv("LAMBDA_FUNCTION_NAME"),
        poll_interval = 30,
        max_wait_time = 600,
        do_table_structure = TRUE
      )
    }
  ),
  tar_target(
    us_body,
    us_urls |>
      bind_cols(us_text)
  ),
  # tar_target(
  #   pages,
  #   make_pages(us_body, relevance_keys)
  # ),
  # tar_target(
  #   documents,
  #   make_documents(pages)
  # ),
  # tar_target(
  #   paragraphs,
  #   make_paragraphs(documents, relevance_keys)
  # ),
  # tar_target(
  #   relevant_paragraphs,
  #   make_relevant_paragraphs(paragraphs)
  # ),
  tar_target(
    # Sliding window chunks for LLM context fitting
    # 50 pages per chunk with 10-page overlap
    # Target ~40K tokens per chunk (Claude context = 200K)
    chunks,
    make_chunks(
      us_body,
      window_size = 50,   # pages per chunk
      overlap = 10,       # overlapping pages
      max_tokens = 40000  # ~40K tokens per chunk
    )
  ),
  tar_target(
    chunks_summary,
    summarize_chunks(chunks)
  )
)
