# Codebook Stage 1: C2 S1 Behavioral Test Runners
# Orchestrators for C2a (evidence extraction) and C2b (motivation classification)
#
# Parallels R/codebook_stage_1.R but does NOT modify it.
# Each sub-codebook is tested independently at S1.

# =============================================================================
# Synthetic Test Data
# =============================================================================

#' Generate synthetic evidence sets for C2b behavioral tests (v0.8.0)
#'
#' Creates six synthetic evidence sets exercising the v0.8.0 output schema:
#'
#' 1. Spending-financing tax increase (exo FALSE, sign +) — Vietnam-era surtax
#' 2. Countercyclical relief crossing a midpoint (exo FALSE, sign -) — effective
#'    November 20 (past Q4 midpoint Nov 15) → 2009Q1 next quarter
#' 3. Inherited-deficit reduction with phased steps (exo TRUE, sign +)
#'    — Jan 1, 1991 + Jan 1, 1992 effective dates
#' 4. Long-run rate reduction (exo TRUE, sign -) — different year/structure
#'    from the C2b YAML examples to keep schema recovery distinct from
#'    example recovery
#' 5. Phased exogenous reform (exo TRUE, sign -) — two phases with quarter
#'    set {1999Q4, 2000Q3} testing multi-quarter recovery
#' 6. Empty-timing reform (exo TRUE, sign -) — motivation evidence only,
#'    no enacted-status or timing signals; expected `enacted_quarter: []`
#'    and the model should not invent a date
#'
#' Years and structures are deliberately disjoint from the years used in the
#' C2b YAML's `examples:` block (1985, 2009, 1951, 1993, 1950) so Test II
#' (schema recovery) is not conflated with Test III (example recovery).
#'
#' Each case carries `expected_exogenous`, `expected_sign`, and
#' `expected_quarters` (character vector, possibly empty) fields used by
#' `test_c2b_schema_recovery()`.
#'
#' @param seed Integer random seed (unused currently, reserved for future)
#' @return List of 6 evidence sets, each with act_name, year, evidence,
#'   enacted_signals, timing_signals, expected_exogenous, expected_sign,
#'   expected_quarters
#' @keywords internal
generate_c2b_test_evidence <- function(seed = 42) {
  list(
    # 1. Spending-financing tax increase (Vietnam-era surtax, distinct from
    #    YAML's 1951 Defense Financing example)
    list(
      act_name = "Synthetic Vietnam-Era Defense Surtax",
      year = 1968,
      expected_exogenous = "FALSE",
      expected_sign = "+",
      expected_quarters = c("1968-Q3"),
      evidence = list(
        list(
          quote = "The surtax was enacted to finance the cost of military operations in Southeast Asia.",
          signal = "Revenue measure explicitly tied to financing contemporaneous defense spending"
        ),
        list(
          quote = "The revenue provisions accompany the supplemental defense appropriations passed earlier this year.",
          signal = "Fiscal measure and spending change enacted within the same year"
        )
      ),
      enacted_signals = list(
        list(
          quote = "The act was signed into law on June 28, 1968.",
          signal = "Signed into law"
        )
      ),
      timing_signals = list(
        list(
          quote = "The surtax took effect July 1, 1968.",
          signal = "Effective date — July 1, 1968 (1968Q3 under midpoint rule)"
        )
      )
    ),

    # 2. Countercyclical relief crossing the Q4 midpoint into Q1 next year.
    #    Effective Nov 20 is one day past the Nov 15 Q4 midpoint, so the act
    #    falls into 2009Q1 (next quarter) under the midpoint rule. Tests the
    #    midpoint-equality boundary.
    list(
      act_name = "Synthetic Year-End Pandemic Relief Act",
      year = 2008,
      expected_exogenous = "FALSE",
      expected_sign = "-",
      expected_quarters = c("2009-Q1"),
      evidence = list(
        list(
          quote = "With unemployment rising sharply and GDP contracting, the government enacted emergency tax relief.",
          signal = "Response to economic downturn"
        ),
        list(
          quote = "These temporary measures will expire once economic conditions normalize.",
          signal = "Temporary nature tied to cyclical conditions"
        )
      ),
      enacted_signals = list(
        list(
          quote = "The President signed the relief package on October 3, 2008.",
          signal = "Signed into law"
        )
      ),
      timing_signals = list(
        list(
          quote = "Provisions take effect November 20, 2008.",
          signal = "Effective November 20, 2008 — one day past Q4 midpoint (Nov 15) → 2009Q1 under midpoint rule"
        )
      )
    ),

    # 3. Inherited-deficit reduction, phased over two years (TRUE, +).
    #    Different year from YAML's 1993 Inherited Deficit Reduction Act.
    list(
      act_name = "Synthetic Federal Deficit Reform Act",
      year = 1990,
      expected_exogenous = "TRUE",
      expected_sign = "+",
      expected_quarters = c("1991-Q1", "1992-Q1"),
      evidence = list(
        list(
          quote = "The deficit, built up over many years of past policy decisions, threatens long-term fiscal stability.",
          signal = "Deficit described as inherited from past decisions"
        ),
        list(
          quote = "The primary purpose of the act is to reduce the structural budget deficit through higher revenues.",
          signal = "Stated goal of deficit reduction"
        )
      ),
      enacted_signals = list(
        list(
          quote = "The act was signed into law on November 5, 1990.",
          signal = "Signed into law"
        )
      ),
      timing_signals = list(
        list(
          quote = "Phase one provisions take effect January 1, 1991.",
          signal = "Phase 1 effective date — January 1, 1991 (1991Q1)"
        ),
        list(
          quote = "Phase two rate increases follow on January 1, 1992.",
          signal = "Phase 2 effective date — January 1, 1992 (1992Q1)"
        )
      )
    ),

    # 4. Long-run rate reduction (exo TRUE, sign -), different year and
    #    structure from YAML's 1985 Long-Run Rate Reduction Act.
    list(
      act_name = "Synthetic Tax Simplification Act",
      year = 1995,
      expected_exogenous = "TRUE",
      expected_sign = "-",
      expected_quarters = c("1996-Q1"),
      evidence = list(
        list(
          quote = "Lowering marginal income tax rates will improve incentives to invest and raise long-run economic growth.",
          signal = "Stated goal of structural reform aimed at raising potential output"
        ),
        list(
          quote = "The reform simplifies the rate structure as a permanent change to the tax instrument.",
          signal = "Permanent structural change to the fiscal instrument"
        )
      ),
      enacted_signals = list(
        list(
          quote = "The act was enacted on July 30, 1995.",
          signal = "Enacted into law"
        )
      ),
      timing_signals = list(
        list(
          quote = "The new rate structure takes effect January 1, 1996.",
          signal = "Effective date — January 1, 1996 (1996Q1)"
        )
      )
    ),

    # 5. Phased exogenous reform (exo TRUE, sign -) with two phases NOT in
    #    consecutive quarters — tests phased-act detection beyond simple Q1
    #    repetitions.
    list(
      act_name = "Synthetic Multi-Phase Investment Reform Act",
      year = 1999,
      expected_exogenous = "TRUE",
      expected_sign = "-",
      expected_quarters = c("1999-Q4", "2000-Q3"),
      evidence = list(
        list(
          quote = "The reform aims to raise long-run investment by phasing in lower marginal rates over two years.",
          signal = "Long-run growth motivation, permanent structural change"
        ),
        list(
          quote = "The act simplifies the depreciation schedule for capital investment.",
          signal = "Structural reform of the fiscal instrument"
        )
      ),
      enacted_signals = list(
        list(
          quote = "The act was signed into law on September 14, 1999.",
          signal = "Signed into law"
        )
      ),
      timing_signals = list(
        list(
          quote = "First-phase rate cuts take effect October 1, 1999.",
          signal = "Phase 1 effective date — October 1, 1999 (1999Q4)"
        ),
        list(
          quote = "Second-phase rate cuts follow on July 1, 2000.",
          signal = "Phase 2 effective date — July 1, 2000 (2000Q3)"
        )
      )
    ),

    # 6. Empty timing case: motivation only, no enacted-status or timing
    #    signals. Tests whether C2b correctly returns `enacted_quarter: []`
    #    rather than hallucinating a date.
    list(
      act_name = "Synthetic Sparse-Timing Reform Act",
      year = 1975,
      expected_exogenous = "TRUE",
      expected_sign = "-",
      expected_quarters = character(0),
      evidence = list(
        list(
          quote = "The reform was undertaken to improve long-run efficiency of the tax system through structural simplification.",
          signal = "Long-run motivation, permanent structural change"
        ),
        list(
          quote = "The provisions reduce marginal rates as part of a permanent restructuring.",
          signal = "Net reduction in fiscal liabilities through rate cuts"
        )
      ),
      enacted_signals = list(),
      timing_signals = list()
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
  if (isTRUE(test_iv$skipped)) {
    message("    SKIPPED (no classes to reorder)")
  } else {
    message(sprintf(
      "    %s (max change rate: %.1f%% [rev=%.1f%%, shuf=%.1f%%], kappa=%.3f %s)",
      if (test_iv$pass) "PASS" else "FAIL",
      test_iv$change_rate * 100,
      test_iv$change_rate_reversed * 100,
      test_iv$change_rate_shuffled * 100,
      test_iv$fleiss_kappa,
      test_iv$kappa_interpretation
    ))
  }

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
      metric = c(test_i$rate, test_ii$rate, test_iii$rate,
                 test_iv$change_rate %||% NA_real_),
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

  # Test II: Schema Recovery (v0.7.0+; replaces Definition Recovery)
  message("  Test II: Schema Recovery...")
  test_ii <- test_c2b_schema_recovery(codebook, test_evidence_sets, model,
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
  if (isTRUE(test_iv$skipped)) {
    message("    SKIPPED (no classes to reorder; v0.7.0+ minimal schema)")
  } else {
    message(sprintf(
      "    %s (max change rate: %.1f%% [rev=%.1f%%, shuf=%.1f%%], kappa=%.3f %s)",
      if (test_iv$pass) "PASS" else "FAIL",
      test_iv$change_rate * 100,
      test_iv$change_rate_reversed * 100,
      test_iv$change_rate_shuffled * 100,
      test_iv$fleiss_kappa,
      test_iv$kappa_interpretation
    ))
    if (!is.na(test_iv$change_rate_categories)) {
      message(sprintf(
        "    Category change rate: %.1f%%, Exogenous change rate: %.1f%%",
        test_iv$change_rate_categories * 100,
        test_iv$change_rate_exogenous * 100
      ))
    }
  }

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
      test = c("I_legal_outputs", "II_schema_recovery",
               "III_example_recovery", "IV_order_invariance"),
      pass = c(test_i$pass, test_ii$pass, test_iii$pass, test_iv$pass),
      metric = c(test_i$rate, test_ii$rate, test_iii$rate,
                 test_iv$change_rate %||% NA_real_),
      threshold = c(1.0, 1.0, 1.0, 0.05),
      comparison = c(">=", ">=", ">=", "<")
    )
  )
}
