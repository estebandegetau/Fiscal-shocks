# LLM Utilities for Phase 0 Models
# Shared functions for calling Claude API and processing responses

#' Call Claude API with retry logic and rate limiting
#'
#' @param messages List of message objects with role and content
#' @param model Character string for model ID (default: claude-sonnet-4-5-20250514)
#' @param max_tokens Integer for max output tokens
#' @param temperature Numeric 0-1 for sampling temperature
#' @param max_retries Integer for number of retry attempts (default 10 for long pipelines)
#' @param system Optional system prompt string
#'
#' @return List with response content and metadata
#' @export
call_claude_api <- function(messages,
                            model = "claude-sonnet-4-5-20250514",
                            max_tokens = 1000,
                            temperature = 0.0,
                            max_retries = 10,
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

      # Log API call (include cache token fields from response)
      log_api_call(
        model = model,
        input_tokens = result$usage$input_tokens,
        output_tokens = result$usage$output_tokens,
        cache_creation_input_tokens = result$usage$cache_creation_input_tokens %||% 0L,
        cache_read_input_tokens = result$usage$cache_read_input_tokens %||% 0L,
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
      } else if (grepl("529|overloaded", e$message, ignore.case = TRUE)) {
        wait_time <- 60  # Server overloaded needs long backoff
        message("Server overloaded (attempt ", attempt, "/", max_retries,
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


#' Call OpenAI-compatible API with retry logic
#'
#' Works with OpenAI, Ollama, Groq, and any OpenAI-compatible endpoint.
#' Normalizes response to Anthropic shape so all downstream consumers work as-is.
#'
#' @param messages List of message objects with role and content
#' @param model Character string for model ID
#' @param max_tokens Integer for max output tokens
#' @param temperature Numeric 0-1 for sampling temperature
#' @param max_retries Integer for number of retry attempts
#' @param system Optional system prompt string
#' @param base_url Character base URL for the API (e.g., "http://localhost:11434/v1")
#' @param api_key Character API key (NULL for local models like Ollama)
#'
#' @return List normalized to Anthropic shape ($content[[1]]$text, $usage)
#' @export
call_openai_api <- function(messages,
                            model,
                            max_tokens = 1000,
                            temperature = 0.0,
                            max_retries = 10,
                            system = NULL,
                            base_url = "http://localhost:11434/v1",
                            api_key = NULL) {

  # Prepend system message (OpenAI convention)
  api_messages <- list()
  if (!is.null(system)) {
    # Flatten content block arrays (from cache path) to plain strings
    sys_text <- if (is.list(system) && length(system) > 0 && is.list(system[[1]])) {
      paste(vapply(system, function(b) b$text %||% "", character(1)),
            collapse = "\n\n")
    } else {
      as.character(system)
    }
    api_messages <- list(list(role = "system", content = sys_text))
  }

  # Flatten user message content blocks to plain strings
  for (msg in messages) {
    content <- msg$content
    if (is.list(content) && length(content) > 0 && is.list(content[[1]])) {
      content <- paste(vapply(content, function(b) b$text %||% "", character(1)),
                       collapse = "\n\n")
    }
    api_messages <- c(api_messages, list(list(role = msg$role, content = content)))
  }

  body <- list(
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
    messages = api_messages
  )

  url <- paste0(sub("/+$", "", base_url), "/chat/completions")

  for (attempt in seq_len(max_retries)) {
    tryCatch({
      req <- httr2::request(url) |>
        httr2::req_headers(`content-type` = "application/json") |>
        httr2::req_body_json(body) |>
        httr2::req_retry(max_tries = 1)

      # Add auth header if API key is provided
      if (!is.null(api_key) && nchar(api_key) > 0) {
        req <- req |>
          httr2::req_headers(Authorization = paste("Bearer", api_key))
      }

      # Add OpenRouter-required headers
      if (grepl("openrouter\\.ai", url)) {
        req <- req |>
          httr2::req_headers(
            `HTTP-Referer` = "https://github.com/estebandegetau/Fiscal-shocks",
            `X-Title` = "Fiscal-Shocks"
          )
      }

      response <- httr2::req_perform(req)
      result <- httr2::resp_body_json(response)

      # Normalize to Anthropic response shape
      finish_reason <- result$choices[[1]]$finish_reason %||% "stop"
      normalized <- list(
        content = list(list(
          type = "text",
          text = result$choices[[1]]$message$content
        )),
        stop_reason = switch(
          finish_reason,
          "stop"           = "end_turn",
          "length"         = "max_tokens",
          "content_filter" = "content_filter",
          "end_turn"
        ),
        usage = list(
          input_tokens = result$usage$prompt_tokens %||% 0L,
          output_tokens = result$usage$completion_tokens %||% 0L,
          cache_creation_input_tokens = 0L,
          cache_read_input_tokens = 0L
        )
      )

      # Log API call
      log_api_call(
        model = model,
        input_tokens = normalized$usage$input_tokens,
        output_tokens = normalized$usage$output_tokens,
        cache_creation_input_tokens = 0L,
        cache_read_input_tokens = 0L,
        timestamp = Sys.time()
      )

      return(normalized)

    }, error = function(e) {
      if (attempt == max_retries) {
        log_api_error(model = model, error = e$message, timestamp = Sys.time())
        stop("API call failed after ", max_retries, " attempts: ", e$message)
      }

      if (grepl("429|Too Many Requests", e$message)) {
        wait_time <- 60
        message("Rate limit hit (attempt ", attempt, "/", max_retries,
                "), waiting ", wait_time, "s...")
      } else {
        wait_time <- 2^attempt
        message("API error (attempt ", attempt, "/", max_retries,
                "), retrying in ", wait_time, "s...")
      }
      message("Error: ", e$message)
      Sys.sleep(wait_time)
    })
  }
}


#' Route LLM calls to the appropriate provider backend
#'
#' Dispatches to call_claude_api() or call_openai_api() based on provider string.
#' Default base_url and api_key are resolved per provider when NULL.
#'
#' @param messages List of message objects with role and content
#' @param model Character string for model ID
#' @param max_tokens Integer for max output tokens
#' @param temperature Numeric 0-1 for sampling temperature
#' @param max_retries Integer for number of retry attempts
#' @param system Optional system prompt string
#' @param provider Character: "anthropic", "ollama", "openai", "groq", or "openrouter"
#' @param base_url Character base URL override (NULL = per-provider default)
#' @param api_key Character API key override (NULL = per-provider default from env)
#'
#' @return List with response content (Anthropic-shaped for all providers)
#' @export
call_llm_api <- function(messages,
                         model,
                         max_tokens = 1000,
                         temperature = 0.0,
                         max_retries = 10,
                         system = NULL,
                         provider = "anthropic",
                         base_url = NULL,
                         api_key = NULL) {
  if (provider == "anthropic") {
    return(call_claude_api(
      messages = messages, model = model, max_tokens = max_tokens,
      temperature = temperature, max_retries = max_retries, system = system
    ))
  }

  # Resolve defaults for OpenAI-compatible providers
  defaults <- list(
    ollama = list(base_url = "http://localhost:11434/v1", api_key = NULL),
    openai = list(base_url = "https://api.openai.com/v1",
                  api_key = Sys.getenv("OPENAI_API_KEY")),
    groq   = list(base_url = "https://api.groq.com/openai/v1",
                  api_key = Sys.getenv("GROQ_API_KEY")),
    openrouter = list(base_url = "https://openrouter.ai/api/v1",
                      api_key = Sys.getenv("OPENROUTER_API_KEY"))
  )

  if (!provider %in% names(defaults)) {
    stop("Unknown LLM provider: '", provider,
         "'. Supported: anthropic, ollama, openai, groq, openrouter")
  }

  base_url <- base_url %||% defaults[[provider]]$base_url
  api_key  <- api_key  %||% defaults[[provider]]$api_key

  call_openai_api(
    messages = messages, model = model, max_tokens = max_tokens,
    temperature = temperature, max_retries = max_retries, system = system,
    base_url = base_url, api_key = api_key
  )
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


#' Get per-token pricing for a Claude model
#'
#' Returns input, output, cache_write, and cache_read prices per 1K tokens.
#' Falls back to Haiku pricing for unknown model IDs.
#'
#' @param model Character string for model ID
#' @return Named list with input, output, cache_write, cache_read ($/1K tokens)
#' @keywords internal
get_model_pricing <- function(model) {
  pricing_table <- list(
    "claude-haiku-4-5-20251001" = list(
      input = 0.001, output = 0.005,
      cache_write = 0.00125, cache_read = 0.0001
    ),
    "claude-sonnet-4-5-20250514" = list(
      input = 0.003, output = 0.015,
      cache_write = 0.00375, cache_read = 0.0003
    ),
    "qwen/qwen-2.5-72b-instruct" = list(
      input = 0.00004, output = 0.0001,
      cache_write = 0, cache_read = 0
    )
  )

  if (model %in% names(pricing_table)) {
    pricing_table[[model]]
  } else if (!grepl("^claude-", model)) {
    # Non-Claude models: $0 pricing (still logs token counts for throughput tracking)
    list(input = 0, output = 0, cache_write = 0, cache_read = 0)
  } else {
    warning("Unknown model '", model, "' — using claude-haiku-4-5-20251001 pricing as fallback")
    pricing_table[["claude-haiku-4-5-20251001"]]
  }
}


#' Log API call to CSV file
#'
#' @param model Character string for model ID
#' @param input_tokens Integer
#' @param output_tokens Integer
#' @param cache_creation_input_tokens Integer tokens written to cache (default 0)
#' @param cache_read_input_tokens Integer tokens read from cache (default 0)
#' @param timestamp POSIXct timestamp
#'
#' @return NULL (side effect: appends to logs/api_calls.csv)
#' @export
log_api_call <- function(model, input_tokens, output_tokens,
                         cache_creation_input_tokens = 0L,
                         cache_read_input_tokens = 0L,
                         timestamp) {

  pricing <- get_model_pricing(model)
  cost_usd <- (input_tokens / 1000 * pricing$input) +
    (output_tokens / 1000 * pricing$output) +
    (cache_creation_input_tokens / 1000 * pricing$cache_write) +
    (cache_read_input_tokens / 1000 * pricing$cache_read)

  log_entry <- tibble::tibble(
    timestamp = timestamp,
    model = model,
    input_tokens = input_tokens,
    output_tokens = output_tokens,
    cache_creation_input_tokens = cache_creation_input_tokens,
    cache_read_input_tokens = cache_read_input_tokens,
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

  log_data <- readr::read_csv(log_file, show_col_types = FALSE)

  # Backward compat: old logs may lack cache columns
  if (!"cache_creation_input_tokens" %in% names(log_data)) {
    log_data$cache_creation_input_tokens <- 0L
  }
  if (!"cache_read_input_tokens" %in% names(log_data)) {
    log_data$cache_read_input_tokens <- 0L
  }

  log_data |>
    dplyr::group_by(model) |>
    dplyr::summarize(
      n_calls = dplyr::n(),
      total_input_tokens = sum(input_tokens),
      total_output_tokens = sum(output_tokens),
      total_cache_creation_tokens = sum(cache_creation_input_tokens, na.rm = TRUE),
      total_cache_read_tokens = sum(cache_read_input_tokens, na.rm = TRUE),
      total_cost_usd = sum(cost_usd),
      cache_hit_rate = ifelse(
        sum(cache_creation_input_tokens + cache_read_input_tokens, na.rm = TRUE) > 0,
        sum(cache_read_input_tokens, na.rm = TRUE) /
          sum(cache_creation_input_tokens + cache_read_input_tokens, na.rm = TRUE),
        NA_real_
      ),
      .groups = "drop"
    )
}


# Null coalescing operator
if (!exists("%||%", mode = "function", envir = environment())) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
