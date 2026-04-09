# Codebook Stage 1: C2 S1 Behavioral Test Runners
# Orchestrators for C2a (evidence extraction) and C2b (motivation classification)
#
# Parallels R/codebook_stage_1.R but does NOT modify it.
# Each sub-codebook is tested independently at S1.

# =============================================================================
# Synthetic Test Data
# =============================================================================

#' Generate synthetic evidence sets for C2b behavioral tests
#'
#' Creates one synthetic evidence set per motivation category. Each set
#' contains 2-3 evidence items with clear signals pointing to the target
#' category, plus one enacted-status signal.
#'
#' @param seed Integer random seed (unused currently, reserved for future)
#' @return List of 4 evidence sets, each with act_name, year, evidence,
#'   enacted_signals
#' @keywords internal
generate_c2b_test_evidence <- function(seed = 42) {
  list(
    list(
      act_name = "Synthetic Spending-Driven Act",
      year = 2003,
      evidence = list(
        list(
          quote = "The tax increase was enacted to finance the new military operations abroad.",
          signal = "Revenue measure explicitly linked to financing a spending commitment",
          suggested_category = "SPENDING_DRIVEN"
        ),
        list(
          quote = "The revenue provisions and the defense appropriations were passed together as a single package.",
          signal = "Fiscal measure and spending change enacted together",
          suggested_category = "SPENDING_DRIVEN"
        )
      ),
      enacted_signals = list(
        list(
          quote = "The act was signed into law on November 5, 2003.",
          signal = "Signed into law"
        )
      )
    ),
    list(
      act_name = "Synthetic Countercyclical Act",
      year = 2009,
      evidence = list(
        list(
          quote = "With unemployment rising sharply and GDP contracting, the government enacted emergency tax relief.",
          signal = "Response to economic downturn, goal of restoring growth to normal",
          suggested_category = "COUNTERCYCLICAL"
        ),
        list(
          quote = "The stimulus package aims to counteract the recession and return the economy to its pre-crisis trajectory.",
          signal = "Explicit countercyclical framing, temporary measure",
          suggested_category = "COUNTERCYCLICAL"
        ),
        list(
          quote = "These temporary measures will expire once economic conditions normalize.",
          signal = "Temporary nature tied to cyclical conditions",
          suggested_category = "COUNTERCYCLICAL"
        )
      ),
      enacted_signals = list(
        list(
          quote = "The President signed the emergency relief package on February 17, 2009.",
          signal = "Signed into law"
        )
      )
    ),
    list(
      act_name = "Synthetic Deficit-Driven Act",
      year = 1993,
      evidence = list(
        list(
          quote = "The deficit, accumulated over many years of past policy decisions, threatens long-term fiscal stability.",
          signal = "Deficit described as inherited from past decisions",
          suggested_category = "DEFICIT_DRIVEN"
        ),
        list(
          quote = "The primary purpose of this act is to restore fiscal balance and reduce the structural budget deficit.",
          signal = "Stated goal of deficit reduction and fiscal prudence",
          suggested_category = "DEFICIT_DRIVEN"
        )
      ),
      enacted_signals = list(
        list(
          quote = "The Fiscal Responsibility Act was enacted on August 10, 1993.",
          signal = "Enacted into law"
        )
      )
    ),
    list(
      act_name = "Synthetic Long-Run Act",
      year = 1986,
      evidence = list(
        list(
          quote = "By broadening the tax base and lowering marginal rates, we can improve economic efficiency and raise long-run growth.",
          signal = "Structural reform aimed at raising growth above normal level",
          suggested_category = "LONG_RUN"
        ),
        list(
          quote = "The reform simplifies the tax code to improve incentives for investment and raise potential output.",
          signal = "Permanent structural change for efficiency and supply-side improvement",
          suggested_category = "LONG_RUN"
        )
      ),
      enacted_signals = list(
        list(
          quote = "The Economic Reform Act was signed into law on October 22, 1986.",
          signal = "Signed into law"
        )
      )
    )
  )
}


# =============================================================================
# C2a S1 Orchestrator
# =============================================================================

#' Run S1 behavioral tests for C2a (evidence extraction)
#'
#' Orchestrates Tests I, II, IV for the C2a extraction codebook.
#' Test III is skipped (no examples in codebook).
#'
#' @param codebook A validated C2a codebook object
#' @param c2_input_data Tibble from assemble_c2_input_data() with chunk text
#' @param model Character model ID (default: "claude-haiku-4-5-20251001")
#' @param n_test Integer number of chunks to sample for Tests I and IV
#' @param seed Integer random seed
#' @param max_tokens Integer max output tokens
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with results for each test, overall_pass flag, and summary
#' @export
run_c2a_behavioral_tests_s1 <- function(codebook,
                                        c2_input_data,
                                        model = "claude-haiku-4-5-20251001",
                                        n_test = 10,
                                        seed = 20251206,
                                        max_tokens = 1024,
                                        provider = "anthropic",
                                        base_url = NULL,
                                        api_key = NULL) {
  set.seed(seed)

  # Sample test chunks from c2_input_data
  n_available <- nrow(c2_input_data)
  n_sample <- min(n_test, n_available)
  test_chunks <- c2_input_data |>
    dplyr::slice_sample(n = n_sample) |>
    dplyr::select(text, act_name, year)

  message(sprintf(
    "Running C2a S1 behavioral tests with %d chunk-level test texts",
    nrow(test_chunks)
  ))

  # Test I: Legal Outputs
  message("  Test I: Legal Outputs...")
  test_i <- test_c2a_legal_outputs(codebook, test_chunks, model,
                                   max_tokens = max_tokens,
                                   provider = provider, base_url = base_url,
                                   api_key = api_key)
  message(sprintf("    %s (%.0f%% valid)",
                  if (test_i$pass) "PASS" else "FAIL", test_i$rate * 100))

  # Test II: Instruction Recovery
  message("  Test II: Instruction Recovery...")
  test_ii <- test_c2a_instruction_recovery(codebook, model,
                                           max_tokens = max_tokens,
                                           provider = provider, base_url = base_url,
                                           api_key = api_key)
  message(sprintf("    %s (%d/%d correct)",
                  if (test_ii$pass) "PASS" else "FAIL",
                  test_ii$n_correct, test_ii$n_total))

  # Test III: Example Recovery — SKIPPED (no examples in C2a codebook)
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

  # Test IV: Order Invariance
  n_order_test <- min(10, nrow(test_chunks))
  order_chunks <- test_chunks[seq_len(n_order_test), ]
  message(sprintf("  Test IV: Order Invariance (n=%d)...", n_order_test))
  test_iv <- test_c2a_order_invariance(codebook, order_chunks, model,
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

  message(sprintf("\nC2a S1 Overall: %s", if (overall_pass) "ALL PASS" else "FAILED"))

  list(
    overall_pass = overall_pass,
    test_i = test_i,
    test_ii = test_ii,
    test_iii = test_iii,
    test_iv = test_iv,
    model = model,
    n_test_texts = nrow(test_chunks),
    seed = seed,
    timestamp = Sys.time(),
    summary = tibble::tibble(
      test = c("I_legal_outputs", "II_instruction_recovery",
               "III_example_recovery", "IV_order_invariance"),
      pass = c(test_i$pass, test_ii$pass, test_iii$pass, test_iv$pass),
      metric = c(test_i$rate, test_ii$rate, test_iii$rate, test_iv$change_rate),
      threshold = c(1.0, 1.0, 1.0, 0.05),
      comparison = c(">=", ">=", ">=", "<")
    )
  )
}


# =============================================================================
# C2b S1 Orchestrator
# =============================================================================

#' Run S1 behavioral tests for C2b (motivation classification)
#'
#' Orchestrates Tests I, II, IV for the C2b classification codebook.
#' Uses synthetic evidence sets (no dependency on c2_input_data).
#' Test III is skipped (no examples in codebook).
#'
#' @param codebook A validated C2b codebook object
#' @param model Character model ID (default: "claude-haiku-4-5-20251001")
#' @param seed Integer random seed
#' @param max_tokens Integer max output tokens
#' @param provider Character provider name
#' @param base_url Optional API base URL
#' @param api_key Optional API key
#' @return List with results for each test, overall_pass flag, and summary
#' @export
run_c2b_behavioral_tests_s1 <- function(codebook,
                                        model = "claude-haiku-4-5-20251001",
                                        seed = 20251206,
                                        max_tokens = 1024,
                                        provider = "anthropic",
                                        base_url = NULL,
                                        api_key = NULL) {
  # Generate synthetic test evidence
  test_evidence_sets <- generate_c2b_test_evidence(seed = seed)

  message(sprintf(
    "Running C2b S1 behavioral tests with %d synthetic evidence sets",
    length(test_evidence_sets)
  ))

  # Test I: Legal Outputs
  message("  Test I: Legal Outputs...")
  test_i <- test_c2b_legal_outputs(codebook, test_evidence_sets, model,
                                   max_tokens = max_tokens,
                                   provider = provider, base_url = base_url,
                                   api_key = api_key)
  message(sprintf("    %s (%.0f%% valid)",
                  if (test_i$pass) "PASS" else "FAIL", test_i$rate * 100))

  # Test II: Definition Recovery
  message("  Test II: Definition Recovery...")
  test_ii <- test_c2b_definition_recovery(codebook, model,
                                          max_tokens = max_tokens,
                                          provider = provider, base_url = base_url,
                                          api_key = api_key)
  message(sprintf("    %s (%d/%d correct)",
                  if (test_ii$pass) "PASS" else "FAIL",
                  test_ii$n_correct, test_ii$n_total))

  # Test III: Example Recovery — SKIPPED (no examples in C2b codebook)
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

  # Test IV: Order Invariance
  message(sprintf("  Test IV: Order Invariance (n=%d)...", length(test_evidence_sets)))
  test_iv <- test_c2b_order_invariance(codebook, test_evidence_sets, model,
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

  # Additional C2b-specific diagnostics
  message(sprintf(
    "    Category change rate: %.1f%%, Exogenous change rate: %.1f%%",
    test_iv$change_rate_categories * 100,
    test_iv$change_rate_exogenous * 100
  ))

  overall_pass <- test_i$pass && test_ii$pass && test_iii$pass && test_iv$pass

  message(sprintf("\nC2b S1 Overall: %s", if (overall_pass) "ALL PASS" else "FAILED"))

  list(
    overall_pass = overall_pass,
    test_i = test_i,
    test_ii = test_ii,
    test_iii = test_iii,
    test_iv = test_iv,
    model = model,
    n_test_texts = length(test_evidence_sets),
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
