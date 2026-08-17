# Business-cycle layer for the procyclicality use case (index.qmd #sec-usecase)
# and the external statutory-rate benchmark (#sec-my-validation).
#
# Everything here is driven by data/raw/Full_sample_filtered.dta, a
# cross-country annual macro-fiscal panel (107 countries, 1960-2030) whose
# provenance is documented in docs/data_sources.md. Two things in it matter:
# a real-GDP series, which gives Malaysia a business cycle the deliverable can
# be read against, and the Vegh and Vuletin (2015) statutory CIT/PIT top rates,
# which give the narrative rate paths their first external referent.
#
# Following the project's figure/table split, the data helpers return tidy
# frames (or a named list of them) and the plot helpers return ggplot objects;
# only data and statistics get targets, the plot helpers are called from the
# manuscript chunks. Reuses bind_components() from R/dataset_summary.R,
# .exo_palette / pretty_exogenous() / .tax_shock_theme() from
# R/tax_shock_report.R, and pretty_motivation() from R/malay_consistency.R.

# ---- Panel cleaning --------------------------------------------------------

# The panel columns we actually use, mapped to project-side names. The source
# carries 273 columns of WEO (NGDP_*) and GFS (i2_*) codes; renaming explicitly
# rather than programmatically keeps that mapping auditable and stops a
# name-cleaning pass from mangling the codes.
.macro_panel_cols <- c(
  ccode          = "ccode",
  country        = "country",
  region         = "region",
  group          = "group",
  incomegroup    = "incomegroup",
  emde           = "emde",
  year           = "year",
  gdp_real       = "NGDP_R",
  gdp_growth     = "NGDP_RPCH",
  output_gap     = "NGAP_NPGDP",
  cit_rate       = "corporate_tr",
  pit_rate       = "individual_tr",
  vat_rate       = "vat_tr",
  cut_cit_rate   = "change_corporate_tr",
  cut_pit_rate   = "change_individual_tr",
  exp_gdp        = "GGX_NGDP",
  rev_gdp        = "GGR_NGDP",
  balance_gdp    = "GGXCNL_NGDP",
  prim_exp_gdp   = "prim_gov_exp_weo"
)

#' Clean the cross-country macro-fiscal panel
#'
#' Strips Stata value labels, keeps the ~20 columns the procyclicality layer
#' uses, and trims the year window. The default upper bound is 2023 because
#' 2024 onward are WEO *forecasts*, which have no place in a historical
#' business cycle.
#'
#' First differences are **recomputed from the level series**, not taken from
#' the panel's `change_corporate_tr` / `change_individual_tr` columns. Those
#' columns record rate reductions only: across the panel, every one of the 72
#' corporate and 94 personal rate *increases* implied by the levels carries a
#' zero there. Treating them as first differences would drop every rate hike,
#' which biases any cyclicality statistic computed from them and would score a
#' correctly-identified hike as a false positive. They are kept under
#' `cut_cit_rate` / `cut_pit_rate` so the discrepancy stays inspectable.
#'
#' @param raw A `haven::read_dta()` tibble from Full_sample_filtered.dta.
#' @param iso Optional ISO3 filter (`ccode`); NULL keeps all countries.
#' @param year_min,year_max Inclusive year window.
#' @return Tibble with one row per country-year, or an empty tibble.
#' @export
clean_macro_panel <- function(raw, iso = NULL,
                              year_min = 1960L, year_max = 2023L) {
  if (is.null(raw) || nrow(raw) == 0) return(tibble::tibble())

  missing <- setdiff(unname(.macro_panel_cols), names(raw))
  if (length(missing) > 0) {
    stop("macro panel is missing expected columns: ",
         paste(missing, collapse = ", "))
  }

  out <- raw |>
    haven::zap_labels() |>
    haven::zap_label() |>
    dplyr::select(dplyr::all_of(.macro_panel_cols)) |>
    dplyr::mutate(
      dplyr::across(c(ccode, country, region, group, incomegroup),
                    as.character),
      year = as.integer(year),
      dplyr::across(c(gdp_real, gdp_growth, output_gap, cit_rate, pit_rate,
                      vat_rate, cut_cit_rate, cut_pit_rate, exp_gdp,
                      rev_gdp, balance_gdp, prim_exp_gdp, emde),
                    as.numeric)
    ) |>
    dplyr::filter(year >= year_min, year <= year_max)

  if (!is.null(iso)) out <- dplyr::filter(out, ccode %in% iso)

  out |>
    dplyr::arrange(ccode, year) |>
    dplyr::group_by(ccode) |>
    # Recomputed from levels; see the note above on the panel's cut-only
    # change columns. Gaps in the level series produce NA rather than a
    # spurious jump, because a diff across a gap is not a rate change.
    dplyr::mutate(
      d_cit_rate = cit_rate - dplyr::lag(cit_rate),
      d_pit_rate = pit_rate - dplyr::lag(pit_rate),
      d_cit_rate = dplyr::if_else(year - dplyr::lag(year) == 1L,
                                  d_cit_rate, NA_real_),
      d_pit_rate = dplyr::if_else(year - dplyr::lag(year) == 1L,
                                  d_pit_rate, NA_real_)
    ) |>
    dplyr::ungroup()
}

# ---- Cycle construction ----------------------------------------------------

#' Hodrick-Prescott trend (two-sided, base R)
#'
#' Closed-form solution of the HP minimisation, which is a single linear solve
#' and so needs no filtering package. `lambda = 100` is the annual convention.
#'
#' @param y Numeric vector with no NAs, length >= 4.
#' @param lambda Smoothing parameter.
#' @return The trend component, same length as `y`.
.hp_filter <- function(y, lambda = 100) {
  n <- length(y)
  if (n < 4) return(rep(NA_real_, n))
  eye <- diag(n)
  dmat <- diff(eye, differences = 2)
  as.vector(solve(eye + lambda * crossprod(dmat), y))
}

#' One country's annual business cycle and cycle state
#'
#' The cycle is the HP-filtered deviation of log real GDP from trend, in percent
#' of trend. Cycle *state* is deliberately returned under two definitions:
#'
#' - `cycle_state`: HP-based, below trend when the gap is negative.
#' - `cycle_state_growth`: growth below its own within-country median.
#'
#' Both are carried unconditionally because the HP filter has a real endpoint
#' problem here — Malaysia's 2020-21 collapse bends the trend enough that
#' 2017-19 score as above trend — and no choice of lambda fixes it. Carrying the
#' second definition through to a robustness row is honest; picking one and
#' staying quiet is not.
#'
#' @param macro_panel Output of `clean_macro_panel()`.
#' @param iso ISO3 country code.
#' @param year_min,year_max Inclusive window for the filter.
#' @param lambda HP smoothing parameter.
#' @return Tibble with one row per year, or an empty tibble.
#' @export
build_country_cycle <- function(macro_panel, iso = "MYS",
                                year_min = 1980L, year_max = 2023L,
                                lambda = 100) {
  if (is.null(macro_panel) || nrow(macro_panel) == 0) return(tibble::tibble())

  cty <- macro_panel |>
    dplyr::filter(ccode == iso, year >= year_min, year <= year_max,
                  !is.na(gdp_real)) |>
    dplyr::arrange(year)

  if (nrow(cty) < 4) return(tibble::tibble())

  log_gdp <- log(cty$gdp_real)
  trend   <- .hp_filter(log_gdp, lambda = lambda)
  growth_median <- stats::median(cty$gdp_growth, na.rm = TRUE)

  cty |>
    dplyr::mutate(
      log_gdp = log_gdp,
      trend   = trend,
      cycle   = 100 * (log_gdp - trend),
      cycle_state = factor(
        dplyr::if_else(cycle < 0, "Below trend", "Above trend"),
        levels = c("Below trend", "Above trend")
      ),
      cycle_state_growth = factor(
        dplyr::if_else(gdp_growth < growth_median, "Below trend", "Above trend"),
        levels = c("Below trend", "Above trend")
      )
    ) |>
    dplyr::select(ccode, country, year, gdp_real, gdp_growth, log_gdp, trend,
                  cycle, cycle_state, cycle_state_growth,
                  cit_rate, pit_rate, d_cit_rate, d_pit_rate,
                  exp_gdp, rev_gdp, balance_gdp)
}

#' Statutory-rate cyclicality, one row per country
#'
#' The Vegh and Vuletin (2015) object: the correlation between the change in a
#' statutory tax rate and the cyclical component of output. Computed here for
#' every country with enough data, so the manuscript can say how thin the
#' statistic is in general rather than only in Malaysia.
#'
#' @param macro_panel Output of `clean_macro_panel()`.
#' @param min_years Minimum non-missing real-GDP years required.
#' @param lambda HP smoothing parameter.
#' @return Tibble with one row per qualifying country, or an empty tibble.
#' @export
compute_vv_cyclicality <- function(macro_panel, min_years = 20L, lambda = 100) {
  if (is.null(macro_panel) || nrow(macro_panel) == 0) return(tibble::tibble())

  # Correlation plus its p-value, guarded for the many countries whose rate
  # series never moves (a constant has no correlation to report).
  cor_stat <- function(x, cycle) {
    ok <- !is.na(x) & !is.na(cycle)
    if (sum(ok) < 10 || stats::sd(x[ok]) == 0 || stats::sd(cycle[ok]) == 0) {
      return(list(estimate = NA_real_, p.value = NA_real_))
    }
    ct <- stats::cor.test(x[ok], cycle[ok])
    list(estimate = unname(ct$estimate), p.value = ct$p.value)
  }

  macro_panel |>
    dplyr::group_by(ccode, country, region, group, incomegroup) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::group_modify(function(g, key) {
      ok <- !is.na(g$gdp_real)
      if (sum(ok) < min_years) return(tibble::tibble())
      cycle <- rep(NA_real_, nrow(g))
      cycle[ok] <- 100 * (log(g$gdp_real[ok]) - .hp_filter(log(g$gdp_real[ok]),
                                                           lambda = lambda))
      cit <- cor_stat(g$d_cit_rate, cycle)
      pit <- cor_stat(g$d_pit_rate, cycle)
      tibble::tibble(
        n_years        = sum(ok),
        n_cit_changes  = sum(g$d_cit_rate != 0, na.rm = TRUE),
        n_pit_changes  = sum(g$d_pit_rate != 0, na.rm = TRUE),
        corr_cit_cycle = cit$estimate, p_cit = cit$p.value,
        corr_pit_cycle = pit$estimate, p_pit = pit$p.value
      )
    }) |>
    dplyr::ungroup()
}

# ---- Events on the cycle ---------------------------------------------------

# Fiscal impulse: what the action does to aggregate demand, which is NOT the
# same axis as what it does to tax liabilities. A spending increase and a tax
# cut are both expansionary; the existing inventory figures sign by liability
# direction and would pool them wrongly here.
.fiscal_impulse <- function(component, direction) {
  dplyr::case_when(
    component == "Spending" & direction == "Increase" ~ "Expansionary",
    component == "Spending" & direction == "Decrease" ~ "Contractionary",
    component != "Spending" & direction == "Cut"      ~ "Expansionary",
    component != "Spending" & direction == "Hike"     ~ "Contractionary",
    TRUE                                              ~ NA_character_
  )
}

# The same impulse mapping read off the model's signed verdict instead of the
# human-stamped direction. `c2b_sign` is the sign of the instrument itself
# (liabilities for tax and incentives, outlays for spending), so it flips
# meaning across components exactly as `direction` does.
.impulse_from_sign <- function(component, c2b_sign) {
  dplyr::case_when(
    component == "Spending" & c2b_sign == "+" ~ "Expansionary",
    component == "Spending" & c2b_sign == "-" ~ "Contractionary",
    component != "Spending" & c2b_sign == "-" ~ "Expansionary",
    component != "Spending" & c2b_sign == "+" ~ "Contractionary",
    TRUE                                      ~ NA_character_
  )
}

#' Bind the component deliverables, sign them by impulse, join the cycle
#'
#' Stance is the object the decomposition turns on: an action is *procyclical*
#' when it pushes in the same direction the cycle is already going, i.e.
#' expansionary in a boom or contractionary in a bust.
#'
#' `direction` is the sign source because it is human-stamped during act
#' identification; `c2b_sign` is a model read carried alongside as a cross-check
#' in `sign_conflict`. Where they disagree the disagreement is reported, never
#' silently resolved.
#'
#' @param tax,spending,incentive Deliverable tibbles. Any may be empty.
#' @param cycle Output of `build_country_cycle()`.
#' @param timing "effective" uses the deliverable's effective-year-first `year`;
#'   "announced" overrides it with the announcement year (robustness row).
#' @return Tibble with one row per event, or an empty tibble.
#' @export
assemble_procyclicality_events <- function(tax = NULL, spending = NULL,
                                           incentive = NULL, cycle,
                                           timing = c("effective", "announced")) {
  timing <- match.arg(timing)
  events <- bind_components(tax, spending, incentive)
  if (nrow(events) == 0 || is.null(cycle) || nrow(cycle) == 0) {
    return(tibble::tibble())
  }

  if (timing == "announced") {
    events <- dplyr::mutate(events, year = as.integer(announced_year))
  }

  events |>
    dplyr::mutate(year = as.integer(year)) |>
    dplyr::left_join(
      dplyr::select(cycle, year, cycle, cycle_state, cycle_state_growth,
                    gdp_growth),
      by = "year"
    ) |>
    dplyr::mutate(
      impulse = .fiscal_impulse(as.character(component), direction),
      stance  = .procyc_stance(impulse, cycle_state),
      stance_growth = .procyc_stance(impulse, cycle_state_growth),
      exogeneity = pretty_exogenous(c2b_exogenous),
      motivation = pretty_motivation(c2b_label),
      # The model's sign and the human-stamped direction should imply the same
      # impulse; where they do not, the manuscript footnotes it rather than
      # picking one.
      impulse_c2b  = .impulse_from_sign(as.character(component), c2b_sign),
      sign_conflict = dplyr::if_else(
        is.na(impulse) | is.na(impulse_c2b), NA, impulse != impulse_c2b
      )
    )
}

# Stance from impulse and cycle state. Procyclical = pushing with the cycle.
.procyc_stance <- function(impulse, state) {
  lab <- dplyr::case_when(
    is.na(impulse) | is.na(state) ~ NA_character_,
    impulse == "Expansionary"   & state == "Above trend" ~ "Procyclical",
    impulse == "Contractionary" & state == "Below trend" ~ "Procyclical",
    TRUE ~ "Countercyclical"
  )
  factor(lab, levels = c("Countercyclical", "Procyclical"))
}

# ---- The decomposition -----------------------------------------------------

# Stance x exogeneity as a 2x2 with stable dimnames, so downstream code can
# index cells by name rather than by position.
.stance_table <- function(events, stance_col = "stance") {
  keep <- !is.na(events[[stance_col]]) & !is.na(events$exogeneity)
  table(stance    = droplevels(events[[stance_col]][keep]),
        exogeneity = droplevels(events$exogeneity[keep]))
}

# Fisher's exact p for a 2x2, NA when the table has degenerated.
.fisher_p <- function(tb) {
  if (!identical(dim(tb), c(2L, 2L))) return(NA_real_)
  stats::fisher.test(tb)$p.value
}

#' Decompose the fiscal record into procyclical timing and cyclical motivation
#'
#' The question the narrative labels answer and a rate correlation cannot: of
#' the actions whose *timing* looks procyclical, how many were actually taken
#' *because of* the cycle?
#'
#' Uncertainty is reported three ways, deliberately not as a single p-value.
#'
#' - `fisher`: the exact test. A permutation test on a 2x2 with both margins
#'   fixed *is* Fisher's exact test, so simulating one would add a seed and a
#'   reproducibility surface to return an identical number.
#' - `fragility`: the minimum number of exogenous-to-endogenous relabels among
#'   the procyclical-exogenous events that pushes the exact p above 0.05. At
#'   this sample size the binding uncertainty is not sampling noise, it is that
#'   the labels are model output, and only this quantity speaks to that.
#' - `phase_perm`: a circular shift of the cycle series, which preserves its
#'   serial correlation and the events' clustering and asks whether the
#'   association is special to the actual phase of the cycle.
#'
#' @param events Output of `assemble_procyclicality_events()`.
#' @param cycle Output of `build_country_cycle()`.
#' @param events_announced Optional second assembly dated by announcement year
#'   rather than effective year, contributing one robustness row.
#' @param alpha Significance level the fragility index is measured against.
#' @return A named list of tidy frames and scalars, or NULL if there is nothing
#'   to decompose.
#' @export
decompose_procyclicality <- function(events, cycle, events_announced = NULL,
                                     alpha = 0.05) {
  if (is.null(events) || nrow(events) == 0) return(NULL)

  tb <- .stance_table(events)
  if (!identical(dim(tb), c(2L, 2L))) return(NULL)
  ft <- stats::fisher.test(tb)

  counts <- tibble::as_tibble(as.data.frame(tb, stringsAsFactors = FALSE)) |>
    dplyr::rename(n = Freq)

  # --- Fragility: flip procyclical-exogenous labels until the test breaks ----
  proc_exo <- which(events$stance %in% "Procyclical" &
                      events$exogeneity %in% "Exogenous")
  fragility <- NA_integer_
  frag_path <- tibble::tibble(n_flipped = integer(), p_value = numeric())
  if (length(proc_exo) > 0) {
    for (k in seq_along(proc_exo)) {
      flipped <- events
      flipped$exogeneity[proc_exo[seq_len(k)]] <- "Endogenous"
      p_k <- .fisher_p(.stance_table(flipped))
      frag_path <- dplyr::bind_rows(frag_path,
                                    tibble::tibble(n_flipped = k, p_value = p_k))
      if (is.na(fragility) && !is.na(p_k) && p_k > alpha) fragility <- k
    }
  }

  # --- The pipeline's own error signal on the same events -------------------
  # Two independent preliminary reads per act; where they disagree, the act is
  # already flagged for adjudication. If the flagged count sits below the
  # fragility index, the known-uncertain labels cannot overturn the result.
  disagree <- events |>
    dplyr::mutate(
      prelim = dplyr::case_when(
        toupper(as.character(exogenous_preliminary)) == "TRUE"  ~ TRUE,
        toupper(as.character(exogenous_preliminary)) == "FALSE" ~ FALSE,
        TRUE ~ NA
      ),
      disagrees = !is.na(prelim) & !is.na(c2b_exogenous) & prelim != c2b_exogenous
    )
  disagree_n <- sum(disagree$disagrees & disagree$stance %in% "Procyclical")

  # --- Robustness across cycle definition, timing and component scope -------
  spec <- function(label, tab) {
    if (!identical(dim(tab), c(2L, 2L))) {
      return(tibble::tibble(spec = label, n = sum(tab),
                            proc_exo = NA_integer_, proc_total = NA_integer_,
                            p_value = NA_real_))
    }
    tibble::tibble(
      spec       = label,
      n          = sum(tab),
      proc_exo   = tab["Procyclical", "Exogenous"],
      proc_total = sum(tab["Procyclical", ]),
      p_value    = .fisher_p(tab)
    )
  }
  robustness <- dplyr::bind_rows(
    spec("HP-filtered cycle (baseline)", tb),
    spec("Growth below within-country median",
         .stance_table(events, "stance_growth")),
    if (!is.null(events_announced) && nrow(events_announced) > 0) {
      spec("Dated by announcement year", .stance_table(events_announced))
    },
    spec("Excluding spending",
         .stance_table(dplyr::filter(events, component != "Spending")))
  )

  # --- Circular-shift phase permutation ------------------------------------
  phase <- .phase_permutation(events, cycle)

  list(
    counts     = counts,
    table      = tb,
    fisher     = tibble::tibble(odds_ratio = unname(ft$estimate),
                                p_value    = ft$p.value,
                                conf_low   = ft$conf.int[1],
                                conf_high  = ft$conf.int[2]),
    fragility  = fragility,
    frag_path  = frag_path,
    disagree_n = disagree_n,
    robustness = robustness,
    phase_perm = phase,
    n_events   = nrow(events),
    n_scored   = sum(!is.na(events$stance) & !is.na(events$exogeneity))
  )
}

# ---- External statutory-rate benchmark -------------------------------------

#' Compare the narrative rate paths against the Vegh-Vuletin rate panel
#'
#' The one external referent the Malaysia deliverable admits. It checks the
#' *rate path* only, not motivation: the panel carries a headline top rate per
#' year and nothing about why it moved.
#'
#' Matching is on `(tax_type, year)` first, then within a +/- `tolerance`-year
#' window comparing the *net* change rather than each event's change, so a
#' narrative pass that resolves one panel step into two annual steps reconciles
#' as a timing difference instead of producing one false miss and one false
#' extra.
#'
#' Non-matches are classified by a rule, not by hand: an external change before
#' the first year the narrative pass covers that instrument predates corpus
#' coverage, and a narrative change with no headline-rate delta is one a
#' top-rate series cannot represent.
#'
#' @param tax_shocks The `tax_shocks` deliverable tibble.
#' @param macro_panel Output of `clean_macro_panel()`.
#' @param iso ISO3 country code.
#' @param tolerance Half-width of the year window, in years.
#' @return A named list with `$paths` (long, for the step overlay) and
#'   `$events` (one row per change from either side), or NULL.
#' @export
compare_rate_paths <- function(tax_shocks, macro_panel, iso = "MYS",
                               tolerance = 1L) {
  if (is.null(tax_shocks) || nrow(tax_shocks) == 0) return(NULL)
  if (is.null(macro_panel) || nrow(macro_panel) == 0) return(NULL)

  panel <- dplyr::filter(macro_panel, ccode == iso)
  if (nrow(panel) == 0) return(NULL)

  # --- External path and its changes ---------------------------------------
  ext_path <- dplyr::bind_rows(
    dplyr::transmute(panel, tax_type = "CIT", year, rate = cit_rate),
    dplyr::transmute(panel, tax_type = "PIT", year, rate = pit_rate)
  ) |>
    dplyr::filter(!is.na(rate)) |>
    dplyr::mutate(source = "Végh–Vuletin panel")

  ext_chg <- dplyr::bind_rows(
    dplyr::transmute(panel, tax_type = "CIT", year, delta = d_cit_rate),
    dplyr::transmute(panel, tax_type = "PIT", year, delta = d_pit_rate)
  ) |>
    dplyr::filter(!is.na(delta), delta != 0)

  # --- Narrative path and its changes --------------------------------------
  nar <- tax_shocks |>
    dplyr::filter(tax_type %in% c("CIT", "PIT"), !is.na(effective_year)) |>
    dplyr::transmute(tax_type, year = as.integer(effective_year),
                     shock_id, act_label,
                     rate_from = as.numeric(rate_from),
                     rate_to   = as.numeric(rate_to),
                     delta     = as.numeric(delta_pp))

  nar_chg <- nar |>
    dplyr::filter(!is.na(delta), delta != 0) |>
    dplyr::group_by(tax_type, year) |>
    dplyr::summarise(delta = sum(delta),
                     shock_id = paste(shock_id, collapse = "; "),
                     act_label = paste(act_label, collapse = "; "),
                     .groups = "drop")

  # Narrative rate path: seed at the earliest rate_from, step to each rate_to.
  nar_path <- nar |>
    dplyr::filter(!is.na(rate_to)) |>
    dplyr::arrange(tax_type, year) |>
    dplyr::group_by(tax_type) |>
    dplyr::group_modify(function(g, key) {
      seed <- tibble::tibble(year = min(g$year) - 1L,
                             rate = g$rate_from[which.min(g$year)])
      dplyr::bind_rows(seed, dplyr::transmute(g, year, rate = rate_to)) |>
        dplyr::filter(!is.na(rate))
    }) |>
    dplyr::ungroup() |>
    dplyr::mutate(source = "Narrative (this paper)")

  # --- Match ---------------------------------------------------------------
  # First year the narrative pass reaches each instrument; external changes
  # before it are a corpus-coverage fact, not a reading failure.
  first_covered <- nar |>
    dplyr::group_by(tax_type) |>
    dplyr::summarise(first_year = min(year), .groups = "drop")

  ext_open <- dplyr::mutate(ext_chg, matched = FALSE, status = NA_character_,
                            partner = NA_character_, delta_nar = NA_real_)
  nar_open <- dplyr::mutate(nar_chg, matched = FALSE)

  for (i in seq_len(nrow(ext_open))) {
    cand <- which(!nar_open$matched &
                    nar_open$tax_type == ext_open$tax_type[i] &
                    abs(nar_open$year - ext_open$year[i]) <= tolerance)
    if (length(cand) == 0) next
    exact <- cand[nar_open$year[cand] == ext_open$year[i]]
    # Prefer the same-year change; otherwise take the window and check whether
    # its net movement reproduces the panel's step.
    if (length(exact) == 1 &&
        isTRUE(all.equal(nar_open$delta[exact], ext_open$delta[i]))) {
      use <- exact; lab <- "Matched"
    } else if (isTRUE(all.equal(sum(nar_open$delta[cand]), ext_open$delta[i]))) {
      use <- cand
      lab <- if (length(cand) == 1 && length(exact) == 1) "Matched" else
        "Timing or aggregation"
    } else if (length(exact) == 1) {
      use <- exact; lab <- "Matched, magnitude differs"
    } else {
      next
    }
    nar_open$matched[use] <- TRUE
    ext_open$matched[i]   <- TRUE
    ext_open$status[i]    <- lab
    ext_open$partner[i]   <- paste(nar_open$shock_id[use], collapse = "; ")
    ext_open$delta_nar[i] <- sum(nar_open$delta[use])
  }

  matched_rows <- ext_open |>
    dplyr::filter(matched) |>
    dplyr::transmute(tax_type, year, status, shock_id = partner,
                     delta_external = delta, delta_narrative = delta_nar,
                     reason = NA_character_)

  external_only <- ext_open |>
    dplyr::filter(!matched) |>
    dplyr::left_join(first_covered, by = "tax_type") |>
    dplyr::transmute(
      tax_type, year, status = "External only", shock_id = NA_character_,
      delta_external = delta, delta_narrative = NA_real_,
      reason = dplyr::if_else(
        !is.na(first_year) & year < first_year,
        "Predates corpus coverage",
        "Not surfaced by the narrative pass"
      )
    )

  # Narrative events with no external counterpart: either the pass found a
  # change the panel missed, or the act does not move a headline top rate at
  # all, which a top-rate series cannot represent by construction.
  narrative_only <- dplyr::bind_rows(
    nar_open |>
      dplyr::filter(!matched) |>
      dplyr::transmute(tax_type, year, shock_id, delta_narrative = delta,
                       no_headline = FALSE),
    nar |>
      dplyr::filter(is.na(delta) | delta == 0) |>
      dplyr::transmute(tax_type, year, shock_id, delta_narrative = delta,
                       no_headline = TRUE)
  ) |>
    dplyr::transmute(
      tax_type, year, status = "Narrative only", shock_id,
      delta_external = NA_real_, delta_narrative,
      reason = dplyr::if_else(
        no_headline,
        "No change to the headline top rate",
        "Moves liabilities without moving the headline top rate"
      )
    )

  events <- dplyr::bind_rows(matched_rows, external_only, narrative_only) |>
    dplyr::arrange(tax_type, year)

  list(paths  = dplyr::bind_rows(ext_path, nar_path),
       events = events)
}

# Shift the cycle series circularly by every non-zero lag, reassign stance, and
# recompute the association. Preserves the cycle's serial correlation and the
# events' clustering in time, which a label shuffle does not. Only n-1 distinct
# shifts exist, so the finest attainable p is 1/n -- a coarse diagnostic, not a
# headline, and the caption says so.
.phase_permutation <- function(events, cycle) {
  if (is.null(cycle) || nrow(cycle) < 4) return(NULL)
  obs <- .fisher_p(.stance_table(events))
  if (is.na(obs)) return(NULL)

  n <- nrow(cycle)
  shifted_p <- vapply(seq_len(n - 1), function(k) {
    shifted <- cycle |>
      dplyr::mutate(cycle_state = cycle_state[c((k + 1):n, 1:k)]) |>
      dplyr::select(year, cycle_state)
    ev <- events |>
      dplyr::select(-cycle_state) |>
      dplyr::left_join(shifted, by = "year") |>
      dplyr::mutate(stance = .procyc_stance(impulse, cycle_state))
    .fisher_p(.stance_table(ev))
  }, numeric(1))

  tibble::tibble(
    observed_p = obs,
    n_shifts   = length(shifted_p),
    n_stronger = sum(shifted_p <= obs, na.rm = TRUE),
    p_phase    = (1 + sum(shifted_p <= obs, na.rm = TRUE)) / (1 + length(shifted_p))
  )
}

# ---- Presentation layer ----------------------------------------------------

# Contiguous runs of below-trend years, as rectangles for the figure backdrop.
.bust_bands <- function(cycle) {
  below <- cycle$cycle_state == "Below trend"
  if (!any(below, na.rm = TRUE)) return(NULL)
  run <- rle(dplyr::coalesce(below, FALSE))
  ends <- cumsum(run$lengths)
  starts <- ends - run$lengths + 1L
  keep <- which(run$values)
  tibble::tibble(
    xmin = cycle$year[starts[keep]] - 0.5,
    xmax = cycle$year[ends[keep]] + 0.5
  )
}

#' The Malaysian cycle with the fiscal record laid over it
#'
#' Two panels on a shared year axis. The upper panel is the output gap; the
#' lower is one mark per fiscal action, expansionary above the line and
#' contractionary below, coloured by exogeneity. The below-trend bands are
#' drawn behind *both* panels, so a reader can drop straight from a downturn
#' into the column of actions taken during it.
#'
#' Marks are stacked deterministically within a year rather than jittered:
#' jitter would move an event off its year, and the year is the entire claim.
#'
#' @param cycle Output of `build_country_cycle()`.
#' @param events Output of `assemble_procyclicality_events()`.
#' @return A patchwork object, or NULL if either input is empty.
#' @export
plot_procyclicality_overlay <- function(cycle, events) {
  if (is.null(cycle) || nrow(cycle) == 0) return(NULL)
  if (is.null(events) || nrow(events) == 0) return(NULL)

  bands <- .bust_bands(cycle)
  band_layer <- function() {
    if (is.null(bands)) return(NULL)
    ggplot2::geom_rect(
      data = bands, inherit.aes = FALSE,
      ggplot2::aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
      fill = "grey88"
    )
  }
  xscale <- ggplot2::scale_x_continuous(
    breaks = scales::breaks_width(5),
    limits = c(min(cycle$year) - 0.5, max(cycle$year) + 0.5)
  )

  p_cycle <- ggplot2::ggplot(cycle, ggplot2::aes(year, cycle)) +
    band_layer() +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
    ggplot2::geom_line(linewidth = 0.6, colour = "grey20") +
    xscale +
    ggplot2::labs(x = NULL, y = "Output gap\n(% of trend)") +
    .tax_shock_theme() +
    ggplot2::theme(panel.grid.major.x = ggplot2::element_blank())

  marks <- events |>
    dplyr::filter(!is.na(impulse), !is.na(year)) |>
    dplyr::arrange(year, impulse) |>
    dplyr::group_by(year, impulse) |>
    dplyr::mutate(
      slot = dplyr::row_number(),
      ypos = dplyr::if_else(impulse == "Expansionary", slot, -slot)
    ) |>
    dplyr::ungroup()
  # Only carry the "unclassified" level when something actually lands in it,
  # so the legend does not advertise an empty category.
  if (anyNA(marks$exogeneity)) {
    marks <- dplyr::mutate(
      marks,
      exogeneity = forcats::fct_na_value_to_level(exogeneity, "Unclassified")
    )
  }

  p_events <- ggplot2::ggplot(marks, ggplot2::aes(year, ypos)) +
    band_layer() +
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.3, colour = "grey40") +
    ggplot2::geom_point(ggplot2::aes(colour = exogeneity, shape = component),
                        size = 2) +
    xscale +
    ggplot2::scale_y_continuous(breaks = scales::breaks_width(2),
                                labels = abs) +
    ggplot2::scale_colour_manual(
      values = c(.exo_palette, Unclassified = "grey60"),
      name = "Motivation", drop = FALSE
    ) +
    ggplot2::scale_shape_manual(values = c(16, 17, 15), name = "Component",
                                drop = FALSE) +
    ggplot2::labs(x = NULL, y = "Acts\n(contractionary ↓ / expansionary ↑)") +
    .tax_shock_theme() +
    ggplot2::theme(
      panel.grid.major.x = ggplot2::element_blank(),
      # Collected below the whole figure: leaving the guides on this panel puts
      # them between the two panels, which breaks the read-straight-down device.
      # Stacked rather than side by side, because two horizontal legend blocks
      # overflow the single-column text block.
      legend.position = "bottom",
      legend.box = "vertical",
      legend.margin = ggplot2::margin(0, 0, 0, 0)
    )

  patchwork::wrap_plots(p_cycle, p_events, ncol = 1, heights = c(1, 1.4)) +
    patchwork::plot_layout(guides = "collect") &
    ggplot2::theme(legend.position = "bottom", legend.box = "vertical")
}

#' Stance by motivation, as counts
#'
#' Shows where each stance bucket's mass comes from: the countercyclical column
#' is dominated by acts the codebook labelled countercyclical, while the
#' procyclical column is long-run and deficit-driven measures that happened to
#' land against the cycle.
#'
#' @param events Output of `assemble_procyclicality_events()`.
#' @return A ggplot, or NULL if no event carries a stance.
#' @export
plot_procyclicality_decomposition <- function(events) {
  if (is.null(events) || nrow(events) == 0) return(NULL)
  dat <- dplyr::filter(events, !is.na(stance), !is.na(motivation))
  if (nrow(dat) == 0) return(NULL)

  # Drop motivation levels no act actually carries: a legend key with no mass
  # behind it invites the reader to look for a category that is not there.
  dat <- dplyr::mutate(dat, motivation = droplevels(motivation))

  dat |>
    dplyr::count(stance, motivation) |>
    ggplot2::ggplot(ggplot2::aes(stance, n, fill = motivation)) +
    ggplot2::geom_col(width = 0.6) +
    ggplot2::scale_fill_manual(values = .malay_motivation_palette,
                               name = "Motivation", drop = TRUE) +
    ggplot2::labs(x = NULL, y = "Acts") +
    .tax_shock_theme() +
    ggplot2::theme(legend.position = "top", legend.box = "vertical")
}

#' Where Malaysia sits in the cross-country statutory-rate cyclicality spread
#'
#' @param vv Output of `compute_vv_cyclicality()`.
#' @param highlight ISO3 code to mark.
#' @return A ggplot, or NULL if nothing qualifies.
#' @export
plot_vv_context <- function(vv, highlight = "MYS") {
  if (is.null(vv) || nrow(vv) == 0) return(NULL)
  dat <- dplyr::filter(vv, !is.na(corr_cit_cycle))
  if (nrow(dat) == 0) return(NULL)
  mark <- dplyr::filter(dat, ccode == highlight)

  p <- ggplot2::ggplot(dat, ggplot2::aes(corr_cit_cycle)) +
    ggplot2::geom_histogram(binwidth = 0.05, fill = "grey75", colour = "white",
                            linewidth = 0.2) +
    ggplot2::geom_vline(xintercept = 0, linewidth = 0.3, colour = "grey40")

  if (nrow(mark) > 0) {
    p <- p +
      ggplot2::geom_vline(data = mark,
                          ggplot2::aes(xintercept = corr_cit_cycle),
                          colour = .exo_palette[["Exogenous"]], linewidth = 0.8) +
      ggplot2::geom_text(data = mark,
                         ggplot2::aes(x = corr_cit_cycle, y = Inf,
                                      label = country),
                         hjust = -0.15, vjust = 1.6, size = 3,
                         colour = .exo_palette[["Exogenous"]])
  }

  p +
    ggplot2::labs(
      x = "Correlation of the corporate-rate change with the output gap",
      y = "Countries"
    ) +
    .tax_shock_theme()
}

#' Narrative rate paths against the Vegh-Vuletin statutory-rate panel
#'
#' Exact agreement reads as the dark narrative line sitting inside the thick
#' grey panel line.
#'
#' @param concordance Output of `compare_rate_paths()`.
#' @return A ggplot, or NULL.
#' @export
plot_rate_path_validation <- function(concordance) {
  if (is.null(concordance) || nrow(concordance$paths) == 0) return(NULL)
  # Level order is draw order: the thick panel line has to go down first, or it
  # paints over the narrative path and the agreement becomes invisible.
  paths <- concordance$paths |>
    dplyr::mutate(source = factor(
      source, levels = c("Végh–Vuletin panel", "Narrative (this paper)")
    ))

  ggplot2::ggplot(paths, ggplot2::aes(year, rate, colour = source,
                                      linewidth = source)) +
    ggplot2::geom_step(direction = "hv") +
    ggplot2::geom_point(
      data = dplyr::filter(paths, source == "Narrative (this paper)"),
      size = 1.1, show.legend = FALSE
    ) +
    ggplot2::facet_wrap(~ tax_type, ncol = 1) +
    ggplot2::scale_colour_manual(
      values = c(`Végh–Vuletin panel` = "grey70",
                 `Narrative (this paper)` = "grey15"),
      name = NULL
    ) +
    ggplot2::scale_linewidth_manual(
      values = c(`Végh–Vuletin panel` = 1.8, `Narrative (this paper)` = 0.6),
      guide = "none"
    ) +
    ggplot2::scale_y_continuous(labels = scales::label_percent(scale = 1)) +
    ggplot2::scale_x_continuous(breaks = scales::breaks_width(5)) +
    ggplot2::labs(x = NULL, y = "Statutory top rate") +
    .tax_shock_theme() +
    ggplot2::theme(legend.position = "top")
}

#' The decomposition as a styled table
#'
#' @param decomp Output of `decompose_procyclicality()`.
#' @return A tinytable, or NULL.
#' @export
procyclicality_table <- function(decomp) {
  if (is.null(decomp)) return(NULL)
  # The baseline p belongs on the Procyclical row itself; repeating it as a
  # robustness row would duplicate the counts directly above it.
  baseline_p <- decomp$robustness$p_value[1]
  body <- decomp$counts |>
    tidyr::pivot_wider(names_from = exogeneity, values_from = n,
                       values_fill = 0L) |>
    dplyr::mutate(
      Total = Exogenous + Endogenous,
      dplyr::across(c(Exogenous, Endogenous, Total), as.character),
      p = dplyr::if_else(stance == "Procyclical",
                         formatC(baseline_p, format = "g", digits = 2), "")
    ) |>
    dplyr::rename(Stance = stance)

  rob <- decomp$robustness |>
    dplyr::slice(-1) |>
    dplyr::transmute(
      Stance = spec,
      Exogenous = as.character(proc_exo),
      Endogenous = as.character(proc_total - proc_exo),
      Total = as.character(proc_total),
      p = formatC(p_value, format = "g", digits = 2)
    )

  out <- dplyr::bind_rows(body, rob)
  names(out)[names(out) == "Stance"] <- "Stance / specification"
  names(out)[names(out) == "p"] <- "Exact p"

  tinytable::tt(out, width = c(0.44, 0.16, 0.16, 0.12, 0.12)) |>
    tt_theme_report() |>
    tinytable::style_tt(j = 1, align = "l") |>
    tinytable::style_tt(i = nrow(body), line = "b", line_width = 0.05)
}

#' The statutory-rate measure and the narrative decomposition, side by side
#'
#' @param decomp Output of `decompose_procyclicality()`.
#' @param vv Output of `compute_vv_cyclicality()`.
#' @param iso ISO3 code of the deployment country.
#' @return A tinytable, or NULL.
#' @export
vv_comparison_table <- function(decomp, vv, iso = "MYS") {
  if (is.null(decomp) || is.null(vv) || nrow(vv) == 0) return(NULL)
  me <- dplyr::filter(vv, ccode == iso)
  pool <- dplyr::filter(vv, !is.na(corr_cit_cycle))
  tb <- decomp$table
  fisher_p <- decomp$fisher$p_value

  num <- function(x, d = 2) formatC(x, format = "f", digits = d)

  tibble::tibble(
    Measure = c(
      "Végh–Vuletin rate cyclicality, corporate",
      "Végh–Vuletin rate cyclicality, personal",
      "Rate changes available to it",
      "Rate changes, median country in the panel",
      "Narrative decomposition, procyclical acts",
      "Of those, motivated by something other than the cycle",
      "Relabels needed to overturn it"
    ),
    Value = c(
      paste0(num(me$corr_cit_cycle), " (p = ", num(me$p_cit), ")"),
      paste0(num(me$corr_pit_cycle), " (p = ", num(me$p_pit), ")"),
      paste0(me$n_cit_changes, " corporate, ", me$n_pit_changes,
             " personal, in ", me$n_years, " years"),
      paste0(stats::median(pool$n_cit_changes), " across ", nrow(pool),
             " countries"),
      paste0(sum(tb["Procyclical", ]), " of ", sum(tb), " acts"),
      paste0(tb["Procyclical", "Exogenous"], " (exact p = ",
             formatC(fisher_p, format = "g", digits = 2), ")"),
      paste0(decomp$fragility, " of ", tb["Procyclical", "Exogenous"],
             "; ", decomp$disagree_n, " already flagged by the pipeline")
    )
  ) |>
    tinytable::tt(width = c(0.52, 0.48)) |>
    tt_theme_report() |>
    tinytable::style_tt(j = 1:2, align = "l") |>
    tinytable::style_tt(i = 4, line = "b", line_width = 0.05)
}

#' Event-level concordance against the Vegh-Vuletin rate panel
#'
#' @param concordance Output of `compare_rate_paths()`.
#' @param detail If TRUE, one row per event; otherwise a status summary.
#' @return A tinytable, or NULL.
#' @export
rate_concordance_table <- function(concordance, detail = FALSE) {
  if (is.null(concordance) || nrow(concordance$events) == 0) return(NULL)
  ev <- concordance$events

  if (!detail) {
    out <- ev |>
      dplyr::count(Outcome = status, tax_type) |>
      tidyr::pivot_wider(names_from = tax_type, values_from = n,
                         values_fill = 0L)
    return(
      tinytable::tt(out) |>
        tt_theme_report() |>
        tinytable::style_tt(j = 1, align = "l")
    )
  }

  # Signed to make direction readable at a glance, but a genuine zero is "0",
  # not "+0" -- a restructure that leaves the top rate alone is not an increase.
  fmt <- function(x) {
    dplyr::case_when(
      is.na(x) ~ "—",
      x == 0   ~ "0",
      TRUE     ~ formatC(x, format = "f", digits = 0, flag = "+")
    )
  }

  ev |>
    dplyr::transmute(
      Tax = tax_type, Year = year, Outcome = status,
      Panel = fmt(delta_external),
      Ours  = fmt(delta_narrative),
      Note  = dplyr::coalesce(reason, "")
    ) |>
    tinytable::tt(width = c(0.08, 0.09, 0.24, 0.10, 0.10, 0.39)) |>
    tt_theme_report() |>
    tinytable::style_tt(j = c(1, 3, 6), align = "l")
}
