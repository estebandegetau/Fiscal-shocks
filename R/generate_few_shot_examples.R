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
    dplyr::mutate(
      input = text,
      output = list(list(
        contains_act = TRUE,
        act_name = act_name,
        confidence = 0.95,
        reasoning = sprintf("This passage clearly describes %s, which is a specific piece of federal fiscal legislation.", act_name)
      ))
    ) |>
    dplyr::select(input, output)

  # Sample negative examples (does not contain fiscal act)
  negative_examples <- training_data_a |>
    dplyr::filter(is_fiscal_act == 0, split == "train") |>
    dplyr::slice_sample(n = n_negative) |>
    dplyr::mutate(
      input = text,
      output = list(list(
        contains_act = FALSE,
        act_name = NA_character_,
        confidence = 0.90,
        reasoning = "This passage contains general economic discussion but does not describe a specific fiscal policy act."
      ))
    ) |>
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
