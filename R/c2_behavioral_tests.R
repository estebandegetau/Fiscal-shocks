# C2 Behavioral Tests for H&K Codebook Validation
# C2-specific test functions for the two-codebook architecture:
#   C2a (evidence extraction) and C2b (motivation classification)
#
# Parallels R/behavioral_tests.R but does NOT modify it.
# Reuses: construct_codebook_prompt(), call_llm_api(), parse_json_response(),
#          get_valid_labels(), fleiss_kappa() from existing code.

# =============================================================================
# Generic Infrastructure
# =============================================================================

#' Call a codebook without assuming output schema
#'
#' Thin wrapper around call_llm_api() + parse_json_response() that does not
#' enforce {label, reasoning} structure. Used by all C2 tests.
#'
#' @param user_message Character string (pre-formatted user message)
#' @param codebook A validated codebook object
#' @param model Character model ID
#' @param system_prompt Optional override; built from codebook if NULL
#' @param max_tokens Integer max output tokens
#' @param temperature Numeric temperature (default 0)
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with parsed JSON fields + $raw_response
#' @keywords internal
call_codebook_generic <- function(user_message,
                                  codebook,
                                  model = "claude-haiku-4-5-20251001",
                                  system_prompt = NULL,
                                  max_tokens = 1024,
                                  temperature = 0,
                                  provider = "anthropic",
                                  base_url = NULL,
                                  api_key = NULL) {
  if (is.null(system_prompt)) {
    system_prompt <- construct_codebook_prompt(codebook)
  }

  raw <- call_llm_api(
    messages = list(list(role = "user", content = user_message)),
    model = model,
    max_tokens = max_tokens,
    temperature = temperature,
    system = system_prompt,
    provider = provider,
    base_url = base_url,
    api_key = api_key
  )

  raw_text <- raw$content[[1]]$text
  parsed <- parse_json_response(raw_text)
  parsed$raw_response <- raw_text
  parsed$stop_reason <- raw$stop_reason %||% NA_character_
  parsed
}


#' Format user message for C2a (evidence extraction)
#'
#' @param text Character chunk text
#' @param act_name Character act name
#' @param year Integer or character year
#' @return Character string formatted for C2a input
#' @keywords internal
format_c2a_input <- function(text, act_name, year) {
  paste0(
    "Act: ", act_name, "\n",
    "Year: ", year, "\n\n",
    "Chunk text:\n", text
  )
}


#' Format user message for C2b (motivation, sign, and timing classification)
#'
#' @param act_name Character act name
#' @param year Integer or character year
#' @param evidence List of motivation evidence objects (each with quote, signal)
#' @param enacted_signals List of enacted-status signal objects (each with quote, signal)
#' @param timing_signals List of timing signal objects (each with quote, signal).
#'   Optional for backward compatibility with v0.7.0 cached evidence; defaults
#'   to an empty list. C2b v0.8.0 expects this array even when empty.
#' @return Character string formatted for C2b input
#' @keywords internal
format_c2b_input <- function(act_name, year, evidence, enacted_signals = list(),
                             timing_signals = list()) {
  evidence_json <- jsonlite::toJSON(evidence, auto_unbox = TRUE, pretty = TRUE)
  signals_json <- jsonlite::toJSON(enacted_signals, auto_unbox = TRUE, pretty = TRUE)
  timing_json <- jsonlite::toJSON(timing_signals, auto_unbox = TRUE, pretty = TRUE)

  paste0(
    "Act: ", act_name, "\n",
    "Year: ", year, "\n\n",
    "Evidence records (motivation):\n", evidence_json, "\n\n",
    "Enacted-status signals:\n", signals_json, "\n\n",
    "Timing signals:\n", timing_json, "\n\n",
    "Classify this act's motivation, sign, and implementation quarter(s) ",
    "based on the evidence above."
  )
}


#' Validate C2a output schema
#'
#' @param parsed List from parse_json_response()
#' @param valid_categories Character vector of valid category labels
#' @return List with $valid (logical) and $reason (character, NA if valid)
#' @keywords internal
validate_c2a_output <- function(parsed) {
  # Check for parse errors
  if (!is.null(parsed$error)) {
    return(list(valid = FALSE, reason = paste("JSON parse error:", parsed$error)))
  }

  # evidence must exist and be a list
  if (is.null(parsed$evidence) || !is.list(parsed$evidence)) {
    return(list(valid = FALSE, reason = "Missing or non-list 'evidence' field"))
  }

  # Validate each evidence item
  for (i in seq_along(parsed$evidence)) {
    item <- parsed$evidence[[i]]
    if (is.null(item$quote) || !is.character(item$quote)) {
      return(list(valid = FALSE,
                  reason = sprintf("evidence[%d]: missing or non-character 'quote'", i)))
    }
    if (is.null(item$signal) || !is.character(item$signal)) {
      return(list(valid = FALSE,
                  reason = sprintf("evidence[%d]: missing or non-character 'signal'", i)))
    }
  }

  # enacted_signals must exist and be a list
  if (is.null(parsed$enacted_signals) || !is.list(parsed$enacted_signals)) {
    return(list(valid = FALSE, reason = "Missing or non-list 'enacted_signals' field"))
  }

  # Validate each enacted_signal item (if any)
  for (i in seq_along(parsed$enacted_signals)) {
    item <- parsed$enacted_signals[[i]]
    if (is.null(item$quote) || !is.character(item$quote)) {
      return(list(valid = FALSE,
                  reason = sprintf("enacted_signals[%d]: missing or non-character 'quote'", i)))
    }
    if (is.null(item$signal) || !is.character(item$signal)) {
      return(list(valid = FALSE,
                  reason = sprintf("enacted_signals[%d]: missing or non-character 'signal'", i)))
    }
  }

  # timing_signals must exist and be a list (added in C2a v0.5.0)
  if (is.null(parsed$timing_signals) || !is.list(parsed$timing_signals)) {
    return(list(valid = FALSE, reason = "Missing or non-list 'timing_signals' field"))
  }

  # Validate each timing_signal item (if any)
  for (i in seq_along(parsed$timing_signals)) {
    item <- parsed$timing_signals[[i]]
    if (is.null(item$quote) || !is.character(item$quote)) {
      return(list(valid = FALSE,
                  reason = sprintf("timing_signals[%d]: missing or non-character 'quote'", i)))
    }
    if (is.null(item$signal) || !is.character(item$signal)) {
      return(list(valid = FALSE,
                  reason = sprintf("timing_signals[%d]: missing or non-character 'signal'", i)))
    }
  }

  list(valid = TRUE, reason = NA_character_)
}


#' Validate C2b output schema (v0.8.0)
#'
#' Validates the minimal Das-et-al.-adapted schema with timing extraction:
#' {enacted: bool, exogenous: "TRUE"|"FALSE"|"UNCLEAR",
#'  sign: "+"|"-"|"0"|"UNCLEAR", enacted_quarter: ["YYYY-QN", ...],
#'  confidence: str, reasoning: str}.
#'
#' Quarter strings must match the regex `^[0-9]{4}-Q[1-4]$`. The
#' `enacted_quarter` array is allowed to be empty when timing evidence is
#' absent or inconsistent, but the field itself must be present and a list.
#'
#' @param parsed List from parse_json_response()
#' @param valid_categories Unused (kept for backward-compatible signature).
#' @return List with $valid (logical) and $reason (character, NA if valid)
#' @keywords internal
validate_c2b_output <- function(parsed, valid_categories = NULL) {
  if (!is.null(parsed$error)) {
    return(list(valid = FALSE, reason = paste("JSON parse error:", parsed$error)))
  }

  # enacted must be logical
  if (is.null(parsed$enacted) || !is.logical(parsed$enacted)) {
    return(list(valid = FALSE, reason = "Missing or non-logical 'enacted' field"))
  }

  # exogenous must be character with valid value
  valid_exo <- c("TRUE", "FALSE", "UNCLEAR")
  if (is.null(parsed$exogenous) || !is.character(parsed$exogenous) ||
      !parsed$exogenous %in% valid_exo) {
    return(list(valid = FALSE,
                reason = sprintf("Invalid 'exogenous' field: '%s' (must be one of %s)",
                                 parsed$exogenous %||% "NULL",
                                 paste(valid_exo, collapse = "/"))))
  }

  # sign must be character with valid value
  valid_sign <- c("+", "-", "0", "UNCLEAR")
  if (is.null(parsed$sign) || !is.character(parsed$sign) ||
      !parsed$sign %in% valid_sign) {
    return(list(valid = FALSE,
                reason = sprintf("Invalid 'sign' field: '%s' (must be one of %s)",
                                 parsed$sign %||% "NULL",
                                 paste(valid_sign, collapse = "/"))))
  }

  # enacted_quarter must be present and a list/character vector;
  # parse_json_response may yield list() or character() depending on jsonlite simplify.
  # Empty array is valid (no timing evidence).
  if (is.null(parsed$enacted_quarter)) {
    return(list(valid = FALSE, reason = "Missing 'enacted_quarter' field"))
  }
  q_vec <- parsed$enacted_quarter
  if (is.list(q_vec)) q_vec <- unlist(q_vec, use.names = FALSE)
  if (!is.character(q_vec) && length(q_vec) > 0) {
    return(list(valid = FALSE,
                reason = "'enacted_quarter' must be an array of strings"))
  }
  if (length(q_vec) > 0) {
    bad_quarter <- !grepl("^[0-9]{4}-Q[1-4]$", q_vec)
    if (any(bad_quarter)) {
      return(list(valid = FALSE,
                  reason = sprintf(
                    "Invalid 'enacted_quarter' format(s): %s (expected YYYY-QN)",
                    paste(q_vec[bad_quarter], collapse = ", ")
                  )))
    }
  }

  # confidence must be character
  if (is.null(parsed$confidence) || !is.character(parsed$confidence)) {
    return(list(valid = FALSE, reason = "Missing or non-character 'confidence' field"))
  }

  # reasoning must be character
  if (is.null(parsed$reasoning) || !is.character(parsed$reasoning)) {
    return(list(valid = FALSE, reason = "Missing or non-character 'reasoning' field"))
  }

  list(valid = TRUE, reason = NA_character_)
}


# =============================================================================
# C2a Tests (Evidence Extraction)
# =============================================================================

#' Test I: C2a Legal Outputs
#'
#' Sends chunk texts to C2a and validates that all responses have valid
#' JSON with correct schema (evidence[] and enacted_signals[] arrays).
#'
#' @param codebook A validated C2a codebook object
#' @param test_chunks Tibble with text, act_name, year columns
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with pass, n_valid, n_total, rate, threshold, details
#' @export
test_c2a_legal_outputs <- function(codebook,
                                   test_chunks,
                                   model = "claude-haiku-4-5-20251001",
                                   max_tokens = 1024,
                                   provider = "anthropic",
                                   base_url = NULL,
                                   api_key = NULL) {
  system_prompt <- construct_codebook_prompt(codebook)
  n <- nrow(test_chunks)

  results <- purrr::map(seq_len(n), function(i) {
    user_msg <- format_c2a_input(
      test_chunks$text[i], test_chunks$act_name[i], test_chunks$year[i]
    )

    parsed <- tryCatch({
      call_codebook_generic(
        user_message = user_msg,
        codebook = codebook,
        model = model,
        system_prompt = system_prompt,
        max_tokens = max_tokens,
        temperature = 0,
        provider = provider,
        base_url = base_url,
        api_key = api_key
      )
    }, error = function(e) {
      list(error = e$message, raw_response = NA_character_)
    })

    validation <- validate_c2a_output(parsed)

    tibble::tibble(
      text_id = i,
      act_name = test_chunks$act_name[i],
      valid = validation$valid,
      reason = validation$reason,
      n_evidence = length(parsed$evidence %||% list()),
      n_enacted_signals = length(parsed$enacted_signals %||% list()),
      raw_response = parsed$raw_response %||% NA_character_
    )
  })

  details <- dplyr::bind_rows(results)
  n_valid <- sum(details$valid, na.rm = TRUE)

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


#' Test II: C2a Instruction Recovery
#'
#' Tests whether C2a can follow extraction instructions by giving it
#' synthetic passages with obvious quotes and motivation signals.
#' Each passage is constructed from a category's definition and
#' clarifications, wrapped in a fiscal-policy frame.
#'
#' @param codebook A validated C2a codebook object
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with pass, n_correct, n_total, rate, threshold, details
#' @export
test_c2a_instruction_recovery <- function(codebook,
                                          model = "claude-haiku-4-5-20251001",
                                          max_tokens = 1024,
                                          provider = "anthropic",
                                          base_url = NULL,
                                          api_key = NULL) {
  valid_categories <- get_valid_labels(codebook)
  system_prompt <- construct_codebook_prompt(codebook)

  # Synthetic passages: one per category, each with an obvious extractable quote
  # The quotes are designed to be unambiguous for the target category
  synthetic_passages <- list(
    SPENDING_DRIVEN = list(
      act_name = "Test Spending Revenue Act",
      year = 2000,
      text = paste(
        "The government introduced the Test Spending Revenue Act of 2000",
        "to finance the new national infrastructure program.",
        "As the budget report stated, 'this tax increase will pay for the",
        "$50 billion highway construction initiative enacted this year.'",
        "The revenue measure and the spending program were enacted together",
        "as a single legislative package."
      )
    ),
    COUNTERCYCLICAL = list(
      act_name = "Test Stimulus Relief Act",
      year = 2001,
      text = paste(
        "In response to the economic downturn, Congress passed the Test",
        "Stimulus Relief Act of 2001. The President stated that 'with",
        "unemployment rising and GDP falling, this temporary tax cut is",
        "needed to restore the economy to its normal growth path.' The",
        "measure was designed as a short-term response to the recession",
        "and was expected to expire once economic conditions normalized."
      )
    ),
    DEFICIT_DRIVEN = list(
      act_name = "Test Fiscal Responsibility Act",
      year = 1993,
      text = paste(
        "The Test Fiscal Responsibility Act of 1993 was enacted to address",
        "the large budget deficit inherited from previous administrations.",
        "The Secretary of the Treasury testified that 'the deficit, which",
        "has accumulated over many years of past policy decisions, threatens",
        "long-term fiscal stability and must be reduced through higher",
        "revenues.' The act was signed into law on August 10, 1993."
      )
    ),
    LONG_RUN = list(
      act_name = "Test Economic Reform Act",
      year = 1986,
      text = paste(
        "The Test Economic Reform Act of 1986 aimed to improve economic",
        "efficiency and simplify the tax code. Policymakers argued that",
        "'by broadening the tax base and lowering marginal rates, we can",
        "raise long-run economic growth above its current trend and improve",
        "incentives for investment and productivity.' The reform was",
        "designed as a permanent structural change to the tax system."
      )
    )
  )

  results <- purrr::map(names(synthetic_passages), function(expected_cat) {
    passage <- synthetic_passages[[expected_cat]]

    user_msg <- format_c2a_input(passage$text, passage$act_name, passage$year)

    parsed <- tryCatch({
      call_codebook_generic(
        user_message = user_msg,
        codebook = codebook,
        model = model,
        system_prompt = system_prompt,
        max_tokens = max_tokens,
        temperature = 0,
        provider = provider,
        base_url = base_url,
        api_key = api_key
      )
    }, error = function(e) {
      list(error = e$message, raw_response = NA_character_)
    })

    # Validate schema first
    validation <- validate_c2a_output(parsed)

    # Check instruction recovery: model extracts evidence from clear synthetic passages
    has_evidence <- length(parsed$evidence %||% list()) > 0

    tibble::tibble(
      expected_category = expected_cat,
      act_name = passage$act_name,
      valid_schema = validation$valid,
      has_evidence = has_evidence,
      correct = validation$valid && has_evidence
    )
  })

  details <- dplyr::bind_rows(results)
  n_correct <- sum(details$correct, na.rm = TRUE)

  list(
    test = "II_instruction_recovery",
    pass = n_correct == nrow(details),
    n_correct = n_correct,
    n_total = nrow(details),
    rate = n_correct / nrow(details),
    threshold = 1.0,
    details = details
  )
}


#' Test IV: C2a Order Invariance
#'
#' Reorders class definitions in the C2a codebook prompt and checks
#' whether extracted evidence changes. Uses sorted evidence fingerprints
#' (truncated quote + signal) per chunk as the comparison unit.
#'
#' @param codebook A validated C2a codebook object
#' @param test_chunks Tibble with text, act_name, year columns
#' @param model Character model ID
#' @param seed Integer seed for shuffled ordering
#' @param max_tokens Integer max output tokens
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with pass, change rates, fleiss_kappa, details
#' @export
test_c2a_order_invariance <- function(codebook,
                                      test_chunks,
                                      model = "claude-haiku-4-5-20251001",
                                      seed = 42,
                                      max_tokens = 1024,
                                      provider = "anthropic",
                                      base_url = NULL,
                                      api_key = NULL) {
  # Skip for extraction codebooks without classes (nothing to reorder)
  if (is.null(codebook$classes) || length(codebook$classes) == 0) {
    return(list(
      test = "IV_order_invariance",
      pass = TRUE,
      change_rate = NA_real_,
      change_rate_reversed = NA_real_,
      change_rate_shuffled = NA_real_,
      n_changed_reversed = NA_integer_,
      n_changed_shuffled = NA_integer_,
      n_total = nrow(test_chunks),
      threshold = 0.05,
      fleiss_kappa = NA_real_,
      kappa_interpretation = NA_character_,
      details = tibble::tibble(),
      skipped = TRUE
    ))
  }

  n_classes <- length(codebook$classes)
  original_order <- seq_len(n_classes)
  reversed_order <- rev(original_order)

  # Generate shuffled order (must differ from original and reversed)
  set.seed(seed)
  shuffled_order <- sample(original_order)
  attempts <- 0
  while ((identical(shuffled_order, original_order) ||
          identical(shuffled_order, reversed_order)) && attempts < 100) {
    shuffled_order <- sample(original_order)
    attempts <- attempts + 1
  }

  # Build prompts for each ordering
  prompt_original <- construct_codebook_prompt(codebook, class_order = original_order)
  prompt_reversed <- construct_codebook_prompt(codebook, class_order = reversed_order)
  prompt_shuffled <- construct_codebook_prompt(codebook, class_order = shuffled_order)

  # Helper: extract sorted evidence fingerprint string from C2a response
  extract_evidence_fingerprint <- function(parsed) {
    evidence <- parsed$evidence %||% list()
    if (length(evidence) == 0) return("EMPTY")
    fingerprints <- vapply(evidence, function(e) {
      q <- substr(e$quote %||% "", 1, 80)
      s <- e$signal %||% ""
      paste(q, s, sep = "|")
    }, character(1))
    paste(sort(fingerprints), collapse = "||")
  }

  n <- nrow(test_chunks)

  results <- purrr::map(seq_len(n), function(i) {
    user_msg <- format_c2a_input(
      test_chunks$text[i], test_chunks$act_name[i], test_chunks$year[i]
    )

    classify_one <- function(prompt) {
      tryCatch({
        parsed <- call_codebook_generic(
          user_message = user_msg,
          codebook = codebook,
          model = model,
          system_prompt = prompt,
          max_tokens = max_tokens,
          temperature = 0,
          provider = provider,
          base_url = base_url,
          api_key = api_key
        )
        extract_evidence_fingerprint(parsed)
      }, error = function(e) NA_character_)
    }

    label_original <- classify_one(prompt_original)
    label_reversed <- classify_one(prompt_reversed)
    label_shuffled <- classify_one(prompt_shuffled)

    tibble::tibble(
      text_id = i,
      label_original = label_original,
      label_reversed = label_reversed,
      label_shuffled = label_shuffled,
      changed_reversed = !identical(label_original, label_reversed),
      changed_shuffled = !identical(label_original, label_shuffled)
    )
  })

  details <- dplyr::bind_rows(results)

  n_changed_reversed <- sum(details$changed_reversed, na.rm = TRUE)
  n_changed_shuffled <- sum(details$changed_shuffled, na.rm = TRUE)
  n_total <- nrow(details)
  change_rate_reversed <- n_changed_reversed / n_total
  change_rate_shuffled <- n_changed_shuffled / n_total
  change_rate_max <- max(change_rate_reversed, change_rate_shuffled)

  # Fleiss's kappa across the three orderings
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
# C2b Tests (Motivation Classification)
# =============================================================================

#' Test I: C2b Legal Outputs
#'
#' Sends evidence arrays to C2b and validates that all responses have
#' valid JSON with correct schema (enacted, motivations[], exogenous,
#' confidence, reasoning).
#'
#' @param codebook A validated C2b codebook object
#' @param test_evidence_sets List of evidence set lists, each with
#'   act_name, year, evidence, enacted_signals
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with pass, n_valid, n_total, rate, threshold, details
#' @export
test_c2b_legal_outputs <- function(codebook,
                                   test_evidence_sets,
                                   model = "claude-haiku-4-5-20251001",
                                   max_tokens = 1024,
                                   provider = "anthropic",
                                   base_url = NULL,
                                   api_key = NULL) {
  valid_categories <- get_valid_labels(codebook)
  system_prompt <- construct_codebook_prompt(codebook)
  n <- length(test_evidence_sets)

  results <- purrr::map(seq_len(n), function(i) {
    es <- test_evidence_sets[[i]]
    user_msg <- format_c2b_input(
      es$act_name, es$year, es$evidence, es$enacted_signals,
      timing_signals = es$timing_signals %||% list()
    )

    parsed <- tryCatch({
      call_codebook_generic(
        user_message = user_msg,
        codebook = codebook,
        model = model,
        system_prompt = system_prompt,
        max_tokens = max_tokens,
        temperature = 0,
        provider = provider,
        base_url = base_url,
        api_key = api_key
      )
    }, error = function(e) {
      list(error = e$message, raw_response = NA_character_)
    })

    validation <- validate_c2b_output(parsed, valid_categories)

    tibble::tibble(
      text_id = i,
      act_name = es$act_name,
      valid = validation$valid,
      reason = validation$reason,
      pred_exogenous = parsed$exogenous %||% NA_character_,
      pred_sign = parsed$sign %||% NA_character_,
      confidence = parsed$confidence %||% NA_character_,
      raw_response = parsed$raw_response %||% NA_character_
    )
  })

  details <- dplyr::bind_rows(results)
  n_valid <- sum(details$valid, na.rm = TRUE)

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


#' Set equality on quarter character vectors
#'
#' Used by C2b tests that compare predicted vs. expected `enacted_quarter[]`.
#' Empty vectors match only when both sides are empty.
#'
#' @param a Character vector or NULL
#' @param b Character vector or NULL
#' @return Logical scalar
#' @keywords internal
quarters_equal <- function(a, b) {
  a <- if (is.null(a)) character(0) else as.character(a)
  b <- if (is.null(b)) character(0) else as.character(b)
  identical(sort(unique(a)), sort(unique(b)))
}


#' Format a quarter vector for human-readable display in result tibbles
#'
#' @param x Character vector of quarter strings
#' @return Character scalar (e.g., "[1986-Q1,1986-Q2]" or "[]")
#' @keywords internal
fmt_quarters <- function(x) {
  if (length(x) == 0) "[]" else paste0("[", paste(x, collapse = ","), "]")
}


#' Test II: C2b Schema Recovery (v0.8.0)
#'
#' For each synthetic evidence set with known expected `exogenous`, `sign`,
#' and `enacted_quarter[]` values, verifies that C2b returns the expected
#' outputs. Replaces the prior 4-class definition-recovery test under the
#' v0.7.0+ minimal codebook (no class definitions to recover).
#'
#' Quarter equality is checked as a set (sorted unique), since C2b's
#' `enacted_quarter[]` is naturally a set of unique implementation quarters.
#' Empty arrays match only when both sides are empty.
#'
#' @param codebook A validated C2b codebook object
#' @param test_evidence_sets List of evidence set lists from
#'   generate_c2b_test_evidence(); each must include `expected_exogenous`,
#'   `expected_sign`, and `expected_quarters` fields. `timing_signals` is
#'   optional (defaults to empty for backward compatibility).
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with pass, n_correct, n_total, rate, threshold, details
#' @export
test_c2b_schema_recovery <- function(codebook,
                                     test_evidence_sets,
                                     model = "claude-haiku-4-5-20251001",
                                     max_tokens = 1024,
                                     provider = "anthropic",
                                     base_url = NULL,
                                     api_key = NULL) {
  system_prompt <- construct_codebook_prompt(codebook)

  results <- purrr::map(seq_along(test_evidence_sets), function(i) {
    es <- test_evidence_sets[[i]]
    if (is.null(es$expected_exogenous) || is.null(es$expected_sign)) {
      stop(sprintf(
        "test_evidence_sets[[%d]] missing expected_exogenous/expected_sign fields",
        i
      ))
    }
    if (is.null(es$expected_quarters)) {
      stop(sprintf(
        "test_evidence_sets[[%d]] missing expected_quarters field (v0.8.0)",
        i
      ))
    }

    user_msg <- format_c2b_input(
      es$act_name, es$year, es$evidence, es$enacted_signals,
      timing_signals = es$timing_signals %||% list()
    )

    parsed <- tryCatch({
      call_codebook_generic(
        user_message = user_msg,
        codebook = codebook,
        model = model,
        system_prompt = system_prompt,
        max_tokens = max_tokens,
        temperature = 0,
        provider = provider,
        base_url = base_url,
        api_key = api_key
      )
    }, error = function(e) {
      list(error = e$message, raw_response = NA_character_)
    })

    validation <- validate_c2b_output(parsed)

    pred_exo <- if (validation$valid) parsed$exogenous else NA_character_
    pred_sign <- if (validation$valid) parsed$sign else NA_character_

    pred_quarters <- character(0)
    if (validation$valid && !is.null(parsed$enacted_quarter)) {
      pq <- parsed$enacted_quarter
      if (is.list(pq)) pq <- unlist(pq, use.names = FALSE)
      if (length(pq) > 0) pred_quarters <- as.character(pq)
    }

    quarter_correct <- quarters_equal(pred_quarters, es$expected_quarters)

    tibble::tibble(
      act_name = es$act_name,
      expected_exogenous = es$expected_exogenous,
      expected_sign = es$expected_sign,
      expected_quarters = fmt_quarters(es$expected_quarters),
      pred_exogenous = pred_exo,
      pred_sign = pred_sign,
      pred_quarters = fmt_quarters(pred_quarters),
      exo_correct = identical(pred_exo, es$expected_exogenous),
      sign_correct = identical(pred_sign, es$expected_sign),
      quarter_correct = quarter_correct,
      correct = identical(pred_exo, es$expected_exogenous) &&
        identical(pred_sign, es$expected_sign) &&
        quarter_correct
    )
  })

  details <- dplyr::bind_rows(results)
  n_correct <- sum(details$correct, na.rm = TRUE)

  list(
    test = "II_schema_recovery",
    pass = n_correct == nrow(details),
    n_correct = n_correct,
    n_total = nrow(details),
    rate = n_correct / nrow(details),
    threshold = 1.0,
    details = details
  )
}


#' Test III: C2b Example Recovery (v0.8.0)
#'
#' Memorization-style test for codebooks with worked examples. For each
#' example in `codebook$examples`, presents the example's `input` block as a
#' recall-framed user message and checks whether the model returns the
#' `output` block listed alongside it. Compares `{enacted, exogenous, sign,
#' enacted_quarter}`; free-form fields (`confidence`, `reasoning`) are not
#' compared. Pass criterion: 100% of examples correct on all four dimensions.
#'
#' Mirrors the recall framing of `test_example_recovery()` for class-based
#' codebooks (C1). C2b's flat top-level `examples` array and multi-field
#' output schema require a separate implementation.
#'
#' @param codebook A validated C2b codebook object with non-empty `examples`
#' @param model Character model ID
#' @param max_tokens Integer max output tokens
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with pass, n_correct, n_total, rate, threshold, details
#' @export
test_c2b_example_recovery <- function(codebook,
                                      model = "claude-haiku-4-5-20251001",
                                      max_tokens = 1024,
                                      provider = "anthropic",
                                      base_url = NULL,
                                      api_key = NULL) {
  system_prompt <- construct_codebook_prompt(codebook)

  recall_prefix <- paste0(
    "The following input appears verbatim as an example in the codebook. ",
    "Recall the output the codebook associates with it.\n\n"
  )

  results <- purrr::map(seq_along(codebook$examples), function(i) {
    ex <- codebook$examples[[i]]

    if (is.null(ex$input) || is.null(ex$output)) {
      stop(sprintf(
        "codebook$examples[[%d]] missing input/output blocks",
        i
      ))
    }

    user_msg <- paste0(
      recall_prefix,
      format_c2b_input(
        ex$input$act_name, ex$input$year, ex$input$evidence,
        ex$input$enacted_signals %||% list(),
        timing_signals = ex$input$timing_signals %||% list()
      )
    )

    parsed <- tryCatch({
      call_codebook_generic(
        user_message = user_msg,
        codebook = codebook,
        model = model,
        system_prompt = system_prompt,
        max_tokens = max_tokens,
        temperature = 0,
        provider = provider,
        base_url = base_url,
        api_key = api_key
      )
    }, error = function(e) {
      list(error = e$message, raw_response = NA_character_)
    })

    validation <- validate_c2b_output(parsed)

    pred_enacted <- if (validation$valid) parsed$enacted else NA
    pred_exo <- if (validation$valid) parsed$exogenous else NA_character_
    pred_sign <- if (validation$valid) parsed$sign else NA_character_

    pred_quarters <- character(0)
    if (validation$valid && !is.null(parsed$enacted_quarter)) {
      pq <- parsed$enacted_quarter
      if (is.list(pq)) pq <- unlist(pq, use.names = FALSE)
      if (length(pq) > 0) pred_quarters <- as.character(pq)
    }

    expected_quarters <- ex$output$enacted_quarter %||% character(0)
    if (is.list(expected_quarters)) {
      expected_quarters <- unlist(expected_quarters, use.names = FALSE)
    }
    expected_quarters <- as.character(expected_quarters)

    enacted_correct <- identical(as.logical(pred_enacted),
                                 as.logical(ex$output$enacted))
    exo_correct <- identical(pred_exo, ex$output$exogenous)
    sign_correct <- identical(pred_sign, ex$output$sign)
    quarter_correct <- quarters_equal(pred_quarters, expected_quarters)

    tibble::tibble(
      example_idx = i,
      act_name = ex$input$act_name %||% NA_character_,
      expected_enacted = ex$output$enacted,
      expected_exogenous = ex$output$exogenous,
      expected_sign = ex$output$sign,
      expected_quarters = fmt_quarters(expected_quarters),
      pred_enacted = pred_enacted,
      pred_exogenous = pred_exo,
      pred_sign = pred_sign,
      pred_quarters = fmt_quarters(pred_quarters),
      enacted_correct = enacted_correct,
      exo_correct = exo_correct,
      sign_correct = sign_correct,
      quarter_correct = quarter_correct,
      correct = enacted_correct && exo_correct && sign_correct && quarter_correct
    )
  })

  details <- dplyr::bind_rows(results)
  n_correct <- sum(details$correct)
  n_total <- nrow(details)

  list(
    test = "III_example_recovery",
    pass = n_correct == n_total,
    n_correct = n_correct,
    n_total = n_total,
    rate = if (n_total > 0) n_correct / n_total else 1.0,
    threshold = 1.0,
    details = details,
    skipped = FALSE
  )
}


#' Test IV: C2b Order Invariance
#'
#' Reorders class definitions in the C2b codebook prompt and checks
#' whether motivation category and exogenous flag assignments change.
#'
#' @param codebook A validated C2b codebook object
#' @param test_evidence_sets List of evidence set lists
#' @param model Character model ID
#' @param seed Integer seed for shuffled ordering
#' @param max_tokens Integer max output tokens
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with pass, change rates, fleiss_kappa, details
#' @export
test_c2b_order_invariance <- function(codebook,
                                      test_evidence_sets,
                                      model = "claude-haiku-4-5-20251001",
                                      seed = 42,
                                      max_tokens = 1024,
                                      provider = "anthropic",
                                      base_url = NULL,
                                      api_key = NULL) {
  # Skip when codebook has no classes (v0.7.0+ minimal classification codebooks).
  # Order invariance over class definitions is degenerate; legal-output stability
  # is covered by Test I.
  if (is.null(codebook$classes) || length(codebook$classes) == 0) {
    return(list(
      test = "IV_order_invariance",
      pass = TRUE,
      change_rate = NA_real_,
      change_rate_reversed = NA_real_,
      change_rate_shuffled = NA_real_,
      change_rate_categories = NA_real_,
      change_rate_exogenous = NA_real_,
      n_changed_reversed = NA_integer_,
      n_changed_shuffled = NA_integer_,
      n_total = length(test_evidence_sets),
      threshold = 0.05,
      fleiss_kappa = NA_real_,
      kappa_interpretation = NA_character_,
      details = tibble::tibble(),
      skipped = TRUE
    ))
  }

  n_classes <- length(codebook$classes)
  original_order <- seq_len(n_classes)
  reversed_order <- rev(original_order)

  set.seed(seed)
  shuffled_order <- sample(original_order)
  attempts <- 0
  while ((identical(shuffled_order, original_order) ||
          identical(shuffled_order, reversed_order)) && attempts < 100) {
    shuffled_order <- sample(original_order)
    attempts <- attempts + 1
  }

  prompt_original <- construct_codebook_prompt(codebook, class_order = original_order)
  prompt_reversed <- construct_codebook_prompt(codebook, class_order = reversed_order)
  prompt_shuffled <- construct_codebook_prompt(codebook, class_order = shuffled_order)

  # Helper: extract combined label from C2b response (category multiset + exogenous)
  extract_c2b_label <- function(parsed) {
    cats <- vapply(
      parsed$motivations %||% list(),
      function(m) m$category %||% NA_character_,
      character(1)
    )
    cats <- sort(cats[!is.na(cats)])
    cat_str <- if (length(cats) == 0) "NONE" else paste(cats, collapse = "+")
    exo_str <- as.character(parsed$exogenous %||% NA)
    paste(cat_str, exo_str, sep = "|")
  }

  # Helper: extract just the category multiset (for separate reporting)
  extract_category_str <- function(parsed) {
    cats <- vapply(
      parsed$motivations %||% list(),
      function(m) m$category %||% NA_character_,
      character(1)
    )
    cats <- sort(cats[!is.na(cats)])
    if (length(cats) == 0) "NONE" else paste(cats, collapse = "+")
  }

  n <- length(test_evidence_sets)

  results <- purrr::map(seq_len(n), function(i) {
    es <- test_evidence_sets[[i]]
    user_msg <- format_c2b_input(
      es$act_name, es$year, es$evidence, es$enacted_signals,
      timing_signals = es$timing_signals %||% list()
    )

    classify_one <- function(prompt) {
      tryCatch({
        parsed <- call_codebook_generic(
          user_message = user_msg,
          codebook = codebook,
          model = model,
          system_prompt = prompt,
          max_tokens = max_tokens,
          temperature = 0,
          provider = provider,
          base_url = base_url,
          api_key = api_key
        )
        list(
          combined = extract_c2b_label(parsed),
          category = extract_category_str(parsed),
          exogenous = as.character(parsed$exogenous %||% NA)
        )
      }, error = function(e) {
        list(combined = NA_character_, category = NA_character_,
             exogenous = NA_character_)
      })
    }

    orig <- classify_one(prompt_original)
    rev_r <- classify_one(prompt_reversed)
    shuf <- classify_one(prompt_shuffled)

    tibble::tibble(
      text_id = i,
      label_original = orig$combined,
      label_reversed = rev_r$combined,
      label_shuffled = shuf$combined,
      cat_original = orig$category,
      cat_reversed = rev_r$category,
      cat_shuffled = shuf$category,
      exo_original = orig$exogenous,
      exo_reversed = rev_r$exogenous,
      exo_shuffled = shuf$exogenous,
      changed_reversed = !identical(orig$combined, rev_r$combined),
      changed_shuffled = !identical(orig$combined, shuf$combined),
      cat_changed_reversed = !identical(orig$category, rev_r$category),
      cat_changed_shuffled = !identical(orig$category, shuf$category),
      exo_changed_reversed = !identical(orig$exogenous, rev_r$exogenous),
      exo_changed_shuffled = !identical(orig$exogenous, shuf$exogenous)
    )
  })

  details <- dplyr::bind_rows(results)
  n_total <- nrow(details)

  # Overall change rates (category OR exogenous changed)
  change_rate_reversed <- sum(details$changed_reversed, na.rm = TRUE) / n_total
  change_rate_shuffled <- sum(details$changed_shuffled, na.rm = TRUE) / n_total
  change_rate_max <- max(change_rate_reversed, change_rate_shuffled)

  # Category-only change rates
  cat_change_reversed <- sum(details$cat_changed_reversed, na.rm = TRUE) / n_total
  cat_change_shuffled <- sum(details$cat_changed_shuffled, na.rm = TRUE) / n_total

  # Exogenous-only change rates
  exo_change_reversed <- sum(details$exo_changed_reversed, na.rm = TRUE) / n_total
  exo_change_shuffled <- sum(details$exo_changed_shuffled, na.rm = TRUE) / n_total

  # Fleiss's kappa on combined label
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
    change_rate_categories = max(cat_change_reversed, cat_change_shuffled),
    change_rate_exogenous = max(exo_change_reversed, exo_change_shuffled),
    n_changed_reversed = sum(details$changed_reversed, na.rm = TRUE),
    n_changed_shuffled = sum(details$changed_shuffled, na.rm = TRUE),
    n_total = n_total,
    threshold = 0.05,
    fleiss_kappa = fk$kappa,
    kappa_interpretation = fk$interpretation,
    shuffled_order = shuffled_order,
    details = details
  )
}


# Null coalescing operator (local copy to avoid dependency on behavioral_tests.R)
if (!exists("%||%", mode = "function", envir = environment())) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
