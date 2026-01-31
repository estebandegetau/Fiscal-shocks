# Model A: Passage Extraction from Document Chunks
# Redesigned from binary classifier to passage extractor for production deployment
# Processes document chunks and extracts fiscal act passages for Models B & C

#' Extract fiscal act passages from a document chunk
#'
#' Processes a document chunk and extracts all passages describing fiscal acts.
#' This is the production version of Model A, designed to work with raw documents
#' rather than pre-segmented passages.
#'
#' @param chunk_text Character string with chunk text (from make_chunks())
#' @param chunk_metadata List with chunk metadata (doc_id, chunk_id, start_page, end_page, year)
#' @param model Character string for Claude model ID
#' @param examples List of few-shot examples (optional, loaded from JSON if NULL)
#' @param system_prompt Character string for system prompt (optional, loaded from file if NULL)
#' @param use_self_consistency Logical, use self-consistency sampling (default TRUE)
#' @param n_samples Integer number of samples for self-consistency (default 5)
#' @param temperature Numeric sampling temperature (default 0.7 for self-consistency)
#'
#' @return List with extraction results:
#'   - acts: List of extracted acts, each with act_name, year, passages, reasoning
#'   - no_acts_found: Logical indicating if no acts were found
#'   - extraction_notes: Optional notes about the extraction
#'   - chunk_metadata: Original chunk metadata for traceability
#'   - agreement_rate: Agreement rate from self-consistency (if used)
#' @export
model_a_extract_passages <- function(chunk_text,
                                     chunk_metadata,
                                     model = "claude-sonnet-4-20250514",
                                     examples = NULL,
                                     system_prompt = NULL,
                                     use_self_consistency = TRUE,
                                     n_samples = 5,
                                     temperature = 0.7) {

  # Load system prompt if not provided
  if (is.null(system_prompt)) {
    system_prompt_file <- here::here("prompts", "model_a_extract_system.txt")
    if (!file.exists(system_prompt_file)) {
      stop("System prompt file not found: ", system_prompt_file)
    }
    system_prompt <- readr::read_file(system_prompt_file)
  }

  # Load examples if not provided
  if (is.null(examples)) {
    examples_file <- here::here("prompts", "model_a_extract_examples.json")
    if (file.exists(examples_file)) {
      examples <- jsonlite::fromJSON(examples_file, simplifyVector = FALSE)
    } else {
      examples <- NULL
    }
  }

  # Format user input with chunk metadata context
  user_input <- format_extraction_input(chunk_text, chunk_metadata)

  # Use self-consistency if enabled
  if (use_self_consistency) {
    result <- model_a_extract_with_self_consistency(
      user_input = user_input,
      chunk_metadata = chunk_metadata,
      model = model,
      n_samples = n_samples,
      temperature = temperature,
      examples = examples,
      system_prompt = system_prompt
    )
  } else {
    # Standard single-shot extraction (temperature = 0)
    full_prompt <- format_few_shot_prompt(
      system = system_prompt,
      examples = examples,
      user_input = user_input
    )

    response <- call_claude_api(
      messages = list(list(role = "user", content = full_prompt)),
      model = model,
      max_tokens = 4000,  # Larger output for extraction
      temperature = 0.0
    )

    result <- parse_extraction_response(
      response$content[[1]]$text,
      chunk_metadata
    )
  }

  result
}


#' Format extraction input with chunk context
#'
#' @param chunk_text Character string with chunk text
#' @param chunk_metadata List with chunk metadata
#'
#' @return Formatted input string for the model
format_extraction_input <- function(chunk_text, chunk_metadata) {
  doc_id <- chunk_metadata$doc_id %||% "unknown"
  year <- chunk_metadata$year %||% "unknown"
  start_page <- chunk_metadata$start_page %||% 1
  end_page <- chunk_metadata$end_page %||% start_page

  glue::glue("
DOCUMENT: {doc_id}
DOCUMENT YEAR: {year}
PAGES: {start_page} to {end_page}

INSTRUCTIONS:
- Extract ALL fiscal act passages from this document chunk
- Page numbers in your output should be absolute (add {start_page - 1} to your page count)
- Group passages by act - if multiple passages describe the same act, include them all under one entry

DOCUMENT TEXT:
{chunk_text}
  ")
}


#' Parse extraction response from Claude API
#'
#' @param response_text Character string with API response
#' @param chunk_metadata List with chunk metadata for enrichment
#'
#' @return List with parsed extraction results
parse_extraction_response <- function(response_text, chunk_metadata) {
  result <- parse_json_response(
    response_text,
    required_fields = c("acts")
  )

  # Handle parsing errors
  if (!is.null(result$error)) {
    return(list(
      acts = list(),
      no_acts_found = TRUE,
      extraction_notes = paste("Parse error:", result$error),
      chunk_metadata = chunk_metadata,
      error = TRUE
    ))
  }

  # Ensure acts is a list
  if (is.null(result$acts)) {
    result$acts <- list()
  }

  # Add chunk metadata for traceability
  result$chunk_metadata <- chunk_metadata

  # Enrich each act with chunk context
  result$acts <- lapply(result$acts, function(act) {
    act$source_doc_id <- chunk_metadata$doc_id
    act$source_chunk_id <- chunk_metadata$chunk_id
    act$source_doc_year <- chunk_metadata$year
    act
  })

  # Ensure no_acts_found is set correctly
  if (is.null(result$no_acts_found)) {
    result$no_acts_found <- length(result$acts) == 0
  }

  result
}


#' Self-consistency wrapper for extraction
#'
#' @param user_input Formatted input string
#' @param chunk_metadata List with chunk metadata
#' @param model Character string for Claude model ID
#' @param n_samples Integer number of samples
#' @param temperature Numeric sampling temperature
#' @param examples List of few-shot examples
#' @param system_prompt Character string for system prompt
#'
#' @return List with aggregated extraction results
model_a_extract_with_self_consistency <- function(user_input,
                                                   chunk_metadata,
                                                   model = "claude-sonnet-4-20250514",
                                                   n_samples = 5,
                                                   temperature = 0.7,
                                                   examples = NULL,
                                                   system_prompt = NULL) {

  # Format prompt
  full_prompt <- format_few_shot_prompt(
    system = system_prompt,
    examples = examples,
    user_input = user_input
  )

  # Collect all samples
  all_results <- vector("list", n_samples)

  for (i in seq_len(n_samples)) {
    response <- call_claude_api(
      messages = list(list(role = "user", content = full_prompt)),
      model = model,
      max_tokens = 4000,
      temperature = temperature
    )

    all_results[[i]] <- tryCatch({
      parse_extraction_response(response$content[[1]]$text, chunk_metadata)
    }, error = function(e) {
      list(
        acts = list(),
        no_acts_found = TRUE,
        extraction_notes = paste("Parse error:", e$message),
        chunk_metadata = chunk_metadata,
        error = TRUE
      )
    })
  }

  # Aggregate extraction results across samples
  aggregate_extraction_results(all_results, chunk_metadata, n_samples)
}


#' Aggregate extraction results from multiple samples
#'
#' Uses voting to determine which acts to include. An act is included if it
#' appears in at least 50% of samples (majority threshold).
#'
#' @param all_results List of extraction results from multiple samples
#' @param chunk_metadata List with chunk metadata
#' @param n_samples Integer number of samples taken
#'
#' @return Aggregated extraction result
aggregate_extraction_results <- function(all_results, chunk_metadata, n_samples) {

  # Collect all acts across samples with their occurrence counts
  act_occurrences <- list()

  for (result in all_results) {
    if (!is.null(result$acts) && length(result$acts) > 0) {
      for (act in result$acts) {
        act_name <- act$act_name
        if (!is.null(act_name) && nchar(act_name) > 0) {
          # Normalize act name for matching
          normalized_name <- normalize_act_name(act_name)

          if (normalized_name %in% names(act_occurrences)) {
            # Add passages to existing act
            act_occurrences[[normalized_name]]$count <-
              act_occurrences[[normalized_name]]$count + 1
            act_occurrences[[normalized_name]]$all_passages <-
              c(act_occurrences[[normalized_name]]$all_passages, act$passages)
            act_occurrences[[normalized_name]]$all_names <-
              c(act_occurrences[[normalized_name]]$all_names, act_name)
            act_occurrences[[normalized_name]]$all_years <-
              c(act_occurrences[[normalized_name]]$all_years, act$year)
            act_occurrences[[normalized_name]]$all_reasoning <-
              c(act_occurrences[[normalized_name]]$all_reasoning, act$reasoning)
          } else {
            # New act
            act_occurrences[[normalized_name]] <- list(
              count = 1,
              all_passages = act$passages,
              all_names = list(act_name),
              all_years = list(act$year),
              all_reasoning = list(act$reasoning)
            )
          }
        }
      }
    }
  }

  # Filter to acts that appear in at least 50% of samples
  n_valid_samples <- sum(sapply(all_results, function(r) !isTRUE(r$error)))
  threshold <- max(1, floor(n_valid_samples * 0.5))

  final_acts <- list()

  for (normalized_name in names(act_occurrences)) {
    occ <- act_occurrences[[normalized_name]]

    if (occ$count >= threshold) {
      # Deduplicate passages
      unique_passages <- deduplicate_passages(occ$all_passages)

      # Get most common act name
      name_counts <- table(unlist(occ$all_names))
      best_name <- names(name_counts)[which.max(name_counts)]

      # Get most common year
      year_counts <- table(unlist(occ$all_years))
      best_year <- as.integer(names(year_counts)[which.max(year_counts)])

      # Get first non-null reasoning
      reasoning <- NA_character_
      for (r in occ$all_reasoning) {
        if (!is.null(r) && !is.na(r) && nchar(r) > 0) {
          reasoning <- r
          break
        }
      }

      final_acts[[length(final_acts) + 1]] <- list(
        act_name = best_name,
        year = best_year,
        passages = unique_passages,
        reasoning = reasoning,
        agreement_rate = occ$count / n_valid_samples,
        source_doc_id = chunk_metadata$doc_id,
        source_chunk_id = chunk_metadata$chunk_id,
        source_doc_year = chunk_metadata$year
      )
    }
  }

  # Calculate overall agreement
  no_acts_counts <- sapply(all_results, function(r) {
    isTRUE(r$no_acts_found) || length(r$acts) == 0
  })

  list(
    acts = final_acts,
    no_acts_found = length(final_acts) == 0,
    extraction_notes = sprintf(
      "Aggregated from %d samples, %d acts found with >=50%% agreement",
      n_valid_samples, length(final_acts)
    ),
    chunk_metadata = chunk_metadata,
    n_samples = n_samples,
    n_valid_samples = n_valid_samples,
    agreement_rate = if (length(final_acts) > 0) {
      mean(sapply(final_acts, function(a) a$agreement_rate))
    } else if (sum(no_acts_counts) >= threshold) {
      sum(no_acts_counts) / n_valid_samples
    } else {
      0
    }
  )
}


#' Normalize act name for matching across samples
#'
#' @param act_name Character string with act name
#'
#' @return Normalized act name
normalize_act_name <- function(act_name) {
  act_name |>
    tolower() |>
    stringr::str_replace_all("\\s+", " ") |>
    stringr::str_replace_all("[^a-z0-9 ]", "") |>
    stringr::str_trim()
}


#' Deduplicate passages based on text similarity
#'
#' @param passages List of passage objects with text field
#' @param similarity_threshold Minimum Jaccard similarity for deduplication (default 0.8)
#'
#' @return Deduplicated list of passages
deduplicate_passages <- function(passages, similarity_threshold = 0.8) {
  if (is.null(passages) || length(passages) == 0) {
    return(list())
  }

  # Extract text from passages
  texts <- sapply(passages, function(p) {
    if (is.character(p)) p else p$text %||% ""
  })

  # Keep track of which passages to include
  keep <- rep(TRUE, length(passages))

  for (i in seq_along(passages)) {
    if (!keep[i]) next

    for (j in seq_len(i - 1)) {
      if (!keep[j]) next

      # Compute Jaccard similarity on words
      words_i <- unique(strsplit(tolower(texts[i]), "\\s+")[[1]])
      words_j <- unique(strsplit(tolower(texts[j]), "\\s+")[[1]])

      intersection <- length(intersect(words_i, words_j))
      union <- length(union(words_i, words_j))

      if (union > 0 && intersection / union >= similarity_threshold) {
        # Keep the longer passage
        if (nchar(texts[i]) <= nchar(texts[j])) {
          keep[i] <- FALSE
        } else {
          keep[j] <- FALSE
        }
      }
    }
  }

  passages[keep]
}


#' Run Model A extraction on multiple chunks
#'
#' @param chunks Data frame with chunks (from make_chunks())
#' @param model Character string for Claude model ID
#' @param show_progress Logical, show progress bar (default TRUE)
#' @param use_self_consistency Logical, use self-consistency sampling (default TRUE)
#' @param n_samples Integer number of samples for self-consistency (default 5)
#' @param temperature Numeric sampling temperature (default 0.7)
#'
#' @return Tibble with extraction results for each chunk
#' @export
model_a_extract_passages_batch <- function(chunks,
                                           model = "claude-sonnet-4-20250514",
                                           show_progress = TRUE,
                                           use_self_consistency = TRUE,
                                           n_samples = 5,
                                           temperature = 0.7) {

  # Load examples and system prompt once
  system_prompt_file <- here::here("prompts", "model_a_extract_system.txt")
  system_prompt <- readr::read_file(system_prompt_file)

  examples_file <- here::here("prompts", "model_a_extract_examples.json")
  if (file.exists(examples_file)) {
    examples <- jsonlite::fromJSON(examples_file, simplifyVector = FALSE)
  } else {
    examples <- NULL
  }

  # Process each chunk
  if (show_progress) {
    pb <- progress::progress_bar$new(
      format = "  Extracting [:bar] :percent eta: :eta (:current/:total chunks)",
      total = nrow(chunks)
    )
  }

  results <- purrr::map(seq_len(nrow(chunks)), function(i) {
    if (show_progress) pb$tick()

    chunk <- chunks[i, ]

    # Build chunk metadata
    chunk_metadata <- list(
      doc_id = chunk$doc_id,
      chunk_id = chunk$chunk_id,
      start_page = chunk$start_page,
      end_page = chunk$end_page,
      year = chunk$year
    )

    result <- model_a_extract_passages(
      chunk_text = chunk$text,
      chunk_metadata = chunk_metadata,
      model = model,
      examples = examples,
      system_prompt = system_prompt,
      use_self_consistency = use_self_consistency,
      n_samples = n_samples,
      temperature = temperature
    )

    # Return as tibble row with nested acts
    tibble::tibble(
      doc_id = chunk$doc_id,
      chunk_id = chunk$chunk_id,
      year = chunk$year,
      start_page = chunk$start_page,
      end_page = chunk$end_page,
      n_acts = length(result$acts),
      acts = list(result$acts),
      no_acts_found = result$no_acts_found,
      agreement_rate = result$agreement_rate %||% NA_real_,
      extraction_notes = result$extraction_notes %||% NA_character_
    )
  })

  dplyr::bind_rows(results)
}


#' Flatten extracted passages from batch results
#'
#' Converts the nested batch results to a flat tibble with one row per act.
#'
#' @param batch_results Tibble from model_a_extract_passages_batch()
#'
#' @return Tibble with one row per extracted act
#' @export
flatten_extracted_acts <- function(batch_results) {

  # Filter to chunks with acts
  with_acts <- batch_results |>
    dplyr::filter(n_acts > 0)

  if (nrow(with_acts) == 0) {
    return(tibble::tibble(
      doc_id = character(),
      chunk_id = integer(),
      year = integer(),
      act_name = character(),
      act_year = integer(),
      passages_text = character(),
      page_numbers = list(),
      confidence = numeric(),
      agreement_rate = numeric(),
      reasoning = character()
    ))
  }

  # Unnest acts
  purrr::map_dfr(seq_len(nrow(with_acts)), function(i) {
    row <- with_acts[i, ]
    acts <- row$acts[[1]]

    purrr::map_dfr(acts, function(act) {
      # Combine passage texts
      passages_text <- paste(
        sapply(act$passages, function(p) {
          if (is.character(p)) p else p$text %||% ""
        }),
        collapse = "\n\n---\n\n"
      )

      # Collect page numbers
      page_numbers <- unique(unlist(lapply(act$passages, function(p) {
        if (is.list(p)) p$page_numbers else NULL
      })))

      # Get average confidence from passages
      confidences <- sapply(act$passages, function(p) {
        if (is.list(p)) p$confidence %||% NA_real_ else NA_real_
      })
      avg_confidence <- mean(confidences, na.rm = TRUE)

      tibble::tibble(
        doc_id = row$doc_id,
        chunk_id = row$chunk_id,
        year = row$year,
        act_name = act$act_name %||% NA_character_,
        act_year = act$year %||% NA_integer_,
        passages_text = passages_text,
        page_numbers = list(page_numbers),
        confidence = if (is.na(avg_confidence)) 0.9 else avg_confidence,
        agreement_rate = act$agreement_rate %||% row$agreement_rate,
        reasoning = act$reasoning %||% NA_character_
      )
    })
  })
}


#' Evaluate Model A extraction against ground truth
#'
#' Compares extracted acts to known acts from us_shocks.csv.
#'
#' @param extracted_acts Tibble from flatten_extracted_acts()
#' @param known_acts Tibble with known acts (act_name, year columns)
#' @param match_threshold Fuzzy match threshold (default 0.85)
#'
#' @return List with evaluation metrics
#' @export
evaluate_model_a_extraction <- function(extracted_acts,
                                        known_acts,
                                        match_threshold = 0.85) {

  # Normalize act names for matching
  extracted_names <- normalize_act_name(extracted_acts$act_name)
  known_names <- normalize_act_name(known_acts$act_name)

  # For each known act, check if it was extracted
  known_found <- sapply(known_names, function(known) {
    # Check exact match first
    if (known %in% extracted_names) {
      return(TRUE)
    }

    # Check fuzzy match
    distances <- stringdist::stringdist(known, extracted_names, method = "jw")
    similarities <- 1 - distances
    any(similarities >= match_threshold)
  })

  # For each extracted act, check if it's a true positive
  extracted_correct <- sapply(extracted_names, function(extracted) {
    if (extracted %in% known_names) {
      return(TRUE)
    }

    distances <- stringdist::stringdist(extracted, known_names, method = "jw")
    similarities <- 1 - distances
    any(similarities >= match_threshold)
  })

  # Calculate metrics
  true_positives <- sum(extracted_correct)
  false_positives <- sum(!extracted_correct)
  false_negatives <- sum(!known_found)

  precision <- true_positives / (true_positives + false_positives)
  recall <- true_positives / (true_positives + false_negatives)
  f1 <- 2 * (precision * recall) / (precision + recall)

  list(
    true_positives = true_positives,
    false_positives = false_positives,
    false_negatives = false_negatives,
    precision = precision,
    recall = recall,
    f1_score = f1,
    n_extracted = nrow(extracted_acts),
    n_known = nrow(known_acts),
    missed_acts = known_acts$act_name[!known_found],
    false_discoveries = extracted_acts$act_name[!extracted_correct]
  )
}


# Null coalescing operator (if not already defined)
if (!exists("%||%")) {
  `%||%` <- function(x, y) {
    if (is.null(x)) y else x
  }
}
