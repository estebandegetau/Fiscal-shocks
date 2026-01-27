# Self-Consistency Functions for LLM Classification
# Implements self-consistency (Wang et al., 2022) for improved calibration
# Key idea: Sample multiple responses with temperature > 0, majority vote for final answer

#' Call Claude API with self-consistency sampling
#'
#' Samples n_samples responses with temperature > 0, parses each, and returns
#' majority vote prediction with agreement rate as uncertainty measure.
#'
#' @param messages List of message objects with role and content
#' @param model Character string for model ID
#' @param n_samples Integer number of samples to draw (default 5)
#' @param temperature Numeric sampling temperature (default 0.7)
#' @param max_tokens Integer for max output tokens
#' @param parse_fn Function to parse API response text to structured result
#' @param extract_class_fn Function to extract classification from parsed result
#' @param max_retries Integer for number of retry attempts per call
#' @param system Optional system prompt string
#'
#' @return List with:
#'   - prediction: Majority vote prediction
#'   - agreement_rate: Proportion of samples agreeing with majority
#'   - all_predictions: Vector of all sampled predictions
#'   - all_results: List of all parsed results
#'   - confidence: Calibrated confidence (agreement_rate)
#' @export
call_with_self_consistency <- function(messages,
                                       model = "claude-sonnet-4-20250514",
                                       n_samples = 5,
                                       temperature = 0.7,
                                       max_tokens = 1000,
                                       parse_fn,
                                       extract_class_fn,
                                       max_retries = 3,
                                       system = NULL) {

  # Collect all samples
  all_results <- vector("list", n_samples)
  all_predictions <- character(n_samples)

  for (i in seq_len(n_samples)) {
    # Call API with temperature > 0 for diversity
    response <- call_claude_api(
      messages = messages,
      model = model,
      max_tokens = max_tokens,
      temperature = temperature,
      max_retries = max_retries,
      system = system
    )

    # Parse response
    parsed <- tryCatch({
      parse_fn(response$content[[1]]$text)
    }, error = function(e) {
      warning("Sample ", i, " parse failed: ", e$message)
      list(error = e$message)
    })

    all_results[[i]] <- parsed

    # Extract classification
    all_predictions[i] <- tryCatch({
      extract_class_fn(parsed)
    }, error = function(e) {
      NA_character_
    })
  }

  # Compute majority vote
  valid_predictions <- all_predictions[!is.na(all_predictions)]

  if (length(valid_predictions) == 0) {
    return(list(
      prediction = NA_character_,
      agreement_rate = 0,
      all_predictions = all_predictions,
      all_results = all_results,
      confidence = 0
    ))
  }

  # Count occurrences
  prediction_counts <- table(valid_predictions)
  majority_prediction <- names(prediction_counts)[which.max(prediction_counts)]
  agreement_rate <- max(prediction_counts) / length(valid_predictions)

  list(
    prediction = majority_prediction,
    agreement_rate = agreement_rate,
    all_predictions = all_predictions,
    all_results = all_results,
    confidence = agreement_rate  # Use agreement rate as calibrated confidence
  )
}


#' Self-consistency for Model A (binary classification)
#'
#' Wrapper for call_with_self_consistency with Model A specific parsing.
#'
#' @param text Character string with passage text to classify
#' @param model Character string for Claude model ID
#' @param n_samples Integer number of samples (default 5)
#' @param temperature Numeric sampling temperature (default 0.7)
#' @param examples List of few-shot examples
#' @param system_prompt Character string for system prompt
#'
#' @return List with prediction, agreement_rate, and detailed results
#' @export
model_a_with_self_consistency <- function(text,
                                          model = "claude-sonnet-4-20250514",
                                          n_samples = 5,
                                          temperature = 0.7,
                                          examples = NULL,
                                          system_prompt = NULL) {

  # Load system prompt if not provided
  if (is.null(system_prompt)) {
    system_prompt_file <- here::here("prompts", "model_a_system.txt")
    if (!file.exists(system_prompt_file)) {
      stop("System prompt file not found: ", system_prompt_file)
    }
    system_prompt <- readr::read_file(system_prompt_file)
  }

  # Load examples if not provided
  if (is.null(examples)) {
    examples_file <- here::here("prompts", "model_a_examples.json")
    if (file.exists(examples_file)) {
      examples <- jsonlite::fromJSON(examples_file, simplifyVector = FALSE)
    } else {
      examples <- NULL
    }
  }

  # Format prompt
  full_prompt <- format_few_shot_prompt(
    system = system_prompt,
    examples = examples,
    user_input = text
  )

  # Define parsing functions
  parse_fn <- function(response_text) {
    parse_json_response(
      response_text,
      required_fields = c("contains_act", "confidence", "reasoning")
    )
  }

  extract_class_fn <- function(parsed) {
    if (!is.null(parsed$contains_act)) {
      as.character(parsed$contains_act)
    } else {
      NA_character_
    }
  }

  # Call with self-consistency
  result <- call_with_self_consistency(
    messages = list(list(role = "user", content = full_prompt)),
    model = model,
    n_samples = n_samples,
    temperature = temperature,
    max_tokens = 500,
    parse_fn = parse_fn,
    extract_class_fn = extract_class_fn
  )

  # Format for Model A output
  list(
    contains_act = as.logical(result$prediction),
    act_name = aggregate_act_names(result$all_results),
    confidence = result$confidence,
    agreement_rate = result$agreement_rate,
    reasoning = aggregate_reasoning(result$all_results),
    n_samples = n_samples,
    all_predictions = result$all_predictions
  )
}


#' Self-consistency for Model B (4-class classification)
#'
#' Wrapper for call_with_self_consistency with Model B specific parsing.
#'
#' @param act_name Character string with act name
#' @param passages_text Character string with concatenated passages
#' @param year Integer year of act
#' @param model Character string for Claude model ID
#' @param n_samples Integer number of samples (default 5)
#' @param temperature Numeric sampling temperature (default 0.7)
#' @param examples List of few-shot examples
#' @param system_prompt Character string for system prompt
#'
#' @return List with prediction, agreement_rate, and detailed results
#' @export
model_b_with_self_consistency <- function(act_name,
                                          passages_text,
                                          year,
                                          model = "claude-sonnet-4-20250514",
                                          n_samples = 5,
                                          temperature = 0.7,
                                          examples = NULL,
                                          system_prompt = NULL) {

  # Load system prompt if not provided
  if (is.null(system_prompt)) {
    system_prompt_file <- here::here("prompts", "model_b_system.txt")
    if (!file.exists(system_prompt_file)) {
      stop("System prompt file not found: ", system_prompt_file)
    }
    system_prompt <- readr::read_file(system_prompt_file)
  }

  # Load examples if not provided
  if (is.null(examples)) {
    examples_file <- here::here("prompts", "model_b_examples.json")
    if (file.exists(examples_file)) {
      examples <- jsonlite::fromJSON(examples_file, simplifyVector = FALSE)
    } else {
      examples <- NULL
    }
  }

  # Format input
  user_input <- glue::glue("
ACT: {act_name}
YEAR: {year}

PASSAGES FROM ORIGINAL SOURCES:
{passages_text}

Classify this act's PRIMARY motivation.
  ")

  # Format prompt
  full_prompt <- format_few_shot_prompt(
    system = system_prompt,
    examples = examples,
    user_input = user_input
  )

  # Define parsing functions
  parse_fn <- function(response_text) {
    parse_json_response(
      response_text,
      required_fields = c("motivation", "exogenous", "confidence", "reasoning")
    )
  }

  extract_class_fn <- function(parsed) {
    if (!is.null(parsed$motivation)) {
      as.character(parsed$motivation)
    } else {
      NA_character_
    }
  }

  # Call with self-consistency
  result <- call_with_self_consistency(
    messages = list(list(role = "user", content = full_prompt)),
    model = model,
    n_samples = n_samples,
    temperature = temperature,
    max_tokens = 1000,
    parse_fn = parse_fn,
    extract_class_fn = extract_class_fn
  )

  # Determine exogenous based on majority motivation
  exogenous <- if (!is.na(result$prediction)) {
    result$prediction %in% c("Long-run", "Deficit-driven")
  } else {
    NA
  }

  # Format for Model B output
  list(
    motivation = result$prediction,
    exogenous = exogenous,
    confidence = result$confidence,
    agreement_rate = result$agreement_rate,
    evidence = aggregate_evidence(result$all_results),
    reasoning = aggregate_reasoning(result$all_results),
    n_samples = n_samples,
    all_predictions = result$all_predictions
  )
}


#' Self-consistency for Model C (numeric extraction)
#'
#' For numeric values (magnitude), uses median instead of majority vote.
#'
#' @param act_name Character string with act name
#' @param passages_text Character string with concatenated passages
#' @param date_signed Character or Date, act signing date
#' @param tables Optional list of tables
#' @param model Character string for Claude model ID
#' @param n_samples Integer number of samples (default 5)
#' @param temperature Numeric sampling temperature (default 0.7)
#' @param examples List of few-shot examples
#' @param system_prompt Character string for system prompt
#'
#' @return List with aggregated predictions
#' @export
model_c_with_self_consistency <- function(act_name,
                                          passages_text,
                                          date_signed,
                                          tables = NULL,
                                          model = "claude-sonnet-4-20250514",
                                          n_samples = 5,
                                          temperature = 0.7,
                                          examples = NULL,
                                          system_prompt = NULL) {

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
      examples <- NULL
    }
  }

  # Format date_signed
  if (inherits(date_signed, "Date")) {
    date_str <- format(date_signed, "%Y-%m-%d")
  } else {
    date_str <- as.character(date_signed)
  }

  # Format input
  user_input <- glue::glue("
ACT: {act_name}
DATE SIGNED: {date_str}

PASSAGES FROM ORIGINAL SOURCES:
{passages_text}

Extract ALL implementation phases with timing, magnitude, and present value.
  ")

  # Format prompt
  full_prompt <- format_few_shot_prompt(
    system = system_prompt,
    examples = examples,
    user_input = user_input
  )

  # Collect samples
  all_results <- vector("list", n_samples)

  for (i in seq_len(n_samples)) {
    response <- call_claude_api(
      messages = list(list(role = "user", content = full_prompt)),
      model = model,
      max_tokens = 2000,
      temperature = temperature
    )

    all_results[[i]] <- tryCatch({
      parse_json_response(
        response$content[[1]]$text,
        required_fields = c("changes", "reasoning")
      )
    }, error = function(e) {
      list(error = e$message, changes = list())
    })
  }

  # Aggregate quarters using median for magnitudes, mode for timing
  aggregated_quarters <- aggregate_model_c_results(all_results)

  list(
    act_name = act_name,
    predicted_quarters = aggregated_quarters,
    reasoning = aggregate_reasoning(all_results),
    n_samples = n_samples,
    all_results = all_results
  )
}


# Helper functions for aggregation -------------------------------------------

#' Aggregate act names from multiple samples (Model A)
#' @param results List of parsed results
#' @return Most common act name
aggregate_act_names <- function(results) {
  act_names <- sapply(results, function(r) {
    if (!is.null(r$act_name)) {
      if (is.list(r$act_name)) {
        if (length(r$act_name) > 0) as.character(r$act_name[[1]]) else NA_character_
      } else {
        as.character(r$act_name)
      }
    } else {
      NA_character_
    }
  })

  valid_names <- act_names[!is.na(act_names)]
  if (length(valid_names) == 0) return(NA_character_)

  # Return most common
  name_counts <- table(valid_names)
  names(name_counts)[which.max(name_counts)]
}


#' Aggregate reasoning from multiple samples
#' @param results List of parsed results
#' @return First valid reasoning string
aggregate_reasoning <- function(results) {
  for (r in results) {
    if (!is.null(r$reasoning) && !is.na(r$reasoning)) {
      return(r$reasoning)
    }
  }
  NA_character_
}


#' Aggregate evidence from multiple samples (Model B)
#' @param results List of parsed results
#' @return First valid evidence list
aggregate_evidence <- function(results) {
  for (r in results) {
    if (!is.null(r$evidence) && length(r$evidence) > 0) {
      return(r$evidence)
    }
  }
  list()
}


#' Aggregate Model C results using median for magnitudes
#' @param results List of parsed results
#' @return Tibble with aggregated quarters
aggregate_model_c_results <- function(results) {

  # Extract all changes from all samples
  all_changes <- list()
  for (r in results) {
    if (!is.null(r$changes) && length(r$changes) > 0) {
      all_changes <- c(all_changes, r$changes)
    }
  }

  if (length(all_changes) == 0) {
    return(tibble::tibble(
      timing_quarter = character(0),
      magnitude_billions = numeric(0),
      present_value_quarter = character(0),
      present_value_billions = numeric(0),
      confidence = numeric(0),
      source = character(0)
    ))
  }

  # Group by timing_quarter and take median magnitude
  changes_df <- purrr::map_dfr(all_changes, function(change) {
    tibble::tibble(
      timing_quarter = change$timing_quarter %||% NA_character_,
      magnitude_billions = change$magnitude_billions %||% NA_real_,
      present_value_quarter = change$present_value_quarter %||% NA_character_,
      present_value_billions = change$present_value_billions %||% NA_real_,
      confidence = change$confidence %||% NA_real_,
      source = change$source %||% NA_character_
    )
  })

  # Group by timing and aggregate
  changes_df |>
    dplyr::filter(!is.na(timing_quarter)) |>
    dplyr::group_by(timing_quarter) |>
    dplyr::summarize(
      magnitude_billions = stats::median(magnitude_billions, na.rm = TRUE),
      present_value_quarter = dplyr::first(present_value_quarter[!is.na(present_value_quarter)]),
      present_value_billions = stats::median(present_value_billions, na.rm = TRUE),
      confidence = mean(confidence, na.rm = TRUE),
      source = dplyr::first(source[!is.na(source)]),
      n_samples_agree = dplyr::n(),
      .groups = "drop"
    )
}


# Null coalescing operator (if not already defined)
if (!exists("%||%")) {
  `%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }
}
