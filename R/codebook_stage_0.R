# Codebook Stage 0: Load, Validate, and Classify with YAML Codebooks
# Generic functions reusable for C1-C4
#
# Loads H&K-format YAML codebooks, validates required fields,
# constructs system prompts, and classifies text passages.

#' Load and validate a YAML codebook
#'
#' Parses a YAML codebook file and validates that all required H&K fields
#' are present for each class definition.
#'
#' @param path Character path to YAML codebook file
#' @return List with codebook metadata and parsed classes
#' @export
load_validate_codebook <- function(path) {
  if (!file.exists(path)) {
    stop("Codebook file not found: ", path)
  }

  raw <- yaml::read_yaml(path)

  if (is.null(raw$codebook)) {
    stop("YAML file missing top-level 'codebook' key: ", path)
  }

  cb <- raw$codebook

  # Validate top-level fields
  required_top <- c("name", "version", "instructions",
                     "classes", "output_instructions")
  missing_top <- setdiff(required_top, names(cb))
  if (length(missing_top) > 0) {
    stop("Codebook missing required top-level fields: ",
         paste(missing_top, collapse = ", "))
  }

  # Validate each class
  required_class <- c("label", "label_definition", "clarification",
                       "negative_clarification")

  for (i in seq_along(cb$classes)) {
    cls <- cb$classes[[i]]
    missing_cls <- setdiff(required_class, names(cls))
    if (length(missing_cls) > 0) {
      stop(sprintf("Class '%s' missing required fields: %s",
                   cls$label %||% paste0("index ", i),
                   paste(missing_cls, collapse = ", ")))
    }

    # Validate examples have text + reasoning
    for (j in seq_along(cls$positive_examples)) {
      ex <- cls$positive_examples[[j]]
      if (is.null(ex$text) || is.null(ex$reasoning)) {
        stop(sprintf("Class '%s' positive_example %d missing text or reasoning",
                     cls$label, j))
      }
    }
    for (j in seq_along(cls$negative_examples)) {
      ex <- cls$negative_examples[[j]]
      if (is.null(ex$text) || is.null(ex$reasoning)) {
        stop(sprintf("Class '%s' negative_example %d missing text or reasoning",
                     cls$label, j))
      }
    }
  }

  # Extract metadata
  valid_labels <- vapply(cb$classes, function(cls) cls$label, character(1))

  structure(
    cb,
    class = "hk_codebook",
    valid_labels = valid_labels,
    codebook_type = sub(":.*", "", cb$name),  # e.g., "C1" from "C1: Measure Identification"
    n_classes = length(cb$classes),
    path = path
  )
}


#' Get valid labels from a codebook
#'
#' @param codebook A validated codebook object from load_validate_codebook()
#' @return Character vector of valid label strings
#' @export
get_valid_labels <- function(codebook) {
  attr(codebook, "valid_labels")
}


#' Construct a system prompt from a codebook
#'
#' Assembles the full system prompt from YAML codebook components.
#' Supports class_order permutation (for Test IV) and component
#' exclusion (for ablation studies).
#'
#' @param codebook A validated codebook object
#' @param class_order Integer vector specifying class order (NULL = original order)
#' @param exclude_components Named list of components to exclude. Keys are class
#'   labels, values are character vectors of component names to exclude
#'   (e.g., list(FISCAL_MEASURE = c("clarification_3", "negative_clarification_2")))
#' @return Character string with the assembled system prompt
#' @export
construct_codebook_prompt <- function(codebook,
                                      class_order = NULL,
                                      exclude_components = NULL) {
  parts <- character()

  # Task description and instructions
  parts <- c(parts, codebook$instructions, "\n\n")

  # Class definitions
  classes <- codebook$classes
  if (!is.null(class_order)) {
    classes <- classes[class_order]
  }

  parts <- c(parts, "# Class Definitions\n\n")

  for (cls in classes) {
    parts <- c(parts, sprintf("## %s\n\n", cls$label))
    parts <- c(parts, sprintf("**Definition:** %s\n\n", cls$label_definition))

    # Clarifications (with optional exclusion)
    excl <- exclude_components[[cls$label]]
    clar_items <- cls$clarification
    if (!is.null(excl)) {
      excl_idx <- grep("^clarification_", excl)
      if (length(excl_idx) > 0) {
        excl_nums <- as.integer(sub("clarification_", "", excl[excl_idx]))
        clar_items <- clar_items[-excl_nums[excl_nums <= length(clar_items)]]
      }
    }
    if (length(clar_items) > 0) {
      parts <- c(parts, "**Inclusion criteria:**\n")
      for (item in clar_items) {
        parts <- c(parts, sprintf("- %s\n", item))
      }
      parts <- c(parts, "\n")
    }

    # Negative clarifications (with optional exclusion)
    neg_clar_items <- cls$negative_clarification
    if (!is.null(excl)) {
      excl_idx <- grep("^negative_clarification_", excl)
      if (length(excl_idx) > 0) {
        excl_nums <- as.integer(sub("negative_clarification_", "", excl[excl_idx]))
        neg_clar_items <- neg_clar_items[-excl_nums[excl_nums <= length(neg_clar_items)]]
      }
    }
    if (length(neg_clar_items) > 0) {
      parts <- c(parts, "**Exclusion criteria:**\n")
      for (item in neg_clar_items) {
        parts <- c(parts, sprintf("- %s\n", item))
      }
      parts <- c(parts, "\n")
    }

    # Positive examples with expected JSON output
    if (length(cls$positive_examples) > 0) {
      parts <- c(parts, sprintf("**Positive examples for %s:**\n\n", cls$label))
      for (j in seq_along(cls$positive_examples)) {
        ex <- cls$positive_examples[[j]]
        example_json <- jsonlite::toJSON(
          list(
            label = jsonlite::unbox(cls$label),
            measure_name = jsonlite::unbox(NULL),
            reasoning = jsonlite::unbox(ex$reasoning)
          ),
          pretty = TRUE, null = "null"
        )
        parts <- c(parts,
          sprintf("Example %d:\nText: %s\n\nExpected output:\n%s\n\n",
                  j, trimws(ex$text), example_json))
      }
    }

    # Negative examples with reasoning (no JSON block)
    if (length(cls$negative_examples) > 0) {
      parts <- c(parts, sprintf("**Negative examples (not %s):**\n\n", cls$label))
      for (j in seq_along(cls$negative_examples)) {
        ex <- cls$negative_examples[[j]]
        parts <- c(parts,
          sprintf("Example %d:\nText: %s\n\nWhy not %s: %s\n\n",
                  j, trimws(ex$text), cls$label, trimws(ex$reasoning)))
      }
    }
  }

  # Output instructions
  parts <- c(parts, "# Output Instructions\n\n", codebook$output_instructions, "\n")

  paste(parts, collapse = "")
}


#' Classify a passage using a codebook
#'
#' Sends a passage to the Claude API using the codebook as system prompt,
#' optionally with few-shot examples and self-consistency.
#'
#' @param text Character string with the passage to classify
#' @param codebook A validated codebook object
#' @param few_shot_examples List of few-shot examples (each with input/output)
#' @param model Character string for model ID (default: "claude-haiku-4-5-20251001")
#' @param temperature Numeric 0-1 (default: 0 for deterministic)
#' @param use_self_consistency Logical, use self-consistency sampling
#' @param n_samples Integer number of self-consistency samples
#' @param sc_temperature Numeric temperature for self-consistency sampling
#' @param system_prompt Optional override for system prompt (NULL = construct from codebook)
#' @param max_tokens Integer max output tokens
#' @param max_retries Integer for number of retry attempts (default 10 for long pipelines)
#' @param use_cache Logical, use Anthropic prompt caching (default FALSE).
#'   When TRUE, system prompt and few-shot examples are sent as content block
#'   arrays with cache_control markers for Anthropic's prompt caching.
#' @return List with label, reasoning, and raw response
#' @export
classify_with_codebook <- function(text,
                                   codebook,
                                   few_shot_examples = NULL,
                                   model = "claude-haiku-4-5-20251001",
                                   temperature = 0,
                                   use_self_consistency = FALSE,
                                   n_samples = 5,
                                   sc_temperature = 0.7,
                                   system_prompt = NULL,
                                   max_tokens = 500,
                                   max_retries = 10,
                                   use_cache = FALSE,
                                   provider = "anthropic",
                                   base_url = NULL,
                                   api_key = NULL) {
  # Build system prompt from codebook if not overridden
  if (is.null(system_prompt)) {
    system_prompt <- construct_codebook_prompt(codebook)
  }

  # Prompt caching is Anthropic-only; disable for other providers
  if (use_cache && provider != "anthropic") {
    message("Note: prompt caching disabled for provider '", provider,
            "' (Anthropic-only feature)")
    use_cache <- FALSE
  }

  # Build few-shot examples text
  examples_text <- ""
  if (!is.null(few_shot_examples) && length(few_shot_examples) > 0) {
    examples_parts <- c("# Examples\n\n")
    for (i in seq_along(few_shot_examples)) {
      ex <- few_shot_examples[[i]]
      examples_parts <- c(examples_parts,
        sprintf("Example %d:\n", i),
        "Input:\n", ex$input,
        "\n\nOutput:\n",
        jsonlite::toJSON(ex$output, auto_unbox = TRUE, pretty = TRUE),
        "\n\n"
      )
    }
    examples_text <- paste(examples_parts, collapse = "")
  }

  # Build chunk text (unique per call)
  chunk_text <- paste0(
    "# Your Task\n\n",
    "Now analyze this passage:\n\n",
    "Input:\n", text,
    "\n\nOutput:\n"
  )

  # Build API inputs: plain strings (default) or content block arrays (cached)
  if (use_cache && nchar(examples_text) > 0) {
    # System prompt as content block array with cache_control
    system_for_api <- list(
      list(type = "text", text = system_prompt,
           cache_control = list(type = "ephemeral"))
    )

    # User message as two content blocks:
    # Block 1: few-shot examples (cached within fold)
    # Block 2: chunk text (unique per call, NOT cached)
    user_content <- list(
      list(type = "text", text = examples_text,
           cache_control = list(type = "ephemeral")),
      list(type = "text", text = chunk_text)
    )
  } else {
    # Plain strings — identical to previous behavior
    system_for_api <- system_prompt
    user_content <- paste0(examples_text, chunk_text)
  }

  valid_labels <- get_valid_labels(codebook)

  # Define parsing functions for self-consistency
  parse_fn <- function(response_text) {
    parse_json_response(
      response_text,
      required_fields = c("label", "reasoning")
    )
  }

  extract_class_fn <- function(parsed) {
    if (!is.null(parsed$label) && parsed$label %in% valid_labels) {
      parsed$label
    } else {
      NA_character_
    }
  }

  if (use_self_consistency) {
    result <- call_with_self_consistency(
      messages = list(list(role = "user", content = user_content)),
      model = model,
      n_samples = n_samples,
      temperature = sc_temperature,
      max_tokens = max_tokens,
      max_retries = max_retries,
      parse_fn = parse_fn,
      extract_class_fn = extract_class_fn,
      system = system_for_api,
      provider = provider,
      base_url = base_url,
      api_key = api_key
    )

    # Extract additional fields from the majority result
    majority_result <- NULL
    for (r in result$all_results) {
      if (!is.null(r$label) && r$label == result$prediction) {
        majority_result <- r
        break
      }
    }

    list(
      label = result$prediction,
      measure_name = majority_result$measure_name %||% NA_character_,
      reasoning = majority_result$reasoning %||% NA_character_,
      confidence = result$confidence,
      agreement_rate = result$agreement_rate,
      all_predictions = result$all_predictions
    )
  } else {
    # Single deterministic call
    response <- call_llm_api(
      messages = list(list(role = "user", content = user_content)),
      model = model,
      max_tokens = max_tokens,
      temperature = temperature,
      max_retries = max_retries,
      system = system_for_api,
      provider = provider,
      base_url = base_url,
      api_key = api_key
    )

    parsed <- parse_fn(response$content[[1]]$text)
    label <- extract_class_fn(parsed)

    list(
      label = label,
      measure_name = parsed$measure_name %||% NA_character_,
      reasoning = parsed$reasoning %||% NA_character_,
      confidence = if (!is.na(label)) 1.0 else 0.0,
      agreement_rate = 1.0,
      all_predictions = label
    )
  }
}


# Null coalescing operator
if (!exists("%||%", mode = "function", envir = environment())) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
