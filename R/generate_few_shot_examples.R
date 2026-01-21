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


#' Save few-shot examples to JSON file
#'
#' @param examples List of examples from generate_model_a_examples()
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
