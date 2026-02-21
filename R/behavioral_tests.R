# Behavioral Tests for H&K Codebook Validation
# Generic test functions reusable for C1-C4
#
# S1 Tests (I-IV): Run before evaluation
# S3 Tests (V-VII): Run during error analysis

# =============================================================================
# S1 Behavioral Tests (Pre-Evaluation)
# =============================================================================

#' Test I: Legal Outputs
#'
#' Verifies the model always returns valid JSON with valid labels
#' for a set of test texts. Uses temperature=0 for determinism.
#'
#' @param codebook A validated codebook object
#' @param test_texts Character vector of test passages
#' @param model Character model ID (default: "claude-haiku-4-5-20251001")
#' @param max_tokens Integer max output tokens
#' @return List with pass (logical), n_valid, n_total, details (tibble)
#' @export
test_legal_outputs <- function(codebook,
                               test_texts,
                               model = "claude-haiku-4-5-20251001",
                               max_tokens = 500) {
  valid_labels <- get_valid_labels(codebook)
  system_prompt <- construct_codebook_prompt(codebook)
  n <- length(test_texts)

  results <- purrr::map(seq_along(test_texts), function(i) {
    response <- tryCatch({
      classify_with_codebook(
        text = test_texts[i],
        codebook = codebook,
        model = model,
        temperature = 0,
        system_prompt = system_prompt,
        max_tokens = max_tokens
      )
    }, error = function(e) {
      list(label = NA_character_, reasoning = e$message)
    })

    tibble::tibble(
      text_id = i,
      label = response$label %||% NA_character_,
      valid_json = !is.na(response$label),
      valid_label = response$label %in% valid_labels,
      reasoning = response$reasoning %||% NA_character_
    )
  })

  details <- dplyr::bind_rows(results)
  n_valid <- sum(details$valid_json & details$valid_label, na.rm = TRUE)

  list(
    test = "I_legal_outputs",
    pass = n_valid == n,
    n_valid = n_valid,
    n_total = n,
    rate = n_valid / n,
    threshold = 1.0,
    details = details
  )
}


#' Test II: Definition Recovery
#'
#' Feeds each label's definition as input text and verifies the model
#' returns the correct label. Tests whether the model can recognize
#' prototypical descriptions.
#'
#' @param codebook A validated codebook object
#' @param model Character model ID
#' @return List with pass (logical), n_correct, n_total, details
#' @export
test_definition_recovery <- function(codebook,
                                     model = "claude-haiku-4-5-20251001") {
  system_prompt <- construct_codebook_prompt(codebook)
  valid_labels <- get_valid_labels(codebook)

  results <- purrr::map(codebook$classes, function(cls) {
    # Frame as label-matching task, NOT passage classification (H&K spec)
    user_message <- paste0(
      "The following is a class definition from the codebook. ",
      "Return the label that this definition corresponds to.\n\n",
      "Definition: ", cls$label_definition, "\n\n",
      "Return your answer as JSON:\n",
      '{"label": "<the matching label>", "reasoning": "Brief explanation"}'
    )

    response <- tryCatch({
      raw <- call_claude_api(
        messages = list(list(role = "user", content = user_message)),
        model = model,
        max_tokens = 300,
        temperature = 0,
        system = system_prompt
      )
      parsed <- parse_json_response(
        raw$content[[1]]$text,
        required_fields = c("label")
      )
      label <- if (!is.null(parsed$label) && parsed$label %in% valid_labels) {
        parsed$label
      } else {
        NA_character_
      }
      list(label = label, reasoning = parsed$reasoning %||% NA_character_)
    }, error = function(e) {
      list(label = NA_character_, reasoning = e$message)
    })

    tibble::tibble(
      true_label = cls$label,
      pred_label = response$label %||% NA_character_,
      correct = identical(response$label, cls$label)
    )
  })

  details <- dplyr::bind_rows(results)
  n_correct <- sum(details$correct, na.rm = TRUE)

  list(
    test = "II_definition_recovery",
    pass = n_correct == nrow(details),
    n_correct = n_correct,
    n_total = nrow(details),
    rate = n_correct / nrow(details),
    threshold = 1.0,
    details = details
  )
}


#' Test III: Example Recovery
#'
#' Feeds each positive and negative example from the codebook and verifies
#' the model returns correct labels. This is a memorization test per H&K:
#' "we provide verbatim examples from the codebook and ask for their labels."
#' Uses a recall-framed prompt (not classification) so the model pattern-matches
#' against examples it already saw in the system prompt.
#'
#' @param codebook A validated codebook object
#' @param model Character model ID
#' @return List with pass, n_correct, n_total, details
#' @export
test_example_recovery <- function(codebook,
                                  model = "claude-haiku-4-5-20251001") {
  system_prompt <- construct_codebook_prompt(codebook)
  valid_labels <- get_valid_labels(codebook)
  results <- list()

  for (cls in codebook$classes) {
    # Test positive examples — should return THIS class label
    for (i in seq_along(cls$positive_examples)) {
      ex <- cls$positive_examples[[i]]

      # Recall-framed prompt: ask the model to recall the label, not classify
      user_message <- paste0(
        "The following text appears verbatim as an example in the codebook. ",
        "What label is it associated with?\n\n",
        "Text: ", ex$text, "\n\n",
        "Return your answer as JSON:\n",
        '{"label": "<the label>", "reasoning": "Brief explanation"}'
      )

      response <- tryCatch({
        raw <- call_claude_api(
          messages = list(list(role = "user", content = user_message)),
          model = model,
          max_tokens = 300,
          temperature = 0,
          system = system_prompt
        )
        parsed <- parse_json_response(
          raw$content[[1]]$text,
          required_fields = c("label")
        )
        label <- if (!is.null(parsed$label) && parsed$label %in% valid_labels) {
          parsed$label
        } else {
          NA_character_
        }
        list(label = label, reasoning = parsed$reasoning %||% NA_character_)
      }, error = function(e) {
        list(label = NA_character_, reasoning = e$message)
      })

      results[[length(results) + 1]] <- tibble::tibble(
        class = cls$label,
        example_type = "positive",
        example_idx = i,
        true_label = cls$label,
        pred_label = response$label %||% NA_character_,
        correct = identical(response$label, cls$label)
      )
    }

    # Test negative examples — should NOT return THIS class label
    other_labels <- setdiff(valid_labels, cls$label)

    for (i in seq_along(cls$negative_examples)) {
      ex <- cls$negative_examples[[i]]

      # Same recall-framed prompt — neutral, doesn't hint positive/negative
      user_message <- paste0(
        "The following text appears verbatim as an example in the codebook. ",
        "What label is it associated with?\n\n",
        "Text: ", ex$text, "\n\n",
        "Return your answer as JSON:\n",
        '{"label": "<the label>", "reasoning": "Brief explanation"}'
      )

      response <- tryCatch({
        raw <- call_claude_api(
          messages = list(list(role = "user", content = user_message)),
          model = model,
          max_tokens = 300,
          temperature = 0,
          system = system_prompt
        )
        parsed <- parse_json_response(
          raw$content[[1]]$text,
          required_fields = c("label")
        )
        label <- if (!is.null(parsed$label) && parsed$label %in% valid_labels) {
          parsed$label
        } else {
          NA_character_
        }
        list(label = label, reasoning = parsed$reasoning %||% NA_character_)
      }, error = function(e) {
        list(label = NA_character_, reasoning = e$message)
      })

      # For binary codebooks: negative example of class X should be the other class
      # For multi-class: just check it's NOT this class
      results[[length(results) + 1]] <- tibble::tibble(
        class = cls$label,
        example_type = "negative",
        example_idx = i,
        true_label = paste(other_labels, collapse = "/"),
        pred_label = response$label %||% NA_character_,
        correct = response$label %in% other_labels
      )
    }
  }

  details <- dplyr::bind_rows(results)
  n_correct <- sum(details$correct, na.rm = TRUE)

  list(
    test = "III_example_recovery",
    pass = n_correct == nrow(details),
    n_correct = n_correct,
    n_total = nrow(details),
    rate = n_correct / nrow(details),
    threshold = 1.0,
    details = details
  )
}


#' Test IV: Order Invariance
#'
#' Classifies test texts with original class order and reversed order.
#' Measures label change rate — should be <5%.
#'
#' @param codebook A validated codebook object
#' @param test_texts Character vector of test passages
#' @param model Character model ID
#' @return List with pass, change_rate, threshold, details
#' @export
test_order_invariance <- function(codebook,
                                  test_texts,
                                  model = "claude-haiku-4-5-20251001") {
  n_classes <- length(codebook$classes)
  original_order <- seq_len(n_classes)
  reversed_order <- rev(original_order)

  # Classify with original order
  prompt_original <- construct_codebook_prompt(codebook, class_order = original_order)
  # Classify with reversed order
  prompt_reversed <- construct_codebook_prompt(codebook, class_order = reversed_order)

  results <- purrr::map(seq_along(test_texts), function(i) {
    pred_original <- tryCatch({
      classify_with_codebook(
        text = test_texts[i],
        codebook = codebook,
        model = model,
        temperature = 0,
        system_prompt = prompt_original
      )$label
    }, error = function(e) NA_character_)

    pred_reversed <- tryCatch({
      classify_with_codebook(
        text = test_texts[i],
        codebook = codebook,
        model = model,
        temperature = 0,
        system_prompt = prompt_reversed
      )$label
    }, error = function(e) NA_character_)

    tibble::tibble(
      text_id = i,
      label_original = pred_original %||% NA_character_,
      label_reversed = pred_reversed %||% NA_character_,
      changed = !identical(pred_original, pred_reversed)
    )
  })

  details <- dplyr::bind_rows(results)
  n_changed <- sum(details$changed, na.rm = TRUE)
  change_rate <- n_changed / nrow(details)

  list(
    test = "IV_order_invariance",
    pass = change_rate < 0.05,
    change_rate = change_rate,
    n_changed = n_changed,
    n_total = nrow(details),
    threshold = 0.05,
    details = details
  )
}


# =============================================================================
# S3 Behavioral Tests (Error Analysis)
# =============================================================================

#' Test V: Exclusion Criteria
#'
#' Removes each negative clarification one at a time and measures whether
#' errors increase for the corresponding confusion pattern. Tests whether
#' each exclusion criterion contributes independently.
#'
#' @param codebook A validated codebook object
#' @param test_texts Character vector of test passages
#' @param true_labels Character vector of true labels
#' @param model Character model ID
#' @return List with results per excluded component
#' @export
test_exclusion_criteria <- function(codebook,
                                    test_texts,
                                    true_labels,
                                    model = "claude-haiku-4-5-20251001") {
  # Get baseline accuracy
  baseline <- classify_batch_for_test(
    codebook, test_texts, model, system_prompt = NULL
  )
  baseline_acc <- mean(baseline == true_labels, na.rm = TRUE)

  # Test removing each negative clarification from each class
  results <- list()
  for (cls in codebook$classes) {
    for (j in seq_along(cls$negative_clarification)) {
      exclude <- stats::setNames(
        list(paste0("negative_clarification_", j)),
        cls$label
      )
      ablated_prompt <- construct_codebook_prompt(
        codebook, exclude_components = exclude
      )
      ablated_preds <- classify_batch_for_test(
        codebook, test_texts, model, system_prompt = ablated_prompt
      )
      ablated_acc <- mean(ablated_preds == true_labels, na.rm = TRUE)

      results[[length(results) + 1]] <- tibble::tibble(
        class = cls$label,
        component = paste0("negative_clarification_", j),
        component_text = cls$negative_clarification[[j]],
        baseline_accuracy = baseline_acc,
        ablated_accuracy = ablated_acc,
        accuracy_drop = baseline_acc - ablated_acc
      )
    }
  }

  list(
    test = "V_exclusion_criteria",
    results = dplyr::bind_rows(results),
    baseline_accuracy = baseline_acc
  )
}


#' Test VI: Generic Labels
#'
#' Replaces semantically meaningful label names with generic LABEL_1, LABEL_2, etc.
#' Large prediction changes suggest the model relies on label semantics rather
#' than definitions.
#'
#' @param codebook A validated codebook object
#' @param test_texts Character vector of test passages
#' @param true_labels Character vector of true labels
#' @param model Character model ID
#' @return List with original vs generic predictions and change rate
#' @export
test_generic_labels <- function(codebook,
                                test_texts,
                                true_labels,
                                model = "claude-haiku-4-5-20251001") {
  # Create a modified codebook with generic labels
  generic_codebook <- codebook
  label_map <- list()  # original -> generic

  for (i in seq_along(generic_codebook$classes)) {
    original_label <- generic_codebook$classes[[i]]$label
    generic_label <- paste0("LABEL_", i)
    label_map[[original_label]] <- generic_label
    generic_codebook$classes[[i]]$label <- generic_label
  }
  attr(generic_codebook, "valid_labels") <- unlist(label_map, use.names = FALSE)

  # Update output_instructions to use generic labels
  for (orig in names(label_map)) {
    generic_codebook$output_instructions <- gsub(
      orig, label_map[[orig]], generic_codebook$output_instructions
    )
  }

  # Classify with original labels
  original_preds <- classify_batch_for_test(codebook, test_texts, model)

  # Classify with generic labels
  generic_preds <- classify_batch_for_test(generic_codebook, test_texts, model)

  # Map generic predictions back to original labels for comparison
  reverse_map <- stats::setNames(names(label_map), unlist(label_map))
  generic_preds_mapped <- reverse_map[generic_preds]

  # Compute metrics
  original_acc <- mean(original_preds == true_labels, na.rm = TRUE)
  generic_acc <- mean(generic_preds_mapped == true_labels, na.rm = TRUE)
  change_rate <- mean(original_preds != generic_preds_mapped, na.rm = TRUE)

  list(
    test = "VI_generic_labels",
    original_accuracy = original_acc,
    generic_accuracy = generic_acc,
    accuracy_difference = original_acc - generic_acc,
    change_rate = change_rate,
    label_map = label_map,
    details = tibble::tibble(
      text_id = seq_along(test_texts),
      true_label = true_labels,
      original_pred = original_preds,
      generic_pred_mapped = generic_preds_mapped,
      changed = original_preds != generic_preds_mapped
    )
  )
}


#' Test VII: Swapped Labels
#'
#' Swaps label definitions across label names. If predictions follow
#' the swapped names rather than swapped definitions, the model is
#' ignoring definitions entirely.
#'
#' @param codebook A validated codebook object
#' @param test_texts Character vector of test passages
#' @param true_labels Character vector of true labels
#' @param model Character model ID
#' @return List with original vs swapped predictions
#' @export
test_swapped_labels <- function(codebook,
                                test_texts,
                                true_labels,
                                model = "claude-haiku-4-5-20251001") {
  n_classes <- length(codebook$classes)
  if (n_classes < 2) {
    stop("Need at least 2 classes for swapped label test")
  }

  # Create swapped codebook: rotate definitions by one position
  # Label names stay the same, but definitions/clarifications rotate
  swapped_codebook <- codebook
  for (i in seq_len(n_classes)) {
    source_idx <- (i %% n_classes) + 1  # Rotate by one
    swapped_codebook$classes[[i]]$label_definition <-
      codebook$classes[[source_idx]]$label_definition
    swapped_codebook$classes[[i]]$clarification <-
      codebook$classes[[source_idx]]$clarification
    swapped_codebook$classes[[i]]$negative_clarification <-
      codebook$classes[[source_idx]]$negative_clarification
  }

  # Classify with original
  original_preds <- classify_batch_for_test(codebook, test_texts, model)

  # Classify with swapped definitions
  swapped_preds <- classify_batch_for_test(swapped_codebook, test_texts, model)

  # If model follows definitions: predictions should rotate
  # If model follows names: predictions should stay the same
  # Build the definition mapping
  def_map <- stats::setNames(
    vapply(codebook$classes, function(c) c$label, character(1)),
    vapply(seq_len(n_classes), function(i) {
      codebook$classes[[(i %% n_classes) + 1]]$label
    }, character(1))
  )

  follows_definitions <- mean(
    swapped_preds == def_map[original_preds], na.rm = TRUE
  )
  follows_names <- mean(swapped_preds == original_preds, na.rm = TRUE)

  list(
    test = "VII_swapped_labels",
    follows_definitions_rate = follows_definitions,
    follows_names_rate = follows_names,
    interpretation = if (follows_names > follows_definitions) {
      "WARNING: Model appears to rely on label names rather than definitions"
    } else {
      "Model appears to follow definitions rather than label names"
    },
    details = tibble::tibble(
      text_id = seq_along(test_texts),
      true_label = true_labels,
      original_pred = original_preds,
      swapped_pred = swapped_preds
    )
  )
}


# =============================================================================
# Internal Helpers
# =============================================================================

#' Classify a batch of texts for behavioral testing
#'
#' @param codebook Codebook object
#' @param texts Character vector of texts
#' @param model Model ID
#' @param system_prompt Optional override system prompt
#' @return Character vector of predicted labels
#' @keywords internal
classify_batch_for_test <- function(codebook, texts, model,
                                    system_prompt = NULL) {
  if (is.null(system_prompt)) {
    system_prompt <- construct_codebook_prompt(codebook)
  }

  purrr::map_chr(texts, function(txt) {
    tryCatch({
      result <- classify_with_codebook(
        text = txt,
        codebook = codebook,
        model = model,
        temperature = 0,
        system_prompt = system_prompt
      )
      result$label %||% NA_character_
    }, error = function(e) {
      NA_character_
    })
  })
}


# Null coalescing operator
if (!exists("%||%", mode = "function", envir = environment())) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
