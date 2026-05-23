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

# Malaysia EN/BM consistency test — Jaro-Winkler distance cutoff for
# clustering near-duplicate measure names within each document.
malay_er_cluster_threshold <- 0.15

# LLM configuration is hardcoded per target (not shared globals) so that
# changing one codebook/stage's model never invalidates another's cache.
# C1 targets: Haiku (validated). C2a: Haiku (extraction). C2b: Haiku (classification, v0.5.0 test).

# Filesystem-driven extraction targets, one set per non-US country in
# build_country_configs(). Spliced into the master list below; tar_combine
# below references this binding by name.
deployment_country_targets <- tarchetypes::tar_map(
  # `country_slug` (not `country`) so tar_map's symbol substitution does
  # not clobber `.x$country` column references downstream.
  values = list(country_slug = vapply(build_country_configs(),
                                      `[[`, character(1), "country")),
  names = country_slug,
  unlist = FALSE,

  tarchetypes::tar_files(
    country_pdf_files,
    command = discover_country_pdfs(
      country_slug,
      year_min = build_country_configs()[[country_slug]]$pilot_year_min,
      year_max = build_country_configs()[[country_slug]]$pilot_year_max
    )
  ),

  tar_target(
    country_text,
    extract_pdf_file(country_pdf_files),
    pattern = map(country_pdf_files),
    iteration = "list"
  ),

  tar_target(
    country_body,
    assemble_country_body(
      file_paths = country_pdf_files,
      text_branches = country_text,
      country_urls_for_country = country_urls_for(country_urls, country_slug)
    ),
    packages = c("tidyverse")
  )
)

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
    cue = tar_cue(mode = "never"),
    packages = "tidyverse"
  ),

  # C2 input: single frozen source (sensitivity superset = all FISCAL_MEASURE chunks).
  # Primary condition (discusses_motivation == TRUE) derived by filtering.
  # To refresh after C1 re-validation: source("R/freeze_results.R"); freeze_results("c2_s2_sensitivity_data")
  # Note: chunk_id 94 exists in the old c2_input_data.qs but is missing from
  # c2_s2_sensitivity_data.qs (frozen at different times). Accepted as immaterial (1/508).
  tar_target(
    c2_s2_sensitivity_file,
    here::here("data", "validated", "c2_s2_sensitivity_data.qs"),
    format = "file"
  ),
  tar_target(
    c2_s2_sensitivity_data,
    qs2::qs_read(c2_s2_sensitivity_file),
    packages = "qs2"
  ),
  tar_target(
    c2_input_data,
    c2_s2_sensitivity_data |>
      dplyr::filter(discusses_motivation == TRUE),
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
      model = "claude-haiku-4-5-20251001",
      max_tokens = 16384,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),
  tar_target(
    c2b_s1_results,
    run_c2b_behavioral_tests_s1(
      c2b_codebook,
      model = "claude-haiku-4-5-20251001",
      max_tokens = 1024,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),

  # ==========================================================================
  # C2 S2: Zero-shot motivation classification (split C2a → C2b pipeline)
  # C2a runs ONCE on the sensitivity superset (all FISCAL_MEASURE chunks).
  # C2b runs TWICE: primary (discusses_motivation only) and sensitivity (all).
  # ==========================================================================

  # Test sets (act-level with nested chunks + ground truth)
  tar_target(
    c2_s2_test_set,
    assemble_c2_s2_test_set(c2_input_data, aligned_data),
    packages = "tidyverse"
  ),
  tar_target(
    c2_s2_sensitivity_test_set,
    assemble_c2_s2_test_set(c2_s2_sensitivity_data, aligned_data),
    packages = "tidyverse"
  ),

  # C2a: single extraction pass on all sensitivity chunks
  tar_target(
    c2a_evidence,
    run_c2a_extraction(
      c2a_codebook, c2_s2_sensitivity_test_set,
      model = "claude-haiku-4-5-20251001",
      max_tokens_c2a = 16384,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),

  # Frozen C2a evidence for C2b consumption (decouples C2b from C2a code changes)
  # To refresh: source("R/freeze_results.R"); freeze_results("c2a_evidence")
  tar_target(
    c2b_inputs_file,
    here::here("data", "validated", "c2a_evidence.qs"),
    format = "file",
    packages = "here"
  ),
  tar_target(
    c2b_inputs,
    qs2::qs_read(c2b_inputs_file),
    packages = "qs2"
  ),

  # C2b primary: filter evidence to discusses_motivation == TRUE chunks
  tar_target(
    c2_s2_results,
    run_c2b_classification(
      c2b_codebook,
      c2b_inputs |> dplyr::filter(discusses_motivation == TRUE),
      c2_s2_test_set,
      model = "claude-haiku-4-5-20251001",
      max_tokens_c2b = 4096,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),
  tar_target(
    c2_s2_eval,
    evaluate_c2_classification(c2_s2_results),
    packages = "tidyverse"
  ),

  # C2b sensitivity: use all evidence
  tar_target(
    c2_s2_sensitivity_results,
    run_c2b_classification(
      c2b_codebook,
      c2b_inputs,
      c2_s2_sensitivity_test_set,
      model = "claude-haiku-4-5-20251001",
      max_tokens_c2b = 4096,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),
  tar_target(
    c2_s2_sensitivity_eval,
    evaluate_c2_classification(c2_s2_sensitivity_results),
    packages = "tidyverse"
  ),

  # C2 S3: Error analysis (Tests V-VII + ablation on C2b)
  tar_target(
    c2_s3_results,
    run_c2_error_analysis(
      c2b_codebook, c2_s2_results,
      model = "claude-haiku-4-5-20251001",
      max_tokens_c2b = 4096,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),

  # C2 S3 leakage diagnostic: per-act evidence-record shuffle on F+A clusters.
  # Reads iter 30 manual-review per-act notes (authoritative cluster source).
  tar_target(
    c2b_iterations_log,
    here::here("prompts", "iterations", "c2b.yml"),
    format = "file",
    packages = "here"
  ),
  tar_target(
    s3_act_clusters,
    build_s3_act_clusters(c2b_iterations_log, iteration = 30L),
    packages = c("yaml", "tibble", "dplyr")
  ),
  tar_target(
    c2b_evidence_shuffle_diagnostic,
    test_c2b_evidence_shuffle(
      c2b_codebook,
      c2b_inputs,
      s3_act_clusters,
      k_shuffles = 3L,
      model = "claude-haiku-4-5-20251001",
      max_tokens_c2b = 4096,
      seed = 42L,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
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

  # S1: Behavioral tests (Tests I-IV) on chunk-length inputs.
  # country_iso = "US" — Phase 0 dev evaluation uses US documents; the
  # {country_iso} token in the C1 v0.7.0 YAML resolves to "US" here.
  tar_target(
    c1_s1_results,
    run_behavioral_tests_s1(
      c1_codebook,
      aligned_data,
      c1_chunk_data,
      model = "claude-haiku-4-5-20251001",
      max_tokens = 3072,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY"),
      country_iso = "US"
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
  # Each chunk classified exactly once with codebook prompt, no few-shot.
  # Output is long-form under C1 v0.7.0 (one row per chunk × measure).
  tar_target(
    c1_s2_results,
    run_zero_shot(
      c1_codebook,
      c1_s2_test_set,
      codebook_type = "C1",
      model = "claude-haiku-4-5-20251001",
      max_tokens = 3072,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY"),
      country_iso = "US"
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

  # S3 under-listing diagnostic input (no API calls): chunks whose Tier 1
  # ground truth contains >= 2 distinct labeled acts. Test input for the
  # C1 v0.7.0 multi-measure under-listing test inside `run_error_analysis()`.
  tar_target(
    c1_multi_act_chunks,
    derive_multi_act_chunks(c1_chunk_data, min_acts = 2L),
    packages = c("tidyverse")
  ),

  # S3: Error analysis — Tests V-VII + ablation + v0.7.0 multi-measure
  # diagnostics (over-listing, country distribution, under-listing). API calls.
  tar_target(
    c1_s3_results,
    run_error_analysis(
      c1_codebook,
      c1_s3_test_set,
      model = "claude-haiku-4-5-20251001",
      max_tokens = 3072,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY"),
      country_iso = "US",
      multi_act_chunks = c1_multi_act_chunks
    ),
    packages = c("tidyverse", "httr2", "jsonlite", "progress"),
    deployment = "main"
  ),
  tar_quarto(
    verify_c1,
    "notebooks/c1_measure_id.qmd"
  ),

  # =============================================================================
  # Iteration Log Parsing (cross-codebook development history)
  # =============================================================================
  tar_target(
    c1_iteration_log_file,
    here::here("prompts", "iterations", "c1.yml"),
    format = "file"
  ),
  tar_target(
    c2a_iteration_log_file,
    here::here("prompts", "iterations", "c2a.yml"),
    format = "file"
  ),
  tar_target(
    c2b_iteration_log_file,
    here::here("prompts", "iterations", "c2b.yml"),
    format = "file"
  ),
  tar_target(
    iteration_logs,
    parse_all_iteration_logs(c(
      c1 = c1_iteration_log_file,
      c2a = c2a_iteration_log_file,
      c2b = c2b_iteration_log_file
    )),
    packages = c("tidyverse", "yaml")
  ),

  # =============================================================================
  # Deployment Pipeline (Phase 1 / Phase 2)
  # Country-agnostic dynamic branching. Adding a country = appending one entry
  # to build_country_configs() in R/build_country_configs.R; existing branches
  # stay cached because dynamic branches hash independently.
  # Stops at C2a evidence; C2b deployment deferred until C2b codebook stabilizes.
  # =============================================================================

  tar_target(
    country_configs,
    build_country_configs(),
    iteration = "list"
  ),

  tar_target(
    country_urls,
    get_country_urls(country_configs),
    pattern = map(country_configs),
    iteration = "list",
    packages = c("tidyverse", "rvest")
  ),

  # Filesystem-driven extraction (non-US): one set of targets per country,
  # generated by `deployment_country_targets` above. `tar_files()` content-
  # hashes each PDF; per-file extraction never sees a URL. tar_combine
  # below merges per-country bodies into a list so downstream
  # `pattern = map(country_body)` keeps working.
  deployment_country_targets,

  tarchetypes::tar_combine(
    country_body,
    deployment_country_targets$country_body,
    command = list(!!!.x),
    use_names = TRUE,
    iteration = "list"
  ),

  tar_quarto(
    verify_country_body,
    path = here("notebooks/verify_country_body.qmd"),
    cache = FALSE
  ),

  tar_target(
    country_chunks,
    make_chunks(country_body, window_size = 10, overlap = 3,
                max_tokens = 40000, min_chars = 100L),
    pattern = map(country_body),
    iteration = "list",
    packages = c("tidyverse", "purrr")
  ),

  tar_target(
    country_c1_predictions,
    run_c1_deployment(
      country_chunks,
      c1_codebook,
      country_iso = country_configs[[unique(country_chunks$country)[1]]]$country_iso %||% "US",
      model = "claude-haiku-4-5-20251001",
      max_tokens = 3072,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    pattern = map(country_chunks),
    iteration = "list",
    packages = c("tidyverse", "httr2", "jsonlite", "progress"),
    deployment = "main"
  ),

  tar_target(
    country_c1_measures,
    filter_c1_measures(country_c1_predictions, country_chunks),
    pattern = map(country_c1_predictions, country_chunks),
    iteration = "list",
    packages = "tidyverse"
  ),

  tar_target(
    country_c2a_evidence,
    run_c2a_deployment(
      country_c1_measures,
      c2a_codebook,
      model = "claude-haiku-4-5-20251001",
      max_tokens_c2a = 16384,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    pattern = map(country_c1_measures),
    iteration = "list",
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),

  # =============================================================================
  # Malaysia EN/BM Cross-Language Consistency Test
  # Self-contained sub-pipeline that slices country_chunks to Economic Report
  # documents with parallel EN+BM coverage, runs its own C1 -> C2a -> C2b on
  # the slice, and produces consistency metrics with bootstrap CIs. See
  # docs/phase_1/malaysia_acquisition.md §4.1 and notebooks/malay_consistency.qmd.
  # =============================================================================

  tar_target(
    malay_er_manifest_file,
    here::here("data", "manual", "malaysia", "economic_report", "MANIFEST.csv"),
    format = "file",
    packages = "here"
  ),

  tar_target(
    malay_er_pair_years,
    select_malay_er_pair_years(malay_er_manifest_file),
    packages = c("readr", "dplyr")
  ),

  tar_target(
    malay_er_chunks,
    slice_malay_er_chunks(country_chunks, malay_er_pair_years),
    packages = c("tidyverse", "stringr")
  ),

  tar_target(
    malay_er_c1,
    run_c1_deployment(
      malay_er_chunks, c1_codebook,
      country_iso = "MY",
      model = "claude-haiku-4-5-20251001",
      max_tokens = 3072,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite", "progress"),
    deployment = "main"
  ),

  tar_target(
    malay_er_c1_measures,
    filter_c1_measures(malay_er_c1, malay_er_chunks),
    packages = "tidyverse"
  ),

  tar_target(
    malay_er_c2a,
    run_c2a_deployment(
      malay_er_c1_measures, c2a_codebook,
      model = "claude-haiku-4-5-20251001",
      max_tokens_c2a = 16384,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),

  tar_target(
    malay_er_clusters,
    cluster_measure_names_within_doc(malay_er_c2a,
                                     threshold = malay_er_cluster_threshold),
    packages = c("tidyverse", "stringdist")
  ),

  tar_target(
    malay_er_candidates,
    propose_en_bm_match_candidates(
      malay_er_clusters,
      malay_er_c2a,
      model = "claude-sonnet-4-20250514"
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),

  tar_target(
    malay_er_candidates_file,
    write_malay_er_candidates_csv(
      malay_er_candidates,
      here::here("data", "manual", "malaysia", "er_consistency_candidates.csv")
    ),
    format = "file",
    packages = c("here", "readr")
  ),

  tar_target(
    malay_er_curated_matches_file,
    ensure_curated_matches_file(
      here::here("data", "manual", "malaysia", "er_consistency_matches_curated.csv"),
      malay_er_candidates_file
    ),
    format = "file",
    packages = c("here", "readr", "tibble")
  ),

  tar_target(
    malay_er_curated_matches,
    load_curated_matches_or_stub(malay_er_curated_matches_file),
    packages = c("readr", "tibble")
  ),

  tar_target(
    malay_er_c2b_inputs,
    aggregate_act_evidence_for_c2b(malay_er_curated_matches,
                                   malay_er_clusters, malay_er_c2a),
    packages = "tidyverse"
  ),

  tar_target(
    malay_er_c2b,
    run_malay_er_c2b(
      malay_er_c2b_inputs, c2b_codebook,
      model = "claude-haiku-4-5-20251001",
      max_tokens_c2b = 4096,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),

  tar_target(
    malay_er_consistency_metrics,
    compute_malay_er_consistency_metrics(
      malay_er_c1, malay_er_c2b,
      malay_er_curated_matches, malay_er_candidates, malay_er_clusters,
      n_boot = 1000L, seed = 20260514L
    ),
    packages = "tidyverse"
  ),

  tar_quarto(
    malay_consistency,
    path = here("notebooks/malay_consistency.qmd"),
    cache = FALSE
  ),

  # =============================================================================
  # C0 Act Aggregator — empirical design notebook
  # Compares 5 methods for aggregating C1 measure_name strings into act-level
  # canonical clusters. Anchored to US gold standard (Tier 1/2 chunks where
  # c1_s2_results already carries the chunk's gold act_name).
  #
  # Phase A (below): deterministic, no API cost. Builds the pool and gold
  # pairs, runs JW single-linkage at a 5-threshold × {unblocked, year_window=2}
  # grid, evaluates with pairwise P/R/F1, ARI, purity, over/under-merge
  # (bootstrap CIs resampled at gold-row level).
  #
  # Phase B (embeddings + HDBSCAN) lives below alongside Phase A; embedding
  # decision: intfloat/multilingual-e5-large-instruct served locally via
  # Ollama (F16 community port), no API key required. LLM judge (Method 4)
  # and stateful builder (Method 5) remain deferred.
  # =============================================================================

  tar_target(
    c0_us_measure_pool,
    build_c0_measure_pool(c1_s2_results),
    packages = "tidyverse"
  ),

  tar_target(
    c0_eval_gold_pairs,
    build_c0_eval_gold_pairs(c1_s2_results),
    packages = "tidyverse"
  ),

  tar_target(
    c0_jw_clusters,
    run_jw_clusters_grid(
      c0_us_measure_pool,
      thresholds = c(0.10, 0.15, 0.20, 0.25, 0.30),
      year_windows = list(NULL, 2L)
    ),
    packages = c("tidyverse", "stringdist", "igraph")
  ),

  tar_target(
    c0_jw_metrics,
    evaluate_clusters_grid(
      c0_jw_clusters,
      c0_eval_gold_pairs,
      group_keys = "variant_id",
      n_boot = 1000L,
      seed = 20260521L
    ),
    packages = "tidyverse"
  ),

  # Phase B: Method 2 + 3 (embedding + HDBSCAN, unblocked and year-blocked).
  # Embedding via local Ollama on jeffh/intfloat-multilingual-e5-large-instruct
  # (F16). Model + instruction string are isolated as their own targets so
  # changing either invalidates only c0_us_embeddings, not downstream funcs.

  tar_target(
    c0_embedding_model,
    "jeffh/intfloat-multilingual-e5-large-instruct:f16"
  ),

  tar_target(
    c0_embedding_instruction,
    "Represent this fiscal-act name for clustering with paraphrases"
  ),

  tar_target(
    c0_us_embeddings,
    embed_c0_measure_pool(
      c0_us_measure_pool,
      model = c0_embedding_model,
      instruction = c0_embedding_instruction
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    format = "qs"
  ),

  tar_target(
    c0_hdbscan_clusters,
    run_hdbscan_clusters_grid(
      c0_us_embeddings,
      c0_us_measure_pool,
      min_cluster_sizes = c(2L, 3L, 5L),
      year_windows = list(NULL, 2L)
    ),
    packages = c("tidyverse", "dbscan")
  ),

  tar_target(
    c0_hdbscan_metrics,
    evaluate_clusters_grid(
      c0_hdbscan_clusters,
      c0_eval_gold_pairs,
      group_keys = "variant_id",
      n_boot = 1000L,
      seed = 20260521L
    ),
    packages = "tidyverse"
  ),

  tar_target(
    c0_f16_quantization_probe,
    probe_f16_quantization(c0_us_embeddings, c0_eval_gold_pairs),
    packages = "tidyverse"
  ),

  tar_quarto(
    c0_aggregator,
    path = here("notebooks/c0_aggregator.qmd"),
    cache = FALSE
  )


)
