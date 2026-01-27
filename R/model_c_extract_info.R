# Model C: Multi-Quarter Information Extraction
# Extracts timing, magnitude, and present value for ALL implementation phases of fiscal acts

#' Extract fiscal impact information from act passages using Claude API
#'
#' @param act_name Character string with act name
#' @param passages_text Character string with concatenated passages describing the act
#' @param date_signed Character or Date, act signing date
#' @param tables Optional list of tables (not yet implemented)
#' @param model Character string for Claude model ID
#' @param examples List of few-shot examples (optional, loaded from JSON if NULL)
#' @param system_prompt Character string for system prompt (optional, loaded from file if NULL)
#' @param use_self_consistency Logical, use self-consistency sampling (default TRUE)
#' @param n_samples Integer number of samples for self-consistency (default 5)
#' @param temperature Numeric sampling temperature (default 0.7 for self-consistency)
#'
#' @return Tibble with nested predictions (one row with predicted_quarters list-column)
#' @export
model_c_extract_info <- function(act_name,
                                 passages_text,
                                 date_signed,
                                 tables = NULL,
                                 model = "claude-sonnet-4-20250514",
                                 examples = NULL,
                                 system_prompt = NULL,
                                 use_self_consistency = TRUE,
                                 n_samples = 5,
                                 temperature = 0.7) {

  # Load system prompt if not provided
  if (is.null(system_prompt)) {
    system_prompt_file <- here::here("prompts", "model_c_system.txt")
    if (!file.exists(system_prompt_file)) {
      stop("System prompt file not found: ", system_prompt_file)
    }
    system_prompt <- readr::read_file(system_prompt_file)
  }

  # Load examples if not provided
  if (is.null(examples)) {
    examples_file <- here::here("prompts", "model_c_examples.json")
    if (file.exists(examples_file)) {
      examples <- jsonlite::fromJSON(examples_file, simplifyVector = FALSE)
    } else {
      warning("No few-shot examples found at: ", examples_file)
      examples <- NULL
    }
  }

  # Format date_signed
  if (inherits(date_signed, "Date")) {
    date_str <- format(date_signed, "%Y-%m-%d")
  } else {
    date_str <- as.character(date_signed)
  }

  # Format input with act context
  # Note: tables support can be added later
  if (!is.null(tables) && length(tables) > 0) {
    tables_text <- "\n\nTABLES:\n"
    for (i in seq_along(tables)) {
      tables_text <- paste0(
        tables_text,
        sprintf("Table %d: %s\n", i, jsonlite::toJSON(tables[[i]], auto_unbox = TRUE, pretty = TRUE)),
        "\n"
      )
    }
  } else {
    tables_text <- ""
  }

  user_input <- glue::glue("
ACT: {act_name}
DATE SIGNED: {date_str}

PASSAGES FROM ORIGINAL SOURCES:
{passages_text}{tables_text}

Extract ALL implementation phases with timing, magnitude, and present value.
  ")

  # Use self-consistency if enabled
  if (use_self_consistency) {
    # Use self-consistency wrapper (with median aggregation for numeric values)
    sc_result <- model_c_with_self_consistency(
      act_name = act_name,
      passages_text = passages_text,
      date_signed = date_signed,
      tables = tables,
      model = model,
      n_samples = n_samples,
      temperature = temperature,
      examples = examples,
      system_prompt = system_prompt
    )

    # Return as single-row tibble with self-consistency results
    return(tibble::tibble(
      act_name = act_name,
      prediction_json = jsonlite::toJSON(sc_result$all_results, auto_unbox = TRUE),
      predicted_quarters = list(sc_result$predicted_quarters),
      reasoning = sc_result$reasoning %||% NA_character_
    ))
  }

  # Standard single-shot extraction (temperature = 0)
  # Format prompt with few-shot examples
  full_prompt <- format_few_shot_prompt(
    system = system_prompt,
    examples = examples,
    user_input = user_input
  )

  # Call Claude API
  response <- call_claude_api(
    messages = list(list(role = "user", content = full_prompt)),
    model = model,
    max_tokens = 2000,  # Longer for multi-quarter extraction
    temperature = 0.0  # Deterministic
  )

  # Parse JSON response
  result <- parse_json_response(
    response$content[[1]]$text,
    required_fields = c("changes", "reasoning")
  )

  # Parse into tibble with nested quarters
  predicted_quarters <- parse_model_c_output(result)

  # Return as single-row tibble
  tibble::tibble(
    act_name = act_name,
    prediction_json = jsonlite::toJSON(result, auto_unbox = TRUE),
    predicted_quarters = list(predicted_quarters),
    reasoning = result$reasoning %||% NA_character_
  )
}


#' Parse Model C output into nested tibble format
#'
#' Converts the JSON output with changes array into a tibble with one row per quarter
#'
#' @param result List from parse_json_response() with changes and reasoning
#'
#' @return Tibble with one row per extracted quarter
#' @export
parse_model_c_output <- function(result) {

  # Handle errors or missing changes
  if (is.null(result$changes) || length(result$changes) == 0) {
    return(tibble::tibble(
      timing_quarter = character(0),
      magnitude_billions = numeric(0),
      present_value_quarter = character(0),
      present_value_billions = numeric(0),
      confidence = numeric(0),
      source = character(0)
    ))
  }

  # Convert changes array to tibble
  purrr::map_dfr(result$changes, function(change) {
    tibble::tibble(
      timing_quarter = change$timing_quarter %||% NA_character_,
      magnitude_billions = change$magnitude_billions %||% NA_real_,
      present_value_quarter = change$present_value_quarter %||% NA_character_,
      present_value_billions = change$present_value_billions %||% NA_real_,
      confidence = change$confidence %||% NA_real_,
      source = change$source %||% NA_character_
    )
  })
}


#' Run Model C extraction on batch of acts
#'
#' @param training_data Tibble with act_name, passages_text, date_signed, ground_truth_quarters, split
#' @param model Character string for Claude model ID
#' @param show_progress Logical, show progress bar (default TRUE)
#' @param use_self_consistency Logical, use self-consistency sampling (default TRUE)
#' @param n_samples Integer number of samples for self-consistency (default 5)
#' @param temperature Numeric sampling temperature (default 0.7 for self-consistency)
#'
#' @return Tibble with predictions joined to ground truth
#' @export
model_c_extract_batch <- function(training_data,
                                   model = "claude-sonnet-4-20250514",
                                   show_progress = TRUE,
                                   use_self_consistency = TRUE,
                                   n_samples = 5,
                                   temperature = 0.7) {

  # Set up progress bar if requested
  if (show_progress) {
    pb <- progress::progress_bar$new(
      format = "  Processing [:bar] :percent eta: :eta",
      total = nrow(training_data)
    )
  }

  # Run extraction on each act with error handling
  predictions <- purrr::pmap_dfr(
    list(
      training_data$act_name,
      training_data$passages_text,
      training_data$date_signed
    ),
    function(act_name, passages_text, date_signed) {
      if (show_progress) pb$tick()

      tryCatch({
        model_c_extract_info(
          act_name = act_name,
          passages_text = passages_text,
          date_signed = date_signed,
          model = model,
          use_self_consistency = use_self_consistency,
          n_samples = n_samples,
          temperature = temperature
        )
      }, error = function(e) {
        warning("Failed to extract for ", act_name, ": ", e$message)
        tibble::tibble(
          act_name = act_name,
          prediction_json = NA_character_,
          predicted_quarters = list(tibble::tibble()),
          reasoning = paste("ERROR:", e$message)
        )
      })
    }
  )

  # Join predictions with ground truth
  training_data |>
    dplyr::select(act_name, ground_truth_quarters, split) |>
    dplyr::left_join(predictions, by = "act_name")
}


# Helper: null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
