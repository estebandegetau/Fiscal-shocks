# External data sources

Reference inputs consumed by the pipeline that were not produced by it. Each
entry records what the file is, which columns we actually use, what we verified
about it, and what remains unconfirmed.

For the US narrative ground truth (`data/raw/us_shocks.csv`,
`data/raw/us_labels.csv`) see `docs/strategy.md` and the appendix of `index.qmd`.

---

## `data/raw/Full_sample_filtered.dta`

**Consumed by:** the `macro_panel_file` → `macro_panel` target pair in
`_targets.R`, cleaned by `clean_macro_panel()` in `R/procyclicality.R`. Feeds
`my_cycle`, `cross_country_cyclicality`, `procyclicality_events`,
`procyclicality_decomposition` and `rate_path_concordance`, which in turn
supply `index.qmd` §sec-usecase and §sec-rate-benchmark.

**Shape:** Stata `.dta`, 7,597 rows × 273 columns, 107 countries, 1960–2030.
One row per country-year. `ccode` is the ISO3 code, `country` the name.

### Provenance

The file was added to `data/raw/` on 2026-08-17. It is a compiled panel drawing
on several upstream sources; the blocks are distinguishable by naming
convention.

- **Statutory tax rates** — `corporate_tr`, `individual_tr`, `vat_tr`,
  `vat_tr_introduced`. **Confirmed by the author (2026-08-17) as the Végh and
  Vuletin (2015) hand-built statutory-rate panel**, cited in the manuscript as
  `@vegh_how_2015`. These are the columns the external benchmark in
  `index.qmd` §sec-rate-benchmark scores against, and the paper names the
  source. Note the columns carry no Stata variable labels, so this attribution
  rests on the author's confirmation rather than on anything in the file.
- **Macro aggregates** — **IMF WEO** conventions (`NGDP_R`, `NGDP_RPCH`,
  `NGDPD`, `GGX_NGDP`, `GGR_NGDP`, `GGXCNL_NGDP`, `PCPIPCH`, `LUR`, …).
- **Fiscal detail** — **IMF GFS** conventions (`i2_rev_tax`,
  `i2_tax_inc_prof_cp`, `i2_exps_subsidies`, `i2_exp_education`, …).
- **Development indicators** — **WDI**-derived (`*_wdi` suffixes).
- **Effective tax rates** — `Capital_tax_rate_bchs`, `Corporate_tax_rate_bchs`,
  `Labor_tax_rate_bchs`. The `_bchs` suffix indicates a separate source; not
  used by this project, so not chased down.

That the rate panel is Végh–Vuletin makes the benchmark tighter than a generic
external check would be: it is the same series whose procyclicality finding
`index.qmd` §sec-usecase takes as its starting point, so the validation and the
use case run against one another's data.

### Columns used

`clean_macro_panel()` keeps 19 of the 273 and discards the rest. Renamed to
project-side names:

| Project name | Source column | Use |
|---|---|---|
| `ccode`, `country`, `region`, `group`, `incomegroup`, `emde` | same | keys and grouping |
| `year` | `year` | annual index |
| `gdp_real` | `NGDP_R` | HP-filtered business cycle |
| `gdp_growth` | `NGDP_RPCH` | alternative cycle-state definition |
| `output_gap` | `NGAP_NPGDP` | unused for Malaysia (all NA) |
| `cit_rate`, `pit_rate`, `vat_rate` | `corporate_tr`, `individual_tr`, `vat_tr` | external statutory-rate benchmark (Végh–Vuletin) |
| `cut_cit_rate`, `cut_pit_rate` | `change_corporate_tr`, `change_individual_tr` | retained for inspection only — see below |
| `exp_gdp`, `rev_gdp`, `balance_gdp`, `prim_exp_gdp` | `GGX_NGDP`, `GGR_NGDP`, `GGXCNL_NGDP`, `prim_gov_exp_weo` | fiscal aggregates |

`d_cit_rate` / `d_pit_rate` are **computed by us** from the level series, not
read from the file. See the next section for why.

### Verified data-quality findings

These were checked directly against the file and are the reasons the cleaning
function does what it does.

1. **The `change_*` columns, as they appear in this file, are not first
   differences.** Across the panel over 1980–2023, *every* rate increase implied
   by the level series — 72 corporate and 94 personal — is recorded as `0` in
   `change_corporate_tr` / `change_individual_tr`. A further 21 corporate and 27
   personal decreases carry a magnitude that differs from the level difference.
   The columns behave as a cut-only measure. Using them as first differences
   would drop every rate hike, which biases any cyclicality statistic computed
   from them and would have scored two correctly-identified Malaysian
   personal-rate hikes (2016 +3pp, 2020 +2pp) as false positives in the
   concordance exhibit. They are kept as `cut_cit_rate` / `cut_pit_rate` so the
   discrepancy stays inspectable; nothing in the pipeline consumes them.

   **This is a statement about the derived columns in this compiled file, not
   about the Végh–Vuletin level series**, which is internally consistent and is
   what both the cyclicality statistic and the benchmark use. Whether the
   `change_*` columns are upstream or were constructed during compilation is
   not established, and it does not matter for our purposes since we recompute.
   It would matter for anyone else reaching for them.
2. **`NGAP_NPGDP` (output gap) is entirely missing for Malaysia**, which is why
   `build_country_cycle()` constructs an HP-filtered cycle rather than using the
   panel's own gap.
3. **`vat_tr` is entirely missing for Malaysia**, so the consumption-tax
   component of the deliverable — including the 2015 GST introduction and its
   2018 repeal, the two largest tax events in the inventory — has no external
   benchmark. §sec-rate-benchmark states this.
4. **2024–2030 are WEO forecasts.** `clean_macro_panel()` defaults `year_max` to
   2023 so that projections cannot enter a historical business cycle.
5. **Coverage for Malaysia** is 44 usable years, 1980–2023, for real GDP and
   both statutory rates; the fiscal aggregates start in 1990.
6. **Cross-country coverage** of the statutory-rate series is partial: 49
   countries have enough data for the cyclicality statistic, out of 107 in the
   file.

### Repository handling

`.gitignore` excludes `data/*`. Git cannot re-include a file whose parent
directory is excluded, so `data/raw/` is un-ignored and then re-ignored
file-by-file, with an explicit exception for this file. It is tracked (13.8 MB)
so the `format = "file"` target builds on a fresh clone, matching the existing
treatment of `us_shocks.csv`.
