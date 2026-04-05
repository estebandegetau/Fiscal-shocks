# Codebook Stage 1: S1 Behavioral Test Runner
# Generic orchestrator for H&K Tests I-IV
#
# Auto-generates test texts from chunk tier data (Tier 1+2 positives,
# negative chunks), then runs all four behavioral tests.

#' Run S1 behavioral tests for a codebook (chunk-based)
#'
#' Orchestrates Tests I-IV from H&K Table 3. Uses chunk-level test data:
#' positive tests from Tier 1+2 chunks, negative tests from clean negative chunks.
#'
#' @param codebook A validated codebook object from load_validate_codebook()
#' @param aligned_data Tibble with aligned labels (must have passages_text)
#' @param c1_chunk_data List from prepare_c1_chunk_data() with tier1, tier2, negatives
#' @param model Character model ID (default: "claude-haiku-4-5-20251001")
#' @param n_test Integer total test texts (default 20, split evenly)
#' @param seed Integer random seed (default 20251206)
#' @return List with results for each test, overall_pass flag, and summary
#' @export
run_behavioral_tests_s1 <- function(codebook,
                                     aligned_data,
                                     c1_chunk_data,
                                     model = "claude-haiku-4-5-20251001",
                                     n_test = 20,
                                     seed = 20251206,
                                     max_tokens = 1024,
                                     provider = "anthropic",
                                     base_url = NULL,
                                     api_key = NULL) {
  set.seed(seed)

  n_pos <- floor(n_test / 2)
  n_neg <- n_test - n_pos

  tier1_chunks <- c1_chunk_data$tier1
  tier2_chunks <- c1_chunk_data$tier2
  negative_chunks <- c1_chunk_data$negatives

  # Positive test texts: sample from Tier 1+2 chunks
  positive_pool <- dplyr::bind_rows(tier1_chunks, tier2_chunks)
  if (nrow(positive_pool) > 0) {
    positive_sample <- positive_pool |>
      dplyr::slice_sample(n = min(n_pos, nrow(positive_pool)))
  } else {
    positive_sample <- tibble::tibble(text = character())
  }

  # Negative test texts: sample from negative chunks
  if (nrow(negative_chunks) > 0) {
    negative_sample <- negative_chunks |>
      dplyr::slice_sample(n = min(n_neg, nrow(negative_chunks)))
  } else {
    negative_sample <- tibble::tibble(text = character())
  }

  test_texts <- c(positive_sample$text, negative_sample$text)

  message(sprintf(
    "Running S1 behavioral tests with %d chunk-level test texts (%d pos, %d neg)",
    length(test_texts), nrow(positive_sample), nrow(negative_sample)
  ))

  # Test I: Legal Outputs
  message("  Test I: Legal Outputs...")
  test_i <- test_legal_outputs(codebook, test_texts, model,
                               max_tokens = max_tokens,
                               provider = provider, base_url = base_url,
                               api_key = api_key)
  message(sprintf("    %s (%.0f%% valid)",
                  if (test_i$pass) "PASS" else "FAIL", test_i$rate * 100))

  # Test II: Definition Recovery (tests codebook, not input format)
  message("  Test II: Definition Recovery...")
  test_ii <- test_definition_recovery(codebook, model,
                                      max_tokens = max_tokens,
                                      provider = provider, base_url = base_url,
                                      api_key = api_key)
  message(sprintf("    %s (%d/%d correct)",
                  if (test_ii$pass) "PASS" else "FAIL",
                  test_ii$n_correct, test_ii$n_total))

  # Test III: Example Recovery (skip if no examples in codebook)
  has_examples <- any(vapply(codebook$classes, function(cls) {
    length(cls$positive_examples) > 0 || length(cls$negative_examples) > 0
  }, logical(1)))

  if (has_examples) {
    message("  Test III: Example Recovery...")
    test_iii <- test_example_recovery(codebook, model,
                                      max_tokens = max_tokens,
                                      provider = provider, base_url = base_url,
                                      api_key = api_key)
    message(sprintf("    %s (%d/%d correct)",
                    if (test_iii$pass) "PASS" else "FAIL",
                    test_iii$n_correct, test_iii$n_total))
  } else {
    message("  Test III: Example Recovery... SKIPPED (no examples in codebook)")
    test_iii <- list(
      test = "III_example_recovery",
      pass = TRUE,
      n_correct = 0L,
      n_total = 0L,
      rate = 1.0,
      threshold = 1.0,
      details = tibble::tibble(
        class = character(), example_type = character(), example_idx = integer(),
        true_label = character(), pred_label = character(), correct = logical()
      ),
      skipped = TRUE
    )
  }

  # Test IV: Order Invariance (use chunk-level texts)
  n_order_test <- min(10, length(test_texts))
  order_texts <- test_texts[seq_len(n_order_test)]
  message(sprintf("  Test IV: Order Invariance (n=%d)...", n_order_test))
  test_iv <- test_order_invariance(codebook, order_texts, model,
                                   max_tokens = max_tokens,
                                   provider = provider, base_url = base_url,
                                   api_key = api_key)
  message(sprintf(
    "    %s (max change rate: %.1f%% [rev=%.1f%%, shuf=%.1f%%], kappa=%.3f %s)",
    if (test_iv$pass) "PASS" else "FAIL",
    test_iv$change_rate * 100,
    test_iv$change_rate_reversed * 100,
    test_iv$change_rate_shuffled * 100,
    test_iv$fleiss_kappa,
    test_iv$kappa_interpretation
  ))

  overall_pass <- test_i$pass && test_ii$pass && test_iii$pass && test_iv$pass

  message(sprintf("\nS1 Overall: %s", if (overall_pass) "ALL PASS" else "FAILED"))

  list(
    overall_pass = overall_pass,
    test_i = test_i,
    test_ii = test_ii,
    test_iii = test_iii,
    test_iv = test_iv,
    model = model,
    n_test_texts = length(test_texts),
    seed = seed,
    timestamp = Sys.time(),
    summary = tibble::tibble(
      test = c("I_legal_outputs", "II_definition_recovery",
               "III_example_recovery", "IV_order_invariance"),
      pass = c(test_i$pass, test_ii$pass, test_iii$pass, test_iv$pass),
      metric = c(test_i$rate, test_ii$rate, test_iii$rate, test_iv$change_rate),
      threshold = c(1.0, 1.0, 1.0, 0.05),
      comparison = c(">=", ">=", ">=", "<")
    )
  )
}
