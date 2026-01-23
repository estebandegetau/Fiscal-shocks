# Training Data Preparation Functions for Phase 0
# Created: 2026-01-19
# Purpose: Align labels with shocks, create train/val/test splits for LLM models
#
# Note: Packages loaded by targets pipeline (tidyverse, stringdist)

#' Clean act names by normalizing whitespace
#'
#' @param act_name Character vector of act names
#' @return Character vector with normalized whitespace
clean_act_name <- function(act_name) {
  act_name %>%
    str_trim() %>%
    str_squish() %>%  # Replace multiple spaces with single space
    str_replace_all("\\s+", " ")
}

#' Align us_labels passages with us_shocks labels using fuzzy matching
#'
#' @param us_labels Tibble with columns: act_name, exogeneity, category, motivation, source, date
#' @param us_shocks Tibble with columns: act_name, date_signed, change_in_liabilities_*, present_value_*, reasoning
#' @param threshold Similarity threshold for fuzzy matching (default 0.9)
#' @return Tibble with aligned labels and shocks data (one row per act, with nested shock details)
align_labels_shocks <- function(us_labels, us_shocks, threshold = 0.9) {

  # Clean act names in both datasets
  labels_clean <- us_labels %>%
    mutate(act_name_clean = clean_act_name(act_name))

  # Prepare shocks data:
  # 1. For each act, nest all quarters for Model C multi-quarter extraction
  # 2. Keep first quarter metadata for joining with labels (backward compatibility)

  # Clean and group shocks by act
  shocks_clean <- us_shocks %>%
    mutate(act_name_clean = clean_act_name(act_name)) %>%
    group_by(act_name_clean) %>%
    arrange(change_in_liabilities_quarter, .by_group = TRUE) %>%
    summarize(
      # Take first quarter's metadata for backward compatibility
      act_name = first(act_name),
      date_signed = first(date_signed),
      change_quarter = first(change_in_liabilities_quarter),
      magnitude_billions = first(change_in_liabilities_billion),
      motivation_category = first(change_in_liabilities_category),
      exogenous_flag = first(change_in_liabilities_exo),
      present_value_quarter = first(present_value_quarter),
      present_value_billions = first(present_value_billion),
      reasoning = first(reasoning),
      # Nest ALL quarters for Model C
      ground_truth_quarters = list(tibble(
        change_in_liabilities_quarter = change_in_liabilities_quarter,
        change_in_liabilities_billion = change_in_liabilities_billion,
        change_in_liabilities_category = change_in_liabilities_category,
        change_in_liabilities_exo = change_in_liabilities_exo,
        present_value_quarter = present_value_quarter,
        present_value_billion = present_value_billion,
        reasoning = reasoning
      )),
      .groups = "drop"
    )

  # Get unique acts from labels (with their original passages)
  # Note: labels has multiple rows per act (one per passage)
  # We'll group them later after joining

  # Try exact match first
  exact_match <- labels_clean %>%
    inner_join(
      shocks_clean %>%
        select(
          act_name_clean,
          date_signed,
          change_quarter,
          magnitude_billions,
          motivation_category,
          exogenous_flag,
          present_value_quarter,
          present_value_billions,
          reasoning,
          ground_truth_quarters  # NEW: Include nested quarters
        ),
      by = "act_name_clean",
      relationship = "many-to-one"
    ) %>%
    select(-act_name_clean)

  # Find unmatched acts in labels
  matched_acts <- unique(exact_match$act_name)
  unmatched_labels <- labels_clean %>%
    filter(!act_name %in% matched_acts)

  if (nrow(unmatched_labels) > 0) {
    message(sprintf("Exact match: %d/%d acts matched",
                    length(matched_acts),
                    n_distinct(labels_clean$act_name)))

    # Try fuzzy matching for unmatched acts
    unmatched_act_names <- unique(unmatched_labels$act_name_clean)
    shocks_act_names <- unique(shocks_clean$act_name_clean)

    fuzzy_matches <- tibble(
      labels_act = unmatched_act_names
    ) %>%
      rowwise() %>%
      mutate(
        # Find best match in shocks
        similarity = map_dbl(labels_act, function(la) {
          max(stringsim(la, shocks_act_names, method = "jw"))
        }),
        best_match = map_chr(labels_act, function(la) {
          idx <- which.max(stringsim(la, shocks_act_names, method = "jw"))
          shocks_act_names[idx]
        })
      ) %>%
      ungroup() %>%
      filter(similarity >= threshold)

    if (nrow(fuzzy_matches) > 0) {
      message(sprintf("Fuzzy match: %d additional acts matched (threshold %.2f)",
                      nrow(fuzzy_matches), threshold))

      # Join fuzzy matched acts
      fuzzy_aligned <- unmatched_labels %>%
        inner_join(
          fuzzy_matches,
          by = c("act_name_clean" = "labels_act")
        ) %>%
        inner_join(
          shocks_clean %>%
            select(
              act_name_clean,
              date_signed,
              change_quarter,
              magnitude_billions,
              motivation_category,
              exogenous_flag,
              present_value_quarter,
              present_value_billions,
              reasoning,
              ground_truth_quarters  # NEW: Include nested quarters
            ),
          by = c("best_match" = "act_name_clean"),
          relationship = "many-to-one"
        ) %>%
        select(-act_name_clean, -similarity, -best_match)

      # Combine exact and fuzzy matches
      exact_match <- bind_rows(exact_match, fuzzy_aligned)
    }
  }

  # Group by act_name and concatenate passages
  # Note: ground_truth_quarters is a list-column that's preserved through grouping
  aligned_data <- exact_match %>%
    group_by(
      act_name,
      date_signed,
      change_quarter,
      magnitude_billions,
      motivation_category,
      exogenous_flag,
      present_value_quarter,
      present_value_billions,
      reasoning,
      ground_truth_quarters  # NEW: Preserve nested quarters
    ) %>%
    summarize(
      n_passages = n(),
      passages_text = paste(motivation, collapse = "\n\n"),
      passage_sources = paste(unique(source), collapse = ", "),
      .groups = "drop"
    ) %>%
    mutate(
      year = lubridate::year(date_signed),
      exogenous = exogenous_flag == "Exogenous"
    )

  message(sprintf("Final alignment: %d acts with %d total passages",
                  nrow(aligned_data),
                  sum(aligned_data$n_passages)))

  return(aligned_data)
}

#' Create stratified train/validation/test splits
#'
#' @param aligned_data Output from align_labels_shocks()
#' @param ratios Numeric vector of split ratios (default c(0.6, 0.2, 0.2))
#' @param seed Random seed for reproducibility (default 20251206)
#' @param stratify_by Column name to stratify by (default "motivation_category")
#' @return Tibble with added 'split' column
create_train_val_test_splits <- function(
    aligned_data,
    ratios = c(0.6, 0.2, 0.2),
    seed = 20251206,
    stratify_by = "motivation_category"
) {

  if (sum(ratios) != 1.0) {
    stop("Ratios must sum to 1.0")
  }

  set.seed(seed)

  # Stratified split by motivation category
  split_data <- aligned_data %>%
    group_by(across(all_of(stratify_by))) %>%
    mutate(
      n_in_category = n(),
      # Assign splits proportionally
      split_id = sample(
        c(
          rep("train", ceiling(n() * ratios[1])),
          rep("val", ceiling(n() * ratios[2])),
          rep("test", n() - ceiling(n() * ratios[1]) - ceiling(n() * ratios[2]))
        ),
        size = n(),
        replace = FALSE
      )
    ) %>%
    ungroup() %>%
    select(-n_in_category) %>%
    rename(split = split_id)

  # Verify splits
  split_summary <- split_data %>%
    count(split, across(all_of(stratify_by))) %>%
    pivot_wider(
      names_from = split,
      values_from = n,
      values_fill = 0
    )

  message("Split summary:")
  message(paste(capture.output(print(split_summary)), collapse = "\n"))

  overall <- split_data %>% count(split)
  message(sprintf("\nOverall: train=%d, val=%d, test=%d",
                  overall$n[overall$split == "train"],
                  overall$n[overall$split == "val"],
                  overall$n[overall$split == "test"]))

  return(split_data)
}

#' Generate negative examples for Model A (act detection)
#'
#' @param body_data us_body target output with extracted text
#' @param n Number of negative examples to generate (default 200)
#' @param seed Random seed (default 20251206)
#' @return Tibble with negative examples (paragraphs without act mentions)
generate_negative_examples <- function(body_data, n = 200, seed = 20251206) {

  set.seed(seed)

  # Extract paragraphs from body text
  # Filter for successful extractions
  docs_with_text <- body_data %>%
    filter(n_pages > 0) %>%
    select(year, body, source, package_id, text)

  # Sample random documents and extract paragraphs
  message(sprintf("Sampling from %d documents...", nrow(docs_with_text)))

  # Extract paragraphs from sampled documents
  paragraphs <- docs_with_text %>%
    sample_n(min(100, nrow(docs_with_text))) %>%  # Sample 100 docs
    mutate(
      full_text = map_chr(text, function(text_list) {
        if (is.null(text_list) || length(text_list) == 0) return("")
        pages <- if (is.list(text_list[[1]])) text_list[[1]] else text_list
        if (length(pages) == 0) return("")
        paste(pages, collapse = "\n\n")
      })
    ) %>%
    filter(nchar(full_text) > 100) %>%
    mutate(
      # Split into paragraphs (simple approach: by double newline)
      paragraphs = str_split(full_text, "\\n\\n+")
    ) %>%
    select(year, body, source, package_id, paragraphs) %>%
    unnest(paragraphs) %>%
    mutate(
      # Clean paragraphs
      paragraph = str_trim(paragraphs),
      n_words = str_count(paragraph, "\\S+")
    ) %>%
    filter(
      n_words >= 50,  # At least 50 words
      n_words <= 500,  # Not too long
      nchar(paragraph) > 200  # At least 200 characters
    )

  message(sprintf("Extracted %d candidate paragraphs", nrow(paragraphs)))

  # Filter out paragraphs that likely mention acts
  # Detection heuristic: contains "act", "bill", "law", "amendment" + year
  act_pattern <- regex(
    "\\b(act|bill|law|amendment|legislation|public law)\\s+(of\\s+)?\\d{4}\\b",
    ignore_case = TRUE
  )

  negative_candidates <- paragraphs %>%
    filter(!str_detect(paragraph, act_pattern)) %>%
    # Also filter out paragraphs with specific act keywords
    filter(!str_detect(paragraph, regex("tax reform|revenue act|appropriation", ignore_case = TRUE)))

  message(sprintf("After filtering act mentions: %d paragraphs",
                  nrow(negative_candidates)))

  # Sample n examples
  if (nrow(negative_candidates) < n) {
    warning(sprintf("Only %d negative examples available (requested %d)",
                    nrow(negative_candidates), n))
    n <- nrow(negative_candidates)
  }

  negative_examples <- negative_candidates %>%
    sample_n(n) %>%
    select(
      text = paragraph,
      year,
      body,
      source,
      package_id,
      n_words
    ) %>%
    mutate(
      is_fiscal_act = 0,
      act_name = NA_character_
    )

  message(sprintf("Generated %d negative examples", nrow(negative_examples)))

  return(negative_examples)
}

#' Prepare Model A training data (binary act detection)
#'
#' @param aligned_data Output from align_labels_shocks() with split column
#' @param negative_examples Output from generate_negative_examples()
#' @return Tibble ready for Model A training
prepare_model_a_data <- function(aligned_data, negative_examples) {

  # Positive examples: each passage from aligned data
  positive_examples <- aligned_data %>%
    mutate(
      text = passages_text,
      is_fiscal_act = 1
    ) %>%
    select(text, is_fiscal_act, act_name, split, year, motivation_category)

  # Combine positive and negative examples
  # Assign splits to negatives proportionally
  split_counts <- positive_examples %>% count(split)
  total_pos <- nrow(positive_examples)

  negatives_with_split <- negative_examples %>%
    mutate(
      split = sample(
        c(
          rep("train", round(nrow(.) * split_counts$n[split_counts$split == "train"] / total_pos)),
          rep("val", round(nrow(.) * split_counts$n[split_counts$split == "val"] / total_pos)),
          rep("test", nrow(.) - round(nrow(.) * split_counts$n[split_counts$split == "train"] / total_pos) -
            round(nrow(.) * split_counts$n[split_counts$split == "val"] / total_pos))
        ),
        size = nrow(.),
        replace = FALSE
      ),
      motivation_category = NA_character_
    ) %>%
    select(text, is_fiscal_act, act_name, split, year, motivation_category, source, body)

  # Combine
  model_a_data <- bind_rows(
    positive_examples %>% mutate(source = NA_character_, body = NA_character_),
    negatives_with_split
  )

  message(sprintf("Model A data: %d examples (pos=%d, neg=%d)",
                  nrow(model_a_data),
                  sum(model_a_data$is_fiscal_act == 1),
                  sum(model_a_data$is_fiscal_act == 0)))

  return(model_a_data)
}

#' Prepare Model B training data (motivation classification)
#'
#' @param aligned_data Output from align_labels_shocks() with split column
#' @return Tibble ready for Model B training
prepare_model_b_data <- function(aligned_data) {

  model_b_data <- aligned_data %>%
    select(
      act_name,
      passages_text,
      year,
      motivation = motivation_category,
      exogenous,
      split
    )

  message(sprintf("Model B data: %d acts", nrow(model_b_data)))
  message("Class distribution:")
  class_dist <- model_b_data %>% count(motivation, split) %>%
    pivot_wider(names_from = split, values_from = n, values_fill = 0)
  message(paste(capture.output(print(class_dist)), collapse = "\n"))

  return(model_b_data)
}

#' Prepare Model C training data (information extraction with multi-quarter support)
#'
#' @param aligned_data Output from align_labels_shocks() with split column and ground_truth_quarters
#' @return Tibble ready for Model C training with nested ground truth quarters
prepare_model_c_data <- function(aligned_data) {

  # Filter for acts with at least ONE complete quarter
  # Uses nested ground_truth_quarters instead of first quarter metadata
  model_c_data <- aligned_data %>%
    filter(
      # Has ground truth quarters AND at least one quarter has complete data
      !is.na(ground_truth_quarters),
      purrr::map_lgl(ground_truth_quarters, ~ {
        nrow(.x) > 0 &&
        !all(is.na(.x$change_in_liabilities_quarter)) &&
        !all(is.na(.x$change_in_liabilities_billion))
      })
    ) %>%
    select(
      act_name,
      passages_text,
      year,
      date_signed,
      ground_truth_quarters,  # Full time series for multi-quarter evaluation
      split
    )

  # Calculate total quarters available
  total_quarters <- sum(purrr::map_int(model_c_data$ground_truth_quarters, nrow))

  message(sprintf("Model C data: %d acts with complete data", nrow(model_c_data)))
  message(sprintf("Total quarters across all acts: %d", total_quarters))
  message(sprintf("Median quarters per act: %.1f",
                  median(purrr::map_int(model_c_data$ground_truth_quarters, nrow))))
  message(sprintf("Filtered out: %d acts with incomplete timing/magnitude",
                  nrow(aligned_data) - nrow(model_c_data)))

  return(model_c_data)
}
