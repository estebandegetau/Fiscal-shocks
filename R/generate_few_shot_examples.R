# Generate Few-Shot Examples for Model A
# This script creates example prompts from training data for few-shot learning

#' Generate few-shot examples for Model A from training data
#'
#' @param training_data_a Tibble with training examples (from tar_read(training_data_a))
#' @param n_positive Integer number of positive examples (default 10)
#' @param n_negative Integer number of negative examples (default 10)
#' @param seed Integer for reproducibility (default 20251206)
#'
#' @return List of examples with input/output structure
#' @export
generate_model_a_examples <- function(training_data_a,
                                      n_positive = 10,
                                      n_negative = 10,
                                      seed = 20251206) {

  set.seed(seed)

  # Sample positive examples (contains fiscal act)
  positive_examples <- training_data_a |>
    dplyr::filter(is_fiscal_act == 1, split == "train") |>
    dplyr::slice_sample(n = n_positive) |>
    dplyr::rowwise() |>
    dplyr::mutate(
      input = text,
      output = list(list(
        contains_act = TRUE,
        act_name = act_name,
        confidence = 0.95,
        reasoning = sprintf("This passage clearly describes %s, which is a specific piece of federal fiscal legislation.", act_name)
      ))
    ) |>
    dplyr::ungroup() |>
    dplyr::select(input, output)

  # Sample negative examples (does not contain fiscal act)
  # Prioritize edge cases for better precision training
  negative_pool <- training_data_a |>
    dplyr::filter(is_fiscal_act == 0, split == "train") |>
    dplyr::mutate(
      # Score examples by edge case keywords to prioritize tricky negatives
      edge_case_score =
        stringr::str_count(tolower(text), "\\bpropose[ds]?\\b") * 3 +  # Proposals (high priority)
        stringr::str_count(tolower(text), "\\brecommend[s|ed|ation|ations]?\\b") * 3 +  # Recommendations
        stringr::str_count(tolower(text), "\\bshould\\b") * 2 +  # Suggestions
        stringr::str_count(tolower(text), "\\b(act|legislation)\\s+of\\s+\\d{4}\\b") * 2 +  # Named acts (likely historical)
        stringr::str_count(tolower(text), "\\bsince\\s+(the|\\d{4})\\b") * 2 +  # Retrospective language
        stringr::str_count(tolower(text), "\\bprevious(ly)?\\b") * 2 +  # Historical references
        stringr::str_count(tolower(text), "\\benacted\\s+(in|to)\\b") * 1.5  # Past enactment (retrospective)
    )

  # Select mix: 2/3 edge cases, 1/3 random negatives
  n_edge <- round(n_negative * 0.67)
  n_random <- n_negative - n_edge

  edge_examples <- negative_pool |>
    dplyr::filter(edge_case_score > 0) |>
    dplyr::slice_max(edge_case_score, n = n_edge, with_ties = FALSE)

  random_examples <- negative_pool |>
    dplyr::filter(!text %in% edge_examples$text) |>
    dplyr::slice_sample(n = n_random)

  negative_examples <- dplyr::bind_rows(edge_examples, random_examples) |>
    dplyr::rowwise() |>
    dplyr::mutate(
      input = text,
      output = list(list(
        contains_act = FALSE,
        act_name = NA_character_,
        confidence = 0.90,
        reasoning = "This passage contains general economic discussion but does not describe a specific fiscal policy act."
      ))
    ) |>
    dplyr::ungroup() |>
    dplyr::select(input, output)

  # Combine and convert to list
  examples <- dplyr::bind_rows(positive_examples, negative_examples)

  # Convert to nested list structure for JSON export
  examples_list <- purrr::map(seq_len(nrow(examples)), function(i) {
    list(
      input = examples$input[[i]],
      output = examples$output[[i]]
    )
  })

  examples_list
}


#' Generate economic context string for a given year
#'
#' @param year Integer year to get context for
#' @param recession_data Tibble with year, recession, and context columns
#'
#' @return Character string describing economic context
#' @export
get_economic_context <- function(year, recession_data) {
  if (is.null(recession_data)) {
    return(NULL)
  }
  if (year %in% recession_data$year) {
    ctx <- recession_data$context[recession_data$year == year]
    return(paste0("RECESSION YEAR: ", ctx))
  } else {
    return("Economic expansion - no recession")
  }
}


#' Generate detailed reasoning for contrasting examples
#'
#' Provides comprehensive reasoning for acts that are commonly misclassified,
#' explaining why they belong to their assigned category despite potentially
#' misleading features.
#'
#' @param act_name Character name of the act
#' @param motivation Character motivation category
#' @param year Integer year of the act
#' @param economic_context Character economic context string (optional)
#'
#' @return Character string with detailed reasoning
generate_contrasting_reasoning <- function(act_name, motivation, year,
                                           economic_context = NULL) {
  # EGTRRA 2001 - Countercyclical despite efficiency/long-run language
  if (grepl("Economic Growth and Tax Relief Reconciliation Act of 2001|EGTRRA",
            act_name)) {
    return(paste0(
      "CRITICAL REASONING: Despite containing language about 'economic growth' and ",
      "long-term tax reform, EGTRRA 2001 is classified as COUNTERCYCLICAL. ",
      "Key evidence: (1) Enacted during the 2001 recession following the dot-com bust; ",
      "(2) Congress explicitly designed the rebate checks to provide immediate stimulus; ",
      "(3) The timing was accelerated specifically to address the economic downturn; ",
      "(4) Contemporary documents describe it as a response to weakening economic ",
      "conditions. The 'growth' framing was political; the economic substance was ",
      "countercyclical stimulus."
    ))
  }

  # TRA 1986 - Long-run despite being during expansion
  if (grepl("Tax Reform Act of 1986", act_name)) {
    return(paste0(
      "CRITICAL REASONING: The Tax Reform Act of 1986 is classified as LONG-RUN ",
      "despite being enacted during economic expansion. Key evidence: (1) The act was ",
      "designed to be revenue-neutral, explicitly NOT intended to stimulate or contract ",
      "the economy; (2) Its primary goal was structural reform - broadening the tax base ",
      "while lowering rates; (3) The reform process began years earlier and was not ",
      "triggered by current economic conditions; (4) Contemporary documents emphasize ",
      "efficiency, fairness, and simplification - not cyclical management. Economic ",
      "expansion is the NEUTRAL baseline; Long-run reforms happen when there is no ",
      "cyclical pressure requiring immediate response."
    ))
  }

  # Default reasoning for other acts
  glue::glue("This act is classified as {motivation} based on the legislative context and timing.")
}


#' Generate few-shot examples for Model B from training data
#'
#' Creates examples for few-shot learning with support for required contrasting
#' examples and economic context to improve classification of boundary cases.
#'
#' @param training_data_b Tibble with Model B training examples (from tar_read(training_data_b))
#' @param n_per_class Integer number of examples per motivation category (default 5)
#' @param required_acts Character vector of act names that must be included
#' @param recession_years Tibble with recession year data (optional)
#' @param seed Integer for reproducibility (default 20251206)
#'
#' @return List of examples with input/output structure
#' @export
generate_model_b_examples <- function(training_data_b,
                                      n_per_class = 5,
                                      required_acts = NULL,
                                      recession_years = NULL,
                                      seed = 20251206) {

  set.seed(seed)

  # Helper function to build example from row
  build_example <- function(row, recession_years, is_required = FALSE) {
    economic_ctx <- get_economic_context(row$year, recession_years)

    # Build input with economic context if available
    if (!is.null(economic_ctx)) {
      input_text <- glue::glue("
ACT: {row$act_name}
YEAR: {row$year}
ECONOMIC CONTEXT: {economic_ctx}

PASSAGES FROM ORIGINAL SOURCES:
{row$passages_text}

Classify this act's PRIMARY motivation.
      ")
    } else {
      input_text <- glue::glue("
ACT: {row$act_name}
YEAR: {row$year}

PASSAGES FROM ORIGINAL SOURCES:
{row$passages_text}

Classify this act's PRIMARY motivation.
      ")
    }

    # Generate reasoning - detailed for required acts, standard for others
    if (is_required) {
      reasoning <- generate_contrasting_reasoning(
        row$act_name, row$motivation, row$year, economic_ctx
      )
    } else {
      reasoning <- glue::glue(
        "This act is classified as {row$motivation} based on the legislative context and timing."
      )
    }

    list(
      input = as.character(input_text),
      output = list(
        motivation = row$motivation,
        exogenous = row$exogenous,
        confidence = 0.95,
        evidence = list(
          list(
            passage_excerpt = stringr::str_sub(row$passages_text, 1, 150),
            supports = row$motivation
          )
        ),
        reasoning = as.character(reasoning)
      )
    )
  }

  # Step 1: Include required acts first (from any split)
  required_examples <- list()
  required_motivations <- character()

  if (!is.null(required_acts) && length(required_acts) > 0) {
    for (act in required_acts) {
      # Find the act in any split
      act_row <- training_data_b |>
        dplyr::filter(grepl(act, act_name, fixed = TRUE)) |>
        dplyr::slice(1)

      if (nrow(act_row) == 1) {
        example <- build_example(
          as.list(act_row),
          recession_years,
          is_required = TRUE
        )
        required_examples <- append(required_examples, list(example))
        required_motivations <- c(required_motivations, act_row$motivation)
        message(sprintf("Including required act: %s (%s)", act, act_row$motivation))
      } else {
        warning(sprintf("Required act not found: %s", act))
      }
    }
  }

  # Step 2: Sample remaining examples from training split
  # Count how many more we need per class
  motivation_counts <- table(required_motivations)
  all_motivations <- unique(training_data_b$motivation)

  sampled_examples <- list()

  for (motiv in all_motivations) {
    # How many required examples do we have for this motivation?
    n_required <- ifelse(motiv %in% names(motivation_counts),
                         motivation_counts[[motiv]], 0)
    n_needed <- max(0, n_per_class - n_required)

    if (n_needed > 0) {
      # Sample from training split, excluding required acts
      pool <- training_data_b |>
        dplyr::filter(
          split == "train",
          motivation == motiv
        )

      if (!is.null(required_acts)) {
        for (act in required_acts) {
          pool <- pool |>
            dplyr::filter(!grepl(act, act_name, fixed = TRUE))
        }
      }

      sampled <- pool |>
        dplyr::slice_sample(n = min(n_needed, nrow(pool)))

      for (i in seq_len(nrow(sampled))) {
        example <- build_example(
          as.list(sampled[i, ]),
          recession_years,
          is_required = FALSE
        )
        sampled_examples <- append(sampled_examples, list(example))
      }
    }
  }

  # Step 3: Combine required and sampled examples
  all_examples <- c(required_examples, sampled_examples)

  # Count by motivation for reporting
  motivation_summary <- sapply(all_examples, function(x) x$output$motivation)
  summary_table <- table(motivation_summary)

  message(sprintf("Generated %d Model B examples:", length(all_examples)))
  for (m in names(summary_table)) {
    message(sprintf("  %s: %d", m, summary_table[[m]]))
  }

  all_examples
}


#' Save few-shot examples to JSON file
#'
#' @param examples List of examples from generate_model_a_examples() or generate_model_b_examples()
#' @param output_path Character path to output JSON file
#'
#' @return Character path to saved file (invisibly)
#' @export
save_few_shot_examples <- function(examples, output_path) {

  # Ensure directory exists
  output_dir <- dirname(output_path)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Write JSON
  jsonlite::write_json(
    examples,
    path = output_path,
    pretty = TRUE,
    auto_unbox = TRUE
  )

  message("Saved ", length(examples), " examples to ", output_path)
  invisible(output_path)
}


#' Generate few-shot examples for Model A extraction from training data
#'
#' Creates examples showing how to extract fiscal act passages from document chunks.
#' Uses us_labels passages matched to source documents to create realistic extraction examples.
#'
#' @param aligned_data Tibble with aligned labels and shocks (from tar_read(aligned_data))
#' @param us_body Tibble with document text (from tar_read(us_body))
#' @param n_positive Integer number of positive examples with acts (default 5)
#' @param n_negative Integer number of negative examples without acts (default 3)
#' @param context_pages Integer number of pages of context around passages (default 3)
#' @param seed Integer for reproducibility (default 20251206)
#'
#' @return List of examples with input/output structure for extraction task
#' @export
generate_model_a_extraction_examples <- function(aligned_data,
                                                  us_body,
                                                  n_positive = 5,
                                                  n_negative = 3,
                                                  context_pages = 3,
                                                  seed = 20251206) {

  set.seed(seed)

  examples <- list()

  # Generate positive examples (chunks containing acts)
  # Sample from different years to get variety
  sampled_acts <- aligned_data |>
    dplyr::slice_sample(n = min(n_positive * 2, nrow(aligned_data))) |>
    dplyr::slice_head(n = n_positive)

  for (i in seq_len(nrow(sampled_acts))) {
    act <- sampled_acts[i, ]

    # Find the document from us_body for this act's year
    doc_year <- act$year

    # Try to find ERP or budget document from same year or adjacent year
    doc_candidates <- us_body |>
      dplyr::filter(
        year >= doc_year - 1,
        year <= doc_year + 1,
        n_pages > 0
      ) |>
      dplyr::arrange(abs(year - doc_year))

    if (nrow(doc_candidates) == 0) {
      message(sprintf("No document found for act: %s (year %d)", act$act_name, doc_year))
      next
    }

    doc <- doc_candidates[1, ]

    # Create a synthetic chunk with the passage embedded
    chunk_input <- create_extraction_example_input(
      act = act,
      doc = doc,
      context_pages = context_pages
    )

    # Create expected output
    chunk_output <- list(
      acts = list(
        list(
          act_name = act$act_name,
          year = as.integer(act$year),
          passages = list(
            list(
              text = stringr::str_sub(act$passages_text, 1, 500),
              page_numbers = as.list(seq(chunk_input$start_page, chunk_input$end_page)),
              confidence = 0.95
            )
          ),
          reasoning = sprintf(
            "This passage describes the %s, a %s fiscal act. The language is contemporaneous, describing what the legislation does/provides.",
            act$act_name,
            tolower(act$motivation_category)
          )
        )
      ),
      no_acts_found = FALSE,
      extraction_notes = "Clear contemporaneous description of enacted legislation found."
    )

    examples[[length(examples) + 1]] <- list(
      input = chunk_input$text,
      output = chunk_output
    )
  }

  # Generate negative examples (chunks without acts)
  # Sample from documents that likely don't contain act descriptions
  negative_docs <- us_body |>
    dplyr::filter(n_pages > 10) |>
    dplyr::slice_sample(n = min(n_negative * 2, nrow(us_body)))

  for (i in seq_len(min(n_negative, nrow(negative_docs)))) {
    doc <- negative_docs[i, ]

    negative_input <- create_negative_extraction_example(doc, context_pages)

    negative_output <- list(
      acts = list(),
      no_acts_found = TRUE,
      extraction_notes = negative_input$notes
    )

    examples[[length(examples) + 1]] <- list(
      input = negative_input$text,
      output = negative_output
    )
  }

  message(sprintf(
    "Generated %d Model A extraction examples (%d positive, %d negative)",
    length(examples),
    min(n_positive, nrow(sampled_acts)),
    min(n_negative, nrow(negative_docs))
  ))

  examples
}


#' Create extraction example input from act and document
#'
#' @param act Row from aligned_data
#' @param doc Row from us_body
#' @param context_pages Number of pages of context
#'
#' @return List with text and metadata
create_extraction_example_input <- function(act, doc, context_pages = 3) {

  # Get pages from document
  pages <- doc$text[[1]]

  if (is.null(pages) || length(pages) == 0) {
    # Return minimal example if no pages
    return(list(
      text = glue::glue("
DOCUMENT: {doc$package_id}
DOCUMENT YEAR: {doc$year}
PAGES: 1 to 3

DOCUMENT TEXT:
{act$passages_text}
      "),
      start_page = 1,
      end_page = 3
    ))
  }

  n_pages <- length(pages)

  # Select a random starting point, ensuring we have enough pages
  max_start <- max(1, n_pages - context_pages)
  start_page <- sample(1:max_start, 1)
  end_page <- min(start_page + context_pages - 1, n_pages)

  # Get context pages
  context_text <- paste(pages[start_page:end_page], collapse = "\n\n--- PAGE BREAK ---\n\n")

  # Insert the passage text into the context (simulating finding it in the document)
  # For training examples, we prepend the actual passage
  combined_text <- paste(
    act$passages_text,
    "\n\n--- PAGE BREAK ---\n\n",
    context_text,
    sep = ""
  )

  list(
    text = glue::glue("
DOCUMENT: {doc$package_id}
DOCUMENT YEAR: {doc$year}
PAGES: {start_page} to {end_page + 1}

INSTRUCTIONS:
- Extract ALL fiscal act passages from this document chunk
- Page numbers in your output should be absolute (add {start_page - 1} to your page count)
- Group passages by act - if multiple passages describe the same act, include them all under one entry

DOCUMENT TEXT:
{combined_text}
    "),
    start_page = start_page,
    end_page = end_page + 1
  )
}


#' Create negative extraction example from document
#'
#' Selects pages from a document that are unlikely to contain act descriptions.
#'
#' @param doc Row from us_body
#' @param context_pages Number of pages
#'
#' @return List with text and notes
create_negative_extraction_example <- function(doc, context_pages = 3) {

  pages <- doc$text[[1]]

  if (is.null(pages) || length(pages) == 0) {
    return(list(
      text = "No text available.",
      notes = "Empty document chunk."
    ))
  }

  n_pages <- length(pages)

  # Try to find pages without act-like keywords
  act_pattern <- "(?i)\\b(act|bill|law|amendment|legislation)\\s+(of\\s+)?\\d{4}\\b"

  non_act_pages <- which(!sapply(pages, function(p) {
    stringr::str_detect(p, act_pattern)
  }))

  if (length(non_act_pages) >= context_pages) {
    # Use consecutive non-act pages
    start_idx <- sample(1:(length(non_act_pages) - context_pages + 1), 1)
    selected_indices <- non_act_pages[start_idx:(start_idx + context_pages - 1)]
  } else {
    # Fall back to random selection from the middle/end of document
    # (front matter often has act descriptions)
    middle_start <- floor(n_pages / 2)
    start_page <- sample(middle_start:max(middle_start, n_pages - context_pages), 1)
    selected_indices <- start_page:min(start_page + context_pages - 1, n_pages)
  }

  context_text <- paste(pages[selected_indices], collapse = "\n\n--- PAGE BREAK ---\n\n")
  start_page <- min(selected_indices)
  end_page <- max(selected_indices)

  # Determine reason for no acts
  notes <- dplyr::case_when(
    stringr::str_detect(context_text, "(?i)table|figure|chart") ~
      "This chunk contains primarily tables and figures without act descriptions.",
    stringr::str_detect(context_text, "(?i)appendix|annex") ~
      "This chunk is from an appendix section without contemporaneous act descriptions.",
    stringr::str_detect(context_text, "(?i)forecast|projection|estimate") ~
      "This chunk contains budget projections but no specific enacted legislation.",
    TRUE ~
      "This chunk contains general economic discussion but no specific fiscal act descriptions."
  )

  list(
    text = glue::glue("
DOCUMENT: {doc$package_id}
DOCUMENT YEAR: {doc$year}
PAGES: {start_page} to {end_page}

INSTRUCTIONS:
- Extract ALL fiscal act passages from this document chunk
- Page numbers in your output should be absolute
- If no fiscal acts are found, return no_acts_found: true

DOCUMENT TEXT:
{context_text}
    "),
    notes = notes
  )
}
