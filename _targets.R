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
  ), 
  garbage_collection = T,
  error = "abridge"
 
)

# Run the R scripts in the R/ folder with your custom functions:
tar_source()
# tar_source("other_functions.R") # Source other scripts as needed.

# Replace the target list below with your own:
max_year <- 2022
min_year <- 1946

# LLM configuration is hardcoded per target (not shared globals) so that
# changing one codebook/stage's model never invalidates another's cache.
# C1 targets: Haiku (validated). C2 S1/S2: Qwen via OpenRouter (cheap iteration).

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
    pull_text_local(
      pdf_url = us_urls_vector,
      output_dir = here::here("data/extracted"),
      workers = 6,
      ocr_dpi = 200
    )
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
    align_labels_shocks(us_labels, us_shocks, threshold = 0.85,
                        exclude_acts = "Internal Revenue Code of 1954"),
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
    make_chunks(us_body, window_size = 10, overlap = 3, max_tokens = 40000,
                min_chars = 100L),
    packages = c("tidyverse", "purrr")
  ),

  # =============================================================================
  # C1 Codebook Pipeline: Measure Identification (H&K S0-S3)
  # =============================================================================

  # C1 chunk tier identification — two-target split for memory safety.
  # c1_chunk_tiers: squish in-place, match tiers, return IDs (no text).
  # c1_chunk_data: join text from chunks onto tier results.
  # With garbage_collection = TRUE, targets gc's between them so peak
  # memory never exceeds ~600 MB (vs ~1.1 GB in the single-target version).
  tar_target(
    c1_chunk_tiers,
    compute_c1_chunk_tiers(aligned_data, chunks, relevance_keys,
                           max_doc_year = 2007L),
    packages = c("tidyverse", "stringr")
  ),
  tar_target(
    c1_chunk_data,
    assemble_c1_chunk_data(c1_chunk_tiers, chunks,
                           max_doc_year = 2007L),
    packages = c("tidyverse")
  ),

  # Lightweight positive ID extract for diagnostics (avoids loading
  # c1_chunk_data's text columns into the diagnostics target)
  tar_target(
    c1_positive_ids,
    dplyr::bind_rows(
      c1_chunk_data$tier1 |> dplyr::select(doc_id, chunk_id),
      c1_chunk_data$tier2 |> dplyr::select(doc_id, chunk_id)
    ) |> dplyr::distinct(),
    packages = "dplyr"
  ),

  # Pre-computed diagnostics for verify_chunk_tiers notebook (avoids OOM)
  tar_target(
    c1_tier_diagnostics,
    prepare_chunk_tier_diagnostics(aligned_data, chunks, c1_positive_ids,
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

  # C1-classified chunks: merge C1 LLM output with chunk text and ground truth
  tar_target(
    c1_classified_chunks,
    assemble_c1_classified_chunks(c1_s2_results, chunks, aligned_data),
    packages = "tidyverse"
  ),

  # C2 input: FISCAL_MEASURE chunks with discusses_motivation == TRUE
  tar_target(
    c2_input_data,
    assemble_c2_input_data(c1_classified_chunks),
    packages = "tidyverse"
  ),

  tar_quarto(
    verify_c2_inputs,
    "notebooks/verify_c2_inputs.qmd"
  ),

  # C2 S0: Track codebook files so YAML edits invalidate downstream targets
  tar_target(
    c2a_codebook_file,
    here::here("prompts", "c2a_extraction.yml"),
    format = "file",
    packages = "here"
  ),
  tar_target(
    c2a_codebook,
    load_validate_codebook(c2a_codebook_file),
    packages = "yaml"
  ),
  tar_target(
    c2b_codebook_file,
    here::here("prompts", "c2b_classification.yml"),
    format = "file",
    packages = "here"
  ),
  tar_target(
    c2b_codebook,
    load_validate_codebook(c2b_codebook_file),
    packages = "yaml"
  ),

  # C2 S1: Behavioral tests (independent per sub-codebook)
  tar_target(
    c2a_s1_results,
    run_c2a_behavioral_tests_s1(
      c2a_codebook,
      c2_input_data,
      model = "qwen/qwen-2.5-72b-instruct",
      max_tokens = 1024,
      provider = "openai",
      base_url = "https://openrouter.ai/api/v1",
      api_key = Sys.getenv("OPENROUTER_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),
  tar_target(
    c2b_s1_results,
    run_c2b_behavioral_tests_s1(
      c2b_codebook,
      model = "qwen/qwen-2.5-72b-instruct",
      max_tokens = 1024,
      provider = "openai",
      base_url = "https://openrouter.ai/api/v1",
      api_key = Sys.getenv("OPENROUTER_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),

  # ==========================================================================
  # C2 S2: Zero-shot motivation classification (composed C2a→C2b pipeline)
  # ==========================================================================

  # Primary chain: C1-filtered inputs (FISCAL_MEASURE + discusses_motivation)
  tar_target(
    c2_s2_test_set,
    assemble_c2_s2_test_set(c2_input_data, aligned_data),
    packages = "tidyverse"
  ),
  tar_target(
    c2_s2_results,
    run_c2_zero_shot(
      c2a_codebook, c2b_codebook, c2_s2_test_set,
      model = "qwen/qwen-2.5-72b-instruct",
      max_tokens_c2a = 1024, max_tokens_c2b = 1024,
      provider = "openrouter",
      base_url = "https://openrouter.ai/api/v1",
      api_key = Sys.getenv("OPENROUTER_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),
  tar_target(
    c2_s2_eval,
    evaluate_c2_classification(c2_s2_results),
    packages = "tidyverse"
  ),

  # Sensitivity chain: relaxes discusses_motivation filter
  tar_target(
    c2_s2_sensitivity_data,
    assemble_c2_s2_sensitivity_data(c1_classified_chunks),
    packages = "tidyverse"
  ),
  tar_target(
    c2_s2_sensitivity_test_set,
    assemble_c2_s2_test_set(c2_s2_sensitivity_data, aligned_data),
    packages = "tidyverse"
  ),
  tar_target(
    c2_s2_sensitivity_results,
    run_c2_zero_shot(
      c2a_codebook, c2b_codebook, c2_s2_sensitivity_test_set,
      model = "qwen/qwen-2.5-72b-instruct",
      max_tokens_c2a = 1024, max_tokens_c2b = 1024,
      provider = "openrouter",
      base_url = "https://openrouter.ai/api/v1",
      api_key = Sys.getenv("OPENROUTER_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),
  tar_target(
    c2_s2_sensitivity_eval,
    evaluate_c2_classification(c2_s2_sensitivity_results),
    packages = "tidyverse"
  ),

  # C1 S0: Track codebook file so YAML edits invalidate downstream targets
  tar_target(
    c1_codebook_file,
    here::here("prompts", "c1_measure_id.yml"),
    format = "file",
    packages = "here"
  ),
  tar_target(
    c1_codebook,
    load_validate_codebook(c1_codebook_file),
    packages = "yaml"
  ),

  # Pre-flight verification of API inputs before S2 LOOCV
  tar_quarto(
    verify_api_inputs,
    "notebooks/verify_api_inputs.qmd",
    garbage_collection = TRUE
  ),

  # S1: Behavioral tests (Tests I-IV) on chunk-length inputs
  tar_target(
    c1_s1_results,
    run_behavioral_tests_s1(
      c1_codebook,
      aligned_data,
      c1_chunk_data,
      model = "claude-haiku-4-5-20251001",
      max_tokens = 1024,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite", "progress"),
    deployment = "main"
  ),

  # S2: Zero-shot evaluation — assemble test set (no API calls)
  # All Tier 1 + capped Tier 2 + sampled negatives in one pass
  tar_target(
    c1_s2_test_set,
    assemble_zero_shot_test_set(
      c1_codebook,
      aligned_data,
      c1_chunk_data,
      n_negatives = 100,
      n_tier2_per_act = 20,
      seed = 20251206
    ),
    packages = "tidyverse"
  ),

  # S2: Zero-shot evaluation — classify test set (API calls)
  # Each chunk classified exactly once with codebook prompt, no few-shot
  tar_target(
    c1_s2_results,
    run_zero_shot(
      c1_codebook,
      c1_s2_test_set,
      codebook_type = "C1",
      model = "claude-haiku-4-5-20251001",
      max_tokens = 1024,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite", "progress"),
    deployment = "main"
  ),

  # S2: Evaluation metrics (no API calls)
  tar_target(
    c1_s2_eval,
    evaluate_classification(c1_s2_results, codebook_type = "C1", n_bootstrap = 1000),
    packages = "tidyverse"
  ),

  # S3: Error analysis — assemble test set (no API calls)
  tar_target(
    c1_s3_test_set,
    assemble_s3_test_set(c1_chunk_data, n_tier1 = 10, n_tier2 = 10, n_negatives = 20),
    packages = c("tidyverse")
  ),

  # S3: Error analysis — Tests V-VII + ablation (API calls)
  tar_target(
    c1_s3_results,
    run_error_analysis(
      c1_codebook,
      c1_s3_test_set,
      model = "claude-haiku-4-5-20251001",
      max_tokens = 1024,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
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
