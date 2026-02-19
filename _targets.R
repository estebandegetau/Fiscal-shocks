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
  garbage_collection = T,
  error = "abridge"
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
max_year <- 2022
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

  # RR1: Source Compilation — all US document URLs consolidated in get_us_urls()
  # Includes ERP, Treasury, Budget. CBO and SSB deferred (CAPTCHA-protected).
  tar_target(
    us_urls,
    get_us_urls(min_year = min_year, max_year = max_year),
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
  tar_quarto(
    verify_us_body,
    "notebooks/verify_body.qmd"
  ),

  # Phase 0 Training Data Preparation
  tar_target(
    aligned_data,
    align_labels_shocks(us_labels, us_shocks, threshold = 0.85),
    packages = c("tidyverse", "stringdist")
  ),
  tar_quarto(
    testing_data_overview,
    "notebooks/data_overview.qmd"
  ),

  # =============================================================================
  # Chunks: Sliding window chunking for LLM context windows
  # =============================================================================

  tar_target(
    chunks,
    make_chunks(us_body, window_size = 50, overlap = 10, max_tokens = 160000),
    packages = c("tidyverse", "purrr")
  ),

  # =============================================================================
  # C1 Codebook Pipeline: Measure Identification (H&K S0-S3)
  # =============================================================================

  # C1 chunk tier identification (Tier 1/2/Negative)
  tar_target(
    c1_chunk_data,
    prepare_c1_chunk_data(aligned_data, chunks, relevance_keys,
                          max_doc_year = 2007L),
    packages = c("tidyverse", "stringr")
  ),

  # Pre-computed diagnostics for verify_chunk_tiers notebook (avoids OOM)
  tar_target(
    c1_tier_diagnostics,
    prepare_chunk_tier_diagnostics(aligned_data, chunks, c1_chunk_data,
                                   max_doc_year = 2007L),
    packages = c("tidyverse", "stringr")
  ),

  # Review C1 identification of known fiscal shocks
  tar_quarto(
    verify_chunk_tiers,
    "notebooks/verify_chunk_tiers.qmd",
    garbage_collection = TRUE,
    deployment = "main"
  ),

  # S0: Load and validate codebook
  tar_target(
    c1_codebook,
    load_validate_codebook(here::here("prompts", "c1_measure_id.yml")),
    packages = c("yaml", "here")
  ),

  # S1: Behavioral tests (Tests I-IV) on chunk-length inputs
  tar_target(
    c1_s1_results,
    run_behavioral_tests_s1(
      c1_codebook,
      aligned_data,
      c1_chunk_data,
      model = "claude-haiku-3-5"
    ),
    packages = c("tidyverse", "httr2", "jsonlite", "progress"),
    deployment = "main"
  ),

  # S2: LOOCV evaluation on chunks with tier-stratified metrics
  tar_target(
    c1_s2_results,
    run_loocv(
      c1_codebook,
      aligned_data,
      c1_chunk_data,
      codebook_type = "C1",
      model = "claude-haiku-3-5",
      n_few_shot = 5,
      seed = 20251206
    ),
    packages = c("tidyverse", "httr2", "jsonlite", "progress"),
    deployment = "main"
  ),
  tar_target(
    c1_s2_eval,
    evaluate_loocv(c1_s2_results, codebook_type = "C1", n_bootstrap = 1000),
    packages = "tidyverse"
  ),

  # S3: Error analysis (Tests V-VII + ablation)
  tar_target(
    c1_s3_results,
    run_error_analysis(
      c1_codebook,
      c1_s2_results,
      aligned_data,
      c1_chunk_data,
      model = "claude-haiku-3-5"
    ),
    packages = c("tidyverse", "httr2", "jsonlite", "progress"),
    deployment = "main"
  ),
  tar_quarto(
    verify_c1,
    "notebooks/c1_measure_id.qmd"
  )

  # =============================================================================
  # LEGACY: Superseded by C1-C4 codebook pipeline
  # Commented out for reference — do not re-enable without updating to new framework
  # =============================================================================
  #
  # # Chunks (Phase 1 only — not needed for Phase 0 LOOCV)
  # tar_target(
  #   chunks,
  #   make_chunks(us_body, window_size = 50, overlap = 10, max_tokens = 160000)
  # ),
  # tar_target(chunks_summary, summarize_chunks(chunks)),
  #
  # # Training data splits (replaced by LOOCV)
  # tar_target(aligned_data_split, create_train_val_test_splits(aligned_data, ...)),
  # tar_target(negative_examples, generate_negative_examples(us_body, n = 200, ...)),
  # tar_target(training_data_a, prepare_model_a_data(aligned_data_split, negative_examples)),
  # tar_target(training_data_b, prepare_model_b_data(aligned_data_split)),
  # tar_target(training_data_c, prepare_model_c_data(aligned_data_split)),
  #
  # # Model A (replaced by C1)
  # tar_target(model_a_examples, ...),
  # tar_target(model_a_examples_file, ...),
  # tar_target(model_a_predictions_val, ..., deployment = "main"),
  # tar_target(model_a_eval_val, ...),
  # tar_target(model_a_predictions_test, ..., deployment = "main"),
  # tar_target(model_a_eval_test, ...),
  #
  # # Model B (replaced by C2)
  # tar_target(model_b_examples, ...),
  # tar_target(model_b_examples_file, ...),
  # tar_target(model_b_predictions_val, ..., deployment = "main"),
  # tar_target(model_b_eval_val, ...),
  # tar_target(model_b_predictions_test, ..., deployment = "main"),
  # tar_target(model_b_eval_test, ...),
  # tar_target(model_b_loocv_results, ..., deployment = "main"),
  # tar_target(model_b_loocv_eval, ...),
  #
  # # Model C (replaced by C3/C4)
  # tar_target(model_c_predictions_val, ..., deployment = "main"),
  # tar_target(model_c_eval_val, ...),
  # tar_target(model_c_predictions_test, ..., deployment = "main"),
  # tar_target(model_c_eval_test, ...),
  #
  # # Production Pipeline (Phase 1 only)
  # tar_target(chunks_production, ...),
  # tar_target(model_a_extract_examples, ...),
  # tar_target(model_a_extract_examples_file, ...),
  # tar_target(extracted_passages, ..., deployment = "main"),
  # tar_target(grouped_acts, ...),
  # tar_target(extraction_eval, ...),
  # tar_target(model_b_predictions_production, ..., deployment = "main"),
  # tar_target(model_b_robustness_eval, ..., deployment = "main"),
  # tar_target(model_b_robustness_comparison, ...)
)
