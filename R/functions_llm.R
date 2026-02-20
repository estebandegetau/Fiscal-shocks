# LLM Utilities for Phase 0 Models
# Shared functions for calling Claude API and processing responses

#' Call Claude API with retry logic and rate limiting
#'
#' @param messages List of message objects with role and content
#' @param model Character string for model ID (default: claude-3-5-sonnet-20241022)
#' @param max_tokens Integer for max output tokens
#' @param temperature Numeric 0-1 for sampling temperature
#' @param max_retries Integer for number of retry attempts
#' @param system Optional system prompt string
#'
#' @return List with response content and metadata
#' @export
call_claude_api <- function(messages,
                            model = "claude-3-5-sonnet-20241022",
                            max_tokens = 1000,
                            temperature = 0.0,
                            max_retries = 3,
                            system = NULL) {

  # Check for API key
  api_key <- Sys.getenv("ANTHROPIC_API_KEY")
  if (api_key == "") {
    stop("ANTHROPIC_API_KEY not found in environment. Set it in .env file.")
  }

  # Build request body
  body <- list(
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
    messages = messages
  )

  # Add system prompt if provided
  if (!is.null(system)) {
    body$system <- system
  }

  # Retry loop with exponential backoff
  for (attempt in seq_len(max_retries)) {
    tryCatch({
      # Rate limiting: Conservative 30 RPM = 2s between calls
      # (Tier 1 limit is 50 RPM, but safer to be conservative)
      Sys.sleep(2)

      # Make API request with detailed error handling
      response <- httr2::request("https://api.anthropic.com/v1/messages") |>
        httr2::req_headers(
          `x-api-key` = api_key,
          `anthropic-version` = "2023-06-01",
          `content-type` = "application/json"
        ) |>
        httr2::req_body_json(body) |>
        httr2::req_error(body = function(resp) {
          # Extract detailed error message from API response
          error_body <- httr2::resp_body_json(resp)
          if (!is.null(error_body$error$message)) {
            error_body$error$message
          } else {
            paste("HTTP", httr2::resp_status(resp), httr2::resp_status_desc(resp))
          }
        }) |>
        httr2::req_retry(max_tries = 1) |>
        httr2::req_perform()

      # Parse response
      result <- httr2::resp_body_json(response)

      # Log API call
      log_api_call(
        model = model,
        input_tokens = result$usage$input_tokens,
        output_tokens = result$usage$output_tokens,
        timestamp = Sys.time()
      )

      return(result)

    }, error = function(e) {
      if (attempt == max_retries) {
        # Log error
        log_api_error(
          model = model,
          error = e$message,
          timestamp = Sys.time()
        )
        stop("API call failed after ", max_retries, " attempts: ", e$message)
      }

      # Special handling for rate limit errors (429)
      if (grepl("429|Too Many Requests", e$message)) {
        wait_time <- 60  # Wait 60 seconds for rate limit
        message("Rate limit hit (attempt ", attempt, "/", max_retries,
                "), waiting ", wait_time, "s...")
      } else {
        # Exponential backoff for other errors: 2s, 4s, 8s
        wait_time <- 2^attempt
        message("API error (attempt ", attempt, "/", max_retries,
                "), retrying in ", wait_time, "s...")
      }
      message("Error: ", e$message)
      Sys.sleep(wait_time)
    })
  }
}


#' Format few-shot prompt with system instructions, examples, and user input
#'
#' @param system Character string with system prompt
#' @param examples List or NULL - if provided, list of examples with input/output
#' @param user_input Character string with current input to process
#'
#' @return Character string with formatted prompt
#' @export
format_few_shot_prompt <- function(system, examples = NULL, user_input) {

  # Start with system prompt
  prompt_parts <- c(system, "\n\n")

  # Add examples if provided
  if (!is.null(examples) && length(examples) > 0) {
    prompt_parts <- c(prompt_parts, "# Examples\n\n")

    for (i in seq_along(examples)) {
      ex <- examples[[i]]
      prompt_parts <- c(
        prompt_parts,
        sprintf("Example %d:\n", i),
        "Input:\n",
        ex$input,
        "\n\nOutput:\n",
        jsonlite::toJSON(ex$output, auto_unbox = TRUE, pretty = TRUE),
        "\n\n"
      )
    }
  }

  # Add current task
  prompt_parts <- c(
    prompt_parts,
    "# Your Task\n\n",
    "Now analyze this passage:\n\n",
    "Input:\n",
    user_input,
    "\n\nOutput:\n"
  )

  paste(prompt_parts, collapse = "")
}


#' Parse JSON response from Claude API
#'
#' Extracts JSON from markdown code blocks and validates structure
#'
#' @param response_text Character string with API response
#' @param required_fields Character vector of required field names (optional)
#'
#' @return List with parsed JSON or tibble row
#' @export
parse_json_response <- function(response_text, required_fields = NULL) {

  # Extract JSON from markdown code blocks if present
  json_pattern <- "```json\\s*\\n(.+?)\\n```"
  json_match <- stringr::str_match(response_text, stringr::regex(json_pattern, dotall = TRUE))

  if (!is.na(json_match[1, 2])) {
    # Found JSON in code block
    json_str <- json_match[1, 2]
  } else {
    # Try to find raw JSON (starting with { or [)
    json_str <- response_text
  }

  # Parse JSON
  tryCatch({
    result <- jsonlite::fromJSON(json_str, simplifyVector = FALSE)

    # Validate required fields if specified
    if (!is.null(required_fields)) {
      missing <- setdiff(required_fields, names(result))
      if (length(missing) > 0) {
        warning("Missing required fields: ", paste(missing, collapse = ", "))
      }
    }

    return(result)

  }, error = function(e) {
    warning("Failed to parse JSON response: ", e$message)
    warning("Response text: ", substr(response_text, 1, 200))
    return(list(error = "JSON parsing failed", raw_response = response_text))
  })
}


#' Log API call to CSV file
#'
#' @param model Character string for model ID
#' @param input_tokens Integer
#' @param output_tokens Integer
#' @param timestamp POSIXct timestamp
#'
#' @return NULL (side effect: appends to logs/api_calls.csv)
#' @export
log_api_call <- function(model, input_tokens, output_tokens, timestamp) {

  # Calculate cost (Claude 3.5 Sonnet pricing as of 2024)
  # Input: $0.003 per 1K tokens
  # Output: $0.015 per 1K tokens
  cost_usd <- (input_tokens / 1000 * 0.003) + (output_tokens / 1000 * 0.015)

  log_entry <- tibble::tibble(
    timestamp = timestamp,
    model = model,
    input_tokens = input_tokens,
    output_tokens = output_tokens,
    cost_usd = cost_usd
  )

  log_file <- here::here("logs", "api_calls.csv")

  # Create logs directory if needed
  if (!dir.exists(here::here("logs"))) {
    dir.create(here::here("logs"), recursive = TRUE)
  }

  # Append to CSV
  if (file.exists(log_file)) {
    readr::write_csv(log_entry, log_file, append = TRUE)
  } else {
    readr::write_csv(log_entry, log_file, append = FALSE)
  }

  invisible(NULL)
}


#' Log API error to log file
#'
#' @param model Character string for model ID
#' @param error Character string with error message
#' @param timestamp POSIXct timestamp
#'
#' @return NULL (side effect: appends to logs/api_errors.log)
#' @export
log_api_error <- function(model, error, timestamp) {

  log_entry <- sprintf(
    "[%s] Model: %s | Error: %s\n",
    format(timestamp, "%Y-%m-%d %H:%M:%S"),
    model,
    error
  )

  log_file <- here::here("logs", "api_errors.log")

  # Create logs directory if needed
  if (!dir.exists(here::here("logs"))) {
    dir.create(here::here("logs"), recursive = TRUE)
  }

  # Append to log
  cat(log_entry, file = log_file, append = TRUE)

  invisible(NULL)
}


#' Get total API cost from log file
#'
#' @return Tibble with cost summary by model
#' @export
get_api_cost_summary <- function() {
  log_file <- here::here("logs", "api_calls.csv")

  if (!file.exists(log_file)) {
    message("No API calls logged yet.")
    return(tibble::tibble(
      model = character(),
      n_calls = integer(),
      total_cost_usd = numeric()
    ))
  }

  readr::read_csv(log_file, show_col_types = FALSE) |>
    dplyr::group_by(model) |>
    dplyr::summarize(
      n_calls = dplyr::n(),
      total_input_tokens = sum(input_tokens),
      total_output_tokens = sum(output_tokens),
      total_cost_usd = sum(cost_usd),
      .groups = "drop"
    )
}
