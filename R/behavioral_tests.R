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
                               max_tokens = 1024,
                               provider = "anthropic",
                               base_url = NULL,
                               api_key = NULL) {
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
        max_tokens = max_tokens,
        provider = provider,
        base_url = base_url,
        api_key = api_key
      )
    }, error = function(e) {
      list(label = NA_character_, reasoning = e$message,
           raw_response = NA_character_, stop_reason = NA_character_)
    })

    tibble::tibble(
      text_id = i,
      label = response$label %||% NA_character_,
      valid_json = !is.na(response$label),
      valid_label = response$label %in% valid_labels,
      reasoning = response$reasoning %||% NA_character_,
      raw_response = response$raw_response %||% NA_character_,
      stop_reason = response$stop_reason %||% NA_character_
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
                                     model = "claude-haiku-4-5-20251001",
                                     max_tokens = 1024,
                                     provider = "anthropic",
                                     base_url = NULL,
                                     api_key = NULL) {
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
      raw <- call_llm_api(
        messages = list(list(role = "user", content = user_message)),
        model = model,
        max_tokens = max_tokens,
        temperature = 0,
        system = system_prompt,
        provider = provider,
        base_url = base_url,
        api_key = api_key
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
                                  model = "claude-haiku-4-5-20251001",
                                  max_tokens = 1024,
                                  provider = "anthropic",
                                  base_url = NULL,
                                  api_key = NULL) {
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
        raw <- call_llm_api(
          messages = list(list(role = "user", content = user_message)),
          model = model,
          max_tokens = max_tokens,
          temperature = 0,
          system = system_prompt,
          provider = provider,
          base_url = base_url,
          api_key = api_key
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
        raw <- call_llm_api(
          messages = list(list(role = "user", content = user_message)),
          model = model,
          max_tokens = max_tokens,
          temperature = 0,
          system = system_prompt,
          provider = provider,
          base_url = base_url,
          api_key = api_key
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


#' Fleiss's Kappa for Inter-Rater Agreement
#'
#' Computes Fleiss (1971) kappa for n subjects rated by r raters into k
#' categories. Used as a diagnostic in Test IV to measure agreement across
#' three class orderings treated as "raters."
#'
#' @param ratings Character matrix (n_subjects x n_raters). Each cell is a
#'   category label. Rows with any NA are dropped before computation.
#' @return List with kappa (numeric) and interpretation (character) per
#'   Landis & Koch (1977)
#' @keywords internal
fleiss_kappa <- function(ratings) {
  # Drop rows with any NA
  complete <- complete.cases(ratings)
  ratings <- ratings[complete, , drop = FALSE]

  n <- nrow(ratings)
  r <- ncol(ratings)
  if (n == 0 || r < 2) {
    return(list(kappa = NA_real_, interpretation = "insufficient data"))
  }

  categories <- sort(unique(as.vector(ratings)))
  k <- length(categories)

  # Build n x k count matrix: how many raters assigned each category per subject
  counts <- matrix(0L, nrow = n, ncol = k)
  for (j in seq_len(k)) {
    counts[, j] <- rowSums(ratings == categories[j])
  }

  # P_i = proportion of agreeing rater pairs for subject i
  P_i <- (rowSums(counts^2) - r) / (r * (r - 1))
  P_bar <- mean(P_i)

  # p_j = proportion of all assignments in category j
  p_j <- colSums(counts) / (n * r)
  P_e <- sum(p_j^2)

  if (P_e == 1) {
    # All raters always pick the same category — perfect agreement by default
    kappa_val <- 1.0
  } else {
    kappa_val <- (P_bar - P_e) / (1 - P_e)
  }

  interpretation <- dplyr::case_when(
    kappa_val > 0.80 ~ "Near-perfect agreement",
    kappa_val > 0.60 ~ "Substantial agreement",
    kappa_val > 0.40 ~ "Moderate agreement",
    kappa_val > 0.20 ~ "Fair agreement",
    TRUE ~ "Poor agreement"
  )

  list(kappa = kappa_val, interpretation = interpretation)
}


#' Test IV: Order Invariance
#'
#' Classifies test texts under three class orderings (original, reversed,
#' shuffled) per H&K Table 3. Reports pairwise change rates and Fleiss's
#' kappa across the three orderings treated as raters.
#'
#' Pass criterion: max(change_rate_reversed, change_rate_shuffled) < 5%.
#'
#' @param codebook A validated codebook object
#' @param test_texts Character vector of test passages
#' @param model Character model ID
#' @param seed Integer seed for reproducible shuffled order (default: 42)
#' @return List with pass, change_rate (= max), per-ordering rates,
#'   fleiss_kappa, details tibble
#' @export
test_order_invariance <- function(codebook,
                                  test_texts,
                                  model = "claude-haiku-4-5-20251001",
                                  seed = 42,
                                  max_tokens = 1024,
                                  provider = "anthropic",
                                  base_url = NULL,
                                  api_key = NULL) {
  n_classes <- length(codebook$classes)
  original_order <- seq_len(n_classes)
  reversed_order <- rev(original_order)

  # Generate shuffled order (must differ from original and reversed)
  if (n_classes <= 2) {
    # Binary codebook: only 2 permutations exist; shuffled = reversed
    shuffled_order <- reversed_order
  } else {
    set.seed(seed)
    shuffled_order <- sample(original_order)
    # Guard: reshuffle if identical to original or reversed
    attempts <- 0
    while ((identical(shuffled_order, original_order) ||
            identical(shuffled_order, reversed_order)) && attempts < 100) {
      shuffled_order <- sample(original_order)
      attempts <- attempts + 1
    }
  }

  # Build prompts for each ordering
  prompt_original <- construct_codebook_prompt(codebook, class_order = original_order)
  prompt_reversed <- construct_codebook_prompt(codebook, class_order = reversed_order)
  prompt_shuffled <- construct_codebook_prompt(codebook, class_order = shuffled_order)

  # Classify each text under all three orderings
  results <- purrr::map(seq_along(test_texts), function(i) {
    classify_one <- function(prompt) {
      tryCatch({
        classify_with_codebook(
          text = test_texts[i],
          codebook = codebook,
          model = model,
          temperature = 0,
          system_prompt = prompt,
          max_tokens = max_tokens,
          provider = provider,
          base_url = base_url,
          api_key = api_key
        )$label
      }, error = function(e) NA_character_)
    }

    pred_original <- classify_one(prompt_original)
    pred_reversed <- classify_one(prompt_reversed)
    pred_shuffled <- classify_one(prompt_shuffled)

    tibble::tibble(
      text_id = i,
      label_original = pred_original %||% NA_character_,
      label_reversed = pred_reversed %||% NA_character_,
      label_shuffled = pred_shuffled %||% NA_character_,
      changed_reversed = !identical(pred_original, pred_reversed),
      changed_shuffled = !identical(pred_original, pred_shuffled)
    )
  })

  details <- dplyr::bind_rows(results)

  # Pairwise change rates
  n_changed_reversed <- sum(details$changed_reversed, na.rm = TRUE)
  n_changed_shuffled <- sum(details$changed_shuffled, na.rm = TRUE)
  n_total <- nrow(details)
  change_rate_reversed <- n_changed_reversed / n_total
  change_rate_shuffled <- n_changed_shuffled / n_total
  change_rate_max <- max(change_rate_reversed, change_rate_shuffled)

  # Fleiss's kappa across the three orderings (treated as raters)
  ratings_matrix <- cbind(
    details$label_original,
    details$label_reversed,
    details$label_shuffled
  )
  fk <- fleiss_kappa(ratings_matrix)

  list(
    test = "IV_order_invariance",
    pass = change_rate_max < 0.05,
    change_rate = change_rate_max,
    change_rate_reversed = change_rate_reversed,
    change_rate_shuffled = change_rate_shuffled,
    n_changed_reversed = n_changed_reversed,
    n_changed_shuffled = n_changed_shuffled,
    n_total = n_total,
    threshold = 0.05,
    fleiss_kappa = fk$kappa,
    kappa_interpretation = fk$interpretation,
    shuffled_order = shuffled_order,
    details = details
  )
}


# =============================================================================
# S3 Behavioral Tests (Error Analysis)
# =============================================================================

#' Test V: Exclusion Criteria Consistency (H&K 4-combo design)
#'
#' Tests whether the model correctly follows exclusion criteria using four
#' conditions: (normal/modified document) x (normal/modified codebook).
#'
#' A semantically irrelevant distractor sentence (per H&K: "elephant") is
#' appended to each test document. A corresponding exclusion rule is added
#' to the codebook. The model should only apply the exclusion when BOTH the
#' trigger (distractor) and the rule are present (combo 4).
#'
#' Combo 1: Normal doc + Normal codebook -> true_labels (baseline)
#' Combo 2: Modified doc + Normal codebook -> true_labels (distractor irrelevant)
#' Combo 3: Normal doc + Modified codebook -> true_labels (rule irrelevant)
#' Combo 4: Modified doc + Modified codebook -> all NOT_FISCAL_MEASURE
#'          (positive texts flip because trigger present AND rule active)
#'
#' @param codebook A validated codebook object
#' @param test_texts Character vector of test passages
#' @param true_labels Character vector of true labels
#' @param model Character model ID
#' @param distractor_text Character semantically irrelevant sentence to inject
#' @param exclusion_criterion Character exclusion rule to add to codebook
#' @return List with per-combo accuracy and overall consistency
#' @export
test_exclusion_criteria <- function(
    codebook,
    test_texts,
    true_labels,
    model = "claude-haiku-4-5-20251001",
    max_tokens = 1024,
    provider = "anthropic",
    base_url = NULL,
    api_key = NULL,
    baseline_preds = NULL,
    distractor_text = "And we also support elephants.",
    exclusion_criterion = paste(
      "IMPORTANT NOTE: This category does not apply if the document",
      "discusses an elephant."
    )
) {
  valid_labels <- get_valid_labels(codebook)
  negative_label <- valid_labels[length(valid_labels)]

  # --- Build modified inputs ---

  # Modified documents: append distractor paragraph to each text
  modified_texts <- paste(test_texts, distractor_text, sep = "\n\n")

  # Modified codebook: deep copy + add exclusion rule as negative_clarification
  modified_codebook <- codebook
  modified_codebook$classes <- lapply(codebook$classes, function(cls) cls)
  # Add exclusion rule to the positive class (first class)
  pos_idx <- 1
  modified_codebook$classes[[pos_idx]] <- as.list(
    modified_codebook$classes[[pos_idx]]
  )
  modified_codebook$classes[[pos_idx]]$negative_clarification <- c(
    modified_codebook$classes[[pos_idx]]$negative_clarification,
    exclusion_criterion
  )

  # --- Expected labels per combo ---
  # Combos 1-3: original true_labels (distractor or rule alone shouldn't flip)
  # Combo 4: ALL texts become negative (positive texts flip due to trigger + rule;
  #          negative texts stay negative)
  combo4_expected <- rep(negative_label, length(true_labels))

  # --- Run four combos ---
  combos <- list(
    list(name = "normal_doc_normal_cb",    texts = test_texts,     cb = codebook,          expected = true_labels),
    list(name = "modified_doc_normal_cb",  texts = modified_texts, cb = codebook,          expected = true_labels),
    list(name = "normal_doc_modified_cb",  texts = test_texts,     cb = modified_codebook, expected = true_labels),
    list(name = "modified_doc_modified_cb", texts = modified_texts, cb = modified_codebook, expected = combo4_expected)
  )

  # Classify once per combo, build summary and details together
  all_details <- purrr::map(combos, function(combo) {
    # Reuse cached baseline for combo 1 (normal_doc_normal_cb)
    if (!is.null(baseline_preds) && combo$name == "normal_doc_normal_cb") {
      preds <- baseline_preds
    } else {
      preds <- classify_batch_for_test(combo$cb, combo$texts, model,
                                          max_tokens = max_tokens,
                                          provider = provider, base_url = base_url,
                                          api_key = api_key)
    }
    combo_name <- combo$name
    combo_expected <- combo$expected
    tibble::tibble(
      combo = combo_name,
      text_id = seq_along(preds),
      true_label = true_labels,
      expected = combo_expected,
      predicted = preds,
      correct = preds == combo_expected
    )
  }) |> dplyr::bind_rows()

  combos_tbl <- all_details |>
    dplyr::group_by(combo) |>
    dplyr::summarise(
      n_correct = sum(correct, na.rm = TRUE),
      n_total = dplyr::n(),
      accuracy = n_correct / n_total,
      .groups = "drop"
    )

  overall <- sum(combos_tbl$n_correct) / sum(combos_tbl$n_total)

  # Per-text: fraction where ALL 4 combos are correct (H&K Figure 4)
  all_correct <- all_details |>
    dplyr::group_by(text_id) |>
    dplyr::summarise(all_correct = all(correct), .groups = "drop")
  all_combos_correct_rate <- mean(all_correct$all_correct)

  list(
    test = "V_exclusion_criteria",
    combos = combos_tbl,
    overall_consistency = overall,
    all_combos_correct_rate = all_combos_correct_rate,
    distractor_text = distractor_text,
    exclusion_criterion = exclusion_criterion,
    details = all_details
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
                                model = "claude-haiku-4-5-20251001",
                                max_tokens = 1024,
                                provider = "anthropic",
                                base_url = NULL,
                                api_key = NULL,
                                baseline_preds = NULL) {
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

  # Classify with original labels (reuse cached baseline if available)
  original_preds <- if (!is.null(baseline_preds)) {
    baseline_preds
  } else {
    classify_batch_for_test(codebook, test_texts, model,
                            max_tokens = max_tokens,
                            provider = provider, base_url = base_url,
                            api_key = api_key)
  }

  # Classify with generic labels
  generic_preds <- classify_batch_for_test(generic_codebook, test_texts, model,
                                           max_tokens = max_tokens,
                                           provider = provider, base_url = base_url,
                                           api_key = api_key)

  # Map generic predictions back to original labels for comparison
  reverse_map <- stats::setNames(names(label_map), unlist(label_map))
  generic_preds_mapped <- reverse_map[generic_preds]

  # Compute metrics
  original_acc <- mean(original_preds == true_labels, na.rm = TRUE)
  generic_acc <- mean(generic_preds_mapped == true_labels, na.rm = TRUE)
  change_rate <- mean(original_preds != generic_preds_mapped, na.rm = TRUE)

  # F1 scores for H&K Figure 4
  labels <- vapply(codebook$classes, function(c) c$label, character(1))
  original_metrics <- compute_binary_metrics(
    tibble::tibble(true_label = true_labels, pred_label = original_preds),
    labels
  )
  generic_metrics <- compute_binary_metrics(
    tibble::tibble(true_label = true_labels, pred_label = generic_preds_mapped),
    labels
  )

  list(
    test = "VI_generic_labels",
    original_accuracy = original_acc,
    generic_accuracy = generic_acc,
    accuracy_difference = original_acc - generic_acc,
    change_rate = change_rate,
    original_f1 = original_metrics$f1,
    generic_f1 = generic_metrics$f1,
    f1_difference = original_metrics$f1 - generic_metrics$f1,
    original_metrics = original_metrics,
    generic_metrics = generic_metrics,
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
                                model = "claude-haiku-4-5-20251001",
                                max_tokens = 1024,
                                provider = "anthropic",
                                base_url = NULL,
                                api_key = NULL,
                                baseline_preds = NULL) {
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

  # Classify with original (reuse cached baseline if available)
  original_preds <- if (!is.null(baseline_preds)) {
    baseline_preds
  } else {
    classify_batch_for_test(codebook, test_texts, model,
                            max_tokens = max_tokens,
                            provider = provider, base_url = base_url,
                            api_key = api_key)
  }

  # Classify with swapped definitions
  swapped_preds <- classify_batch_for_test(swapped_codebook, test_texts, model,
                                           max_tokens = max_tokens,
                                           provider = provider, base_url = base_url,
                                           api_key = api_key)

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

  # F1/accuracy of swapped predictions vs ground truth (H&K Figure 4)
  labels <- vapply(codebook$classes, function(c) c$label, character(1))
  swapped_metrics <- compute_binary_metrics(
    tibble::tibble(true_label = true_labels, pred_label = swapped_preds),
    labels
  )

  list(
    test = "VII_swapped_labels",
    follows_definitions_rate = follows_definitions,
    follows_names_rate = follows_names,
    swapped_f1 = swapped_metrics$f1,
    swapped_accuracy = swapped_metrics$accuracy,
    swapped_metrics = swapped_metrics,
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
#' @param return_details If TRUE, return a tibble with full model output
#'   (label, reasoning, raw_response, measure_name, stop_reason) instead of
#'   a character vector of labels
#' @return Character vector of predicted labels (default), or tibble if
#'   return_details = TRUE
#' @keywords internal
classify_batch_for_test <- function(codebook, texts, model,
                                    system_prompt = NULL,
                                    return_details = FALSE,
                                    max_tokens = 1024,
                                    provider = "anthropic",
                                    base_url = NULL,
                                    api_key = NULL) {
  if (is.null(system_prompt)) {
    system_prompt <- construct_codebook_prompt(codebook)
  }

  results <- purrr::map(texts, function(txt) {
    tryCatch({
      classify_with_codebook(
        text = txt,
        codebook = codebook,
        model = model,
        temperature = 0,
        system_prompt = system_prompt,
        max_tokens = max_tokens,
        provider = provider,
        base_url = base_url,
        api_key = api_key
      )
    }, error = function(e) {
      list(label = NA_character_, reasoning = NA_character_,
           raw_response = NA_character_, measure_name = NA_character_,
           stop_reason = NA_character_, confidence = 0.0,
           agreement_rate = NA_real_)
    })
  })

  if (return_details) {
    tibble::tibble(
      text_id = seq_along(texts),
      label = purrr::map_chr(results, ~ .x$label %||% NA_character_),
      reasoning = purrr::map_chr(results, ~ .x$reasoning %||% NA_character_),
      raw_response = purrr::map_chr(results, ~ .x$raw_response %||% NA_character_),
      measure_name = purrr::map_chr(results, ~ .x$measure_name %||% NA_character_),
      discusses_motivation = purrr::map_lgl(results, ~ .x$discusses_motivation %||% NA),
      discusses_timing = purrr::map_lgl(results, ~ .x$discusses_timing %||% NA),
      discusses_magnitude = purrr::map_lgl(results, ~ .x$discusses_magnitude %||% NA),
      stop_reason = purrr::map_chr(results, ~ .x$stop_reason %||% NA_character_)
    )
  } else {
    purrr::map_chr(results, ~ .x$label %||% NA_character_)
  }
}


# Null coalescing operator
if (!exists("%||%", mode = "function", envir = environment())) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
