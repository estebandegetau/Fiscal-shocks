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

# Heterogeneous crew controllers. Most targets dispatch through `default`
# (essentially sequential — one worker — but goes through the crew layer).
# C0 UMAP-sweep targets opt into `c0_umap` (3 workers) via per-target
# resources. See https://books.ropensci.org/targets/crew.html#heterogeneous-workers
crew_default <- crew::crew_controller_local(
  name         = "default",
  workers      = 1L,
  seconds_idle = 10
)

crew_c0_umap <- crew::crew_controller_local(
  name         = "c0_umap",
  workers      = 6L,
  seconds_idle = 10
)

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
  error = "abridge",
  controller = crew::crew_controller_group(crew_default, crew_c0_umap)
)

# Run the R scripts in the R/ folder with your custom functions:
tar_source()
# tar_source("other_functions.R") # Source other scripts as needed.

# Replace the target list below with your own:
max_year <- 2022
min_year <- 1946

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
      country_urls_for_country = country_urls_for(country_urls, country_slug),
      country_iso = build_country_configs()[[country_slug]]$country_iso
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

  # Graduated figure example for the Quarto style guide (Figure & Table
  # Lifecycle). Returns a bare ggplot object; caption/label owned by the
  # consuming chunk in the notebook or index.qmd.
  tar_target(
    fig_c0_variance_per_act,
    plot_variance_per_act(c0_eval_gold_pairs),
    packages = c("dplyr", "forcats", "stringr", "ggplot2")
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
                max_tokens = 40000, min_chars = 100L,
                carry_cols = c("country", "country_iso")),
    pattern = map(country_body),
    iteration = "list",
    packages = c("tidyverse", "purrr")
  ),

  tar_target(
    country_c1_predictions,
    run_c1_deployment(
      country_chunks,
      c1_codebook,
      country_iso = unique(country_chunks$country_iso)[1] %||% "US",
      country = unique(country_chunks$country)[1] %||% "united states",
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

  # ---------------------------------------------------------------------------
  # C0 act aggregation -> C2b classification (continues the deployment chain).
  #
  # All five targets branch per-country via single-input `map(..., iteration =
  # "list")`. Each country branch IS one whole-country pool, so C0 aggregates the
  # country jointly (EN + BM together) in a single M5 call -- one deduplicated
  # cross-language act inventory per country.
  #
  # Positional-zip invariant: country_c0_acts and country_c2b_inputs zip two
  # branched inputs each. This is safe ONLY because every target in this chain
  # descends from country_c1_measures via single-input `map` (1:1 branch
  # preservation, never `cross`/`tar_group_*`), so branch order is identical
  # across country_c2a_evidence / country_measure_pool / country_c0_clusters /
  # country_c0_clusters_checked / country_c0_acts. country_c0_clusters_checked
  # is a 1:1 pass-through guard (returns its input unchanged), so it preserves
  # branch order. Do not insert a branch-dropping step into this chain.
  # ---------------------------------------------------------------------------

  tar_target(
    country_measure_pool,
    build_country_measure_pool(country_c1_measures),
    pattern = map(country_c1_measures),
    iteration = "list",
    packages = "tidyverse"
  ),

  # tar_target(
  #   country_c0_clusters,
  #   run_c0_deployment(
  #     country_measure_pool,
  #     instruction = c0_m5_prompt$instruction,
  #     model = "claude-haiku-4-5-20251001",
  #     max_tokens = 64000,
  #     seed = 1L,
  #     provider = "anthropic",
  #     base_url = "https://api.anthropic.com/v1",
  #     api_key = Sys.getenv("ANTHROPIC_API_KEY")
  #   ),
  #   pattern = map(country_measure_pool),
  #   iteration = "list",
  #   packages = c("tidyverse", "httr2", "jsonlite", "withr"),
  #   deployment = "main"
  # ),

  # tar_target(
  #   country_c0_acts,
  #   reshape_c0_clusters_deployment(country_c0_clusters, country_measure_pool),
  #   pattern = map(country_c0_clusters, country_measure_pool),
  #   iteration = "list",
  #   packages = "tidyverse"
  # ),

#---- Test C0 on Sonnet

  tar_target(
    country_c0_clusters,
    run_c0_deployment_stream(
      country_measure_pool,
      instruction = c0_m5_prompt$instruction,
      model = "claude-sonnet-4-6",
      max_tokens = 64000,
      seed = 1L,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    pattern = map(country_measure_pool),
    iteration = "list",
    packages = c("tidyverse", "httr2", "jsonlite", "withr"),
    deployment = "main"
  ),

  # Quality guard: hard-FAIL (halt before C2b) on a degenerate near-no-merge C0
  # clustering (merge_rate < 1%); WARN below 5%. Pass-through -- returns
  # country_c0_clusters unchanged, so the raw value stays cached/inspectable.
  tar_target(
    country_c0_clusters_checked,
    guard_c0_merge_rate(
      country_c0_clusters,
      fail_below = 0.01,
      warn_below = 0.05
    ),
    pattern = map(country_c0_clusters),
    iteration = "list",
    packages = "tidyverse"
  ),

  tar_target(
    country_c0_acts,
    reshape_c0_clusters_deployment(country_c0_clusters_checked, country_measure_pool),
    pattern = map(country_c0_clusters_checked, country_measure_pool),
    iteration = "list",
    packages = "tidyverse"
  ),

#---- Resume Deployment Stage

  tar_target(
    country_c2b_inputs,
    aggregate_c0_acts_deployment(country_c0_acts, country_c2a_evidence),
    pattern = map(country_c0_acts, country_c2a_evidence),
    iteration = "list",
    packages = c("tidyverse", "stringr")
  ),

  tar_target(
    country_c2b,
    run_c2b_deployment(
      country_c2b_inputs,
      c2b_codebook,
      model = "claude-haiku-4-5-20251001",
      max_tokens_c2b = 4096,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    pattern = map(country_c2b_inputs),
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

  # Grouped one branch per `doc_id` so the per-document API chain below
  # (C1 -> C2a -> C0 per-doc) branches dynamically: changing the corpus
  # re-runs only the changed document's branches, not the whole slice.
  # `tar_read(malay_er_chunks)` still returns the full tibble (plus a harmless
  # `tar_group` column). NB: dynamic branch identity is positional -- appending
  # a newer pair year is cheap, but backfilling a mid-sequence document shifts
  # downstream branches from the insertion point onward.
  tarchetypes::tar_group_by(
    malay_er_chunks,
    slice_malay_er_chunks(country_chunks, malay_er_pair_years),
    doc_id,
    packages = c("tidyverse", "stringr")
  ),

  # Branched per document. Default vector iteration aggregates the per-doc
  # branches into one combined tibble for non-branching consumers (the notebook
  # plots, the pooled C0 steps).
  tar_target(
    malay_er_c1,
    run_c1_deployment(
      malay_er_chunks, c1_codebook,
      country_iso = "MY",
      country = "malaysia",
      model = "claude-haiku-4-5-20251001",
      max_tokens = 3072,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    pattern = map(malay_er_chunks),
    packages = c("tidyverse", "httr2", "jsonlite", "progress"),
    deployment = "main"
  ),

  tar_target(
    malay_er_c1_measures,
    filter_c1_measures(malay_er_c1, malay_er_chunks),
    pattern = map(malay_er_c1, malay_er_chunks),
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
    pattern = map(malay_er_c1_measures),
    packages = c("tidyverse", "httr2", "jsonlite"),
    deployment = "main"
  ),

  # C0 act aggregator (M5 LLM canonical clustering) replaces the old
  # within-doc Jaro-Winkler clusterer. Three scopes: per-doc and joint are
  # C0-only diagnostics; per-language is the deployment-realistic inventory
  # that feeds C2 and the headline timeline. Reuses the c0_m5_prompt target
  # (prompts/c0_canonicalize.yml). All three are API-calling (Haiku).
  # Branched per document: each branch builds that document's measure pool; the
  # vector-aggregated value is the full pool the pooled C0 scopes below consume.
  tar_target(
    malay_er_measure_pool,
    build_malay_er_measure_pool(malay_er_c1_measures),
    pattern = map(malay_er_c1_measures),
    packages = c("tidyverse", "stringr")
  ),

  # Per-doc scope branches naturally: each branch is one document's pool, which
  # `run_malay_er_c0(scope = "per_doc")` partitions into a single group.
  tar_target(
    malay_er_c0_perdoc,
    run_malay_er_c0(
      malay_er_measure_pool, scope = "per_doc",
      model = "claude-haiku-4-5-20251001",
      instruction = c0_m5_prompt$instruction,
      max_tokens = 8192,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    pattern = map(malay_er_measure_pool),
    packages = c("tidyverse", "httr2", "jsonlite", "withr"),
    deployment = "main"
  ),

  tar_target(
    malay_er_c0_perlang,
    run_malay_er_c0(
      malay_er_measure_pool, scope = "per_language",
      model = "claude-haiku-4-5-20251001",
      instruction = c0_m5_prompt$instruction,
      max_tokens = 8192,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite", "withr"),
    deployment = "main"
  ),

  tar_target(
    malay_er_c0_joint,
    run_malay_er_c0(
      malay_er_measure_pool, scope = "joint",
      model = "claude-haiku-4-5-20251001",
      instruction = c0_m5_prompt$instruction,
      max_tokens = 8192,
      provider = "anthropic",
      base_url = "https://api.anthropic.com/v1",
      api_key = Sys.getenv("ANTHROPIC_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite", "withr"),
    deployment = "main"
  ),

  tar_target(
    malay_er_c0_acts,
    reshape_c0_clusters_to_chunks(malay_er_c0_perlang, malay_er_measure_pool),
    packages = "tidyverse"
  ),

  tar_target(
    malay_er_c2b_inputs,
    aggregate_c0_acts_for_c2b(malay_er_c0_acts, malay_er_c2a),
    packages = c("tidyverse", "stringr")
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
    compute_malay_er_consistency_tallies(
      malay_er_c0_perdoc, malay_er_c0_perlang, malay_er_c0_joint,
      malay_er_c2b, malay_er_measure_pool
    ),
    packages = c("tidyverse", "stringr")
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

  # FP32 reference of the same model, hosted on DeepInfra. Used only by
  # the probe section of c0_aggregator.qmd to disentangle "F16 broke the
  # geometry" from "the model itself can't do this task". Methods 2/3
  # (HDBSCAN) continue to read c0_us_embeddings (F16).
  tar_target(
    c0_embedding_model_fp32,
    "intfloat/multilingual-e5-large-instruct"
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
    c0_us_gold_embeddings,
    embed_c0_gold_labels(
      c0_eval_gold_pairs,
      model = c0_embedding_model,
      instruction = c0_embedding_instruction
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    format = "qs"
  ),

  tar_target(
    c0_us_embeddings_fp32,
    embed_c0_measure_pool(
      c0_us_measure_pool,
      model       = c0_embedding_model_fp32,
      instruction = c0_embedding_instruction,
      provider    = "openai",
      base_url    = "https://api.deepinfra.com/v1/openai",
      api_key     = Sys.getenv("DEEPINFRA_API_KEY")
    ),
    packages = c("tidyverse", "httr2", "jsonlite"),
    format = "qs"
  ),

  tar_target(
    c0_us_gold_embeddings_fp32,
    embed_c0_gold_labels(
      c0_eval_gold_pairs,
      model       = c0_embedding_model_fp32,
      instruction = c0_embedding_instruction,
      provider    = "openai",
      base_url    = "https://api.deepinfra.com/v1/openai",
      api_key     = Sys.getenv("DEEPINFRA_API_KEY")
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
    c0_umap_grid,
    tidyr::expand_grid(
      n_neighbors  = c(5L, 15L, 30L),
      n_components = c(2L, 5L, 10L),
      min_dist     = c(0.0, 0.01, 0.1)
    ),
    packages = "tidyverse"
  ),

  tar_target(
    c0_hdbscan_umap_clusters,
    run_hdbscan_umap_clusters_one_cell(
      embeddings        = c0_us_embeddings,
      measure_pool      = c0_us_measure_pool,
      n_neighbors       = c0_umap_grid$n_neighbors,
      n_components      = c0_umap_grid$n_components,
      min_dist          = c0_umap_grid$min_dist,
      min_cluster_sizes = c(2L, 3L, 5L),
      year_windows      = list(NULL, 2L),
      seed              = 20260526L
    ),
    pattern   = map(c0_umap_grid),
    packages  = c("tidyverse", "dbscan", "uwot"),
    resources = tar_resources(crew = tar_resources_crew(controller = "c0_umap"))
  ),

  tar_target(
    c0_hdbscan_umap_metrics,
    evaluate_clusters_grid(
      c0_hdbscan_umap_clusters,
      c0_eval_gold_pairs,
      group_keys = "variant_id",
      n_boot = 1000L,
      seed = 20260521L
    ),
    pattern   = map(c0_hdbscan_umap_clusters),
    packages  = "tidyverse",
    resources = tar_resources(crew = tar_resources_crew(controller = "c0_umap"))
  ),

  # UMAP-space embedding-geometry probe (Euclidean analog of the F16/FP32
  # cosine probes below). Cache the reductions once so the probe — and any
  # future UMAP-space diagnostic — reuses them instead of re-running uwot.
  # Same seed as `c0_hdbscan_umap_clusters` so the reduced space the probe
  # measures is identical to the one HDBSCAN clusters in.
  tar_target(
    c0_umap_reduced_embeddings,
    umap_reduce_embeddings(
      c0_us_embeddings,
      n_neighbors  = c0_umap_grid$n_neighbors,
      n_components = c0_umap_grid$n_components,
      min_dist     = c0_umap_grid$min_dist,
      seed         = 20260526L
    ),
    pattern   = map(c0_umap_grid),
    iteration = "list",
    packages  = c("tidyverse", "uwot"),
    format    = "qs",
    resources = tar_resources(crew = tar_resources_crew(controller = "c0_umap"))
  ),

  # Full-pool probe (unambiguous Tier 1 + Tier 2). Each branch carries its
  # UMAP cell coordinates so downstream plots can read hyperparams without
  # re-parsing variant_ids.
  tar_target(
    c0_hdbscan_umap_probe,
    tibble::tibble(
      n_neighbors  = c0_umap_grid$n_neighbors,
      n_components = c0_umap_grid$n_components,
      min_dist     = c0_umap_grid$min_dist
    ) |>
      dplyr::bind_cols(
        probe_umap_geometry(c0_umap_reduced_embeddings, c0_eval_gold_pairs)
      ),
    pattern  = map(c0_umap_reduced_embeddings, c0_umap_grid),
    packages = c("tidyverse")
  ),

  # Tier 1 slice — caller pre-filters, mirroring
  # `c0_f16_quantization_probe_tier1` below.
  tar_target(
    c0_hdbscan_umap_probe_tier1,
    tibble::tibble(
      n_neighbors  = c0_umap_grid$n_neighbors,
      n_components = c0_umap_grid$n_components,
      min_dist     = c0_umap_grid$min_dist
    ) |>
      dplyr::bind_cols(
        probe_umap_geometry(
          c0_umap_reduced_embeddings,
          dplyr::filter(c0_eval_gold_pairs, tier == 1L)
        )
      ),
    pattern  = map(c0_umap_reduced_embeddings, c0_umap_grid),
    packages = c("tidyverse")
  ),

  # FP32 mirror of the UMAP-space probe block above. Same UMAP grid, same
  # seed, same probe function — the only thing that differs from the F16
  # chain is the input embedding matrix, so the F16↔FP32 row contrast in
  # `fig-umap-separation-probe` is strictly about precision.
  tar_target(
    c0_umap_reduced_embeddings_fp32,
    umap_reduce_embeddings(
      c0_us_embeddings_fp32,
      n_neighbors  = c0_umap_grid$n_neighbors,
      n_components = c0_umap_grid$n_components,
      min_dist     = c0_umap_grid$min_dist,
      seed         = 20260526L
    ),
    pattern   = map(c0_umap_grid),
    iteration = "list",
    packages  = c("tidyverse", "uwot"),
    format    = "qs",
    resources = tar_resources(crew = tar_resources_crew(controller = "c0_umap"))
  ),

  tar_target(
    c0_hdbscan_umap_probe_fp32,
    tibble::tibble(
      n_neighbors  = c0_umap_grid$n_neighbors,
      n_components = c0_umap_grid$n_components,
      min_dist     = c0_umap_grid$min_dist
    ) |>
      dplyr::bind_cols(
        probe_umap_geometry(c0_umap_reduced_embeddings_fp32, c0_eval_gold_pairs)
      ),
    pattern  = map(c0_umap_reduced_embeddings_fp32, c0_umap_grid),
    packages = c("tidyverse")
  ),

  tar_target(
    c0_hdbscan_umap_probe_tier1_fp32,
    tibble::tibble(
      n_neighbors  = c0_umap_grid$n_neighbors,
      n_components = c0_umap_grid$n_components,
      min_dist     = c0_umap_grid$min_dist
    ) |>
      dplyr::bind_cols(
        probe_umap_geometry(
          c0_umap_reduced_embeddings_fp32,
          dplyr::filter(c0_eval_gold_pairs, tier == 1L)
        )
      ),
    pattern  = map(c0_umap_reduced_embeddings_fp32, c0_umap_grid),
    packages = c("tidyverse")
  ),

  tar_target(
    c0_f16_quantization_probe,
    probe_f16_quantization(c0_us_embeddings, c0_eval_gold_pairs),
    packages = "tidyverse"
  ),

  tar_target(
    c0_f16_quantization_probe_tier1,
    probe_f16_quantization(
      c0_us_embeddings,
      dplyr::filter(c0_eval_gold_pairs, tier == 1L)
    ),
    packages = "tidyverse"
  ),

  tar_target(
    c0_fp32_reference_probe,
    probe_f16_quantization(c0_us_embeddings_fp32, c0_eval_gold_pairs),
    packages = "tidyverse"
  ),

  tar_target(
    c0_fp32_reference_probe_tier1,
    probe_f16_quantization(
      c0_us_embeddings_fp32,
      dplyr::filter(c0_eval_gold_pairs, tier == 1L)
    ),
    packages = "tidyverse"
  ),

  # =========================================================================
  # C0 Phase A — RR-aligned evaluation framework
  # =========================================================================
  # Scores each Methods 1–3 clustering against R&R's 49-act list in
  # us_shocks.csv (independent of any pipeline output). Match gates: keyword
  # containment via generate_subcomponents() OR JW-min ≤ 0.30, AND year
  # within ±2 of the act's signing year. Replaces pairwise P/R/F1 + ARI as
  # the headline eval; the c0_*_metrics targets above stay wired for the
  # §"Why we pivoted away from pairwise P/R" trace subsection in the
  # notebook. See R/c0_aggregator.R for function-level docs and
  # `memory/c0_gold_pool_ceiling.md` for the rationale.

  tar_target(
    c0_us_rr_acts,
    build_us_rr_acts(us_shocks),
    packages = c("tidyverse", "lubridate")
  ),

  tar_target(
    c0_jw_rr_matches,
    match_clusters_to_rr_acts(c0_jw_clusters, c0_us_measure_pool,
                              c0_us_rr_acts),
    packages = c("tidyverse", "stringdist")
  ),

  tar_target(
    c0_jw_rr_metrics,
    evaluate_rr_matches_grid(c0_jw_rr_matches, c0_jw_clusters,
                             c0_us_rr_acts,
                             n_boot = 1000L, seed = 20260529L),
    packages = c("tidyverse", "withr")
  ),

  tar_target(
    c0_hdbscan_rr_matches,
    match_clusters_to_rr_acts(c0_hdbscan_clusters, c0_us_measure_pool,
                              c0_us_rr_acts),
    packages = c("tidyverse", "stringdist")
  ),

  tar_target(
    c0_hdbscan_rr_metrics,
    evaluate_rr_matches_grid(c0_hdbscan_rr_matches, c0_hdbscan_clusters,
                             c0_us_rr_acts,
                             n_boot = 1000L, seed = 20260529L),
    packages = c("tidyverse", "withr")
  ),

  # UMAP branches map over c0_umap_grid the same way as the existing
  # c0_hdbscan_umap_clusters / c0_hdbscan_umap_metrics targets do.
  tar_target(
    c0_hdbscan_umap_rr_matches,
    match_clusters_to_rr_acts(c0_hdbscan_umap_clusters, c0_us_measure_pool,
                              c0_us_rr_acts),
    pattern   = map(c0_hdbscan_umap_clusters),
    packages  = c("tidyverse", "stringdist"),
    resources = tar_resources(crew = tar_resources_crew(controller = "c0_umap"))
  ),

  tar_target(
    c0_hdbscan_umap_rr_metrics,
    evaluate_rr_matches_grid(c0_hdbscan_umap_rr_matches,
                             c0_hdbscan_umap_clusters, c0_us_rr_acts,
                             n_boot = 1000L, seed = 20260529L),
    pattern   = map(c0_hdbscan_umap_rr_matches, c0_hdbscan_umap_clusters),
    packages  = c("tidyverse", "withr"),
    resources = tar_resources(crew = tar_resources_crew(controller = "c0_umap"))
  ),

  # Method 5: LLM canonical clustering. Bespoke prompt (NOT an H&K
  # classification codebook); emits the same cluster-table contract as JW /
  # HDBSCAN so it reuses match_clusters_to_rr_acts + evaluate_rr_matches_grid.
  # c0_m5_clusters is the only API-calling C0 target (Haiku, single-shot,
  # 5 shuffle seeds for the order-sensitivity probe).
  tar_target(
    c0_m5_prompt_file,
    here::here("prompts", "c0_canonicalize.yml"),
    format = "file",
    packages = "here"
  ),
  tar_target(
    c0_m5_prompt,
    yaml::read_yaml(c0_m5_prompt_file),
    packages = "yaml"
  ),
  tar_target(
    c0_m5_clusters,
    run_m5_llm_clusters(
      c0_us_measure_pool,
      model       = "claude-haiku-4-5-20251001",
      instruction = c0_m5_prompt$instruction,
      max_tokens  = 8192,
      provider    = "anthropic",
      base_url    = "https://api.anthropic.com/v1",
      api_key     = Sys.getenv("ANTHROPIC_API_KEY"),
      seeds       = 1:5
    ),
    packages   = c("tidyverse", "httr2", "jsonlite", "withr"),
    deployment = "main"
  ),
  tar_target(
    c0_m5_rr_matches,
    match_clusters_to_rr_acts(c0_m5_clusters, c0_us_measure_pool,
                              c0_us_rr_acts),
    packages = c("tidyverse", "stringdist")
  ),
  tar_target(
    c0_m5_rr_metrics,
    evaluate_rr_matches_grid(c0_m5_rr_matches, c0_m5_clusters,
                             c0_us_rr_acts,
                             n_boot = 1000L, seed = 20260529L),
    packages = c("tidyverse", "withr")
  ),

  tar_quarto(
    c0_aggregator,
    path = here("notebooks/c0_aggregator.qmd"),
    cache = FALSE
  )


)
