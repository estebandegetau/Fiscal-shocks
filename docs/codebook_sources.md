# Codebook Sources: Implementation-Critical Details for Codebook Design

*Role: a **codebook-implementation reference** distilling R&R, Das et al., and H&K into design decisions for the C1-C4 codebooks. This is **not** the project's literature review — for that see `docs/lit_review_plan.md` (coverage map), `docs/brainstorm.qmd` (positioning), and `docs/lit_review_workflow.md` (how sources flow into the paper).*

This document distills implementation-relevant details from the source papers into a practical reference for codebook development. It is organized as "what we need to know before writing each codebook," not as a traditional literature survey.

## Section 1: R&R Methodology — Implementation Details

**Source papers:**

- Romer and Romer (2010), "The Macroeconomic Effects of Tax Changes," *AER* 100(3): 763-801
- Romer and Romer (2009), "A Narrative Analysis of Postwar Tax Changes," companion paper (95 pp)

### 1.1 Source Hierarchy

R&R use contemporaneous primary documents from executive and legislative branches (companion paper, Section I.A, pp. 3-5):

**Executive sources (ranked by usefulness):**

1. **Economic Report of the President (ERP)**: Released each January; best source for motivation of major tax changes. Discusses motivation, revenue effects, and nature of changes in the previous calendar year.
2. **Treasury Annual Report**: Covers a fiscal year; useful for systematic account of all tax law changes and revenue estimates. Detailed reports stopped after 1981.
3. **Budget of the United States**: For a fiscal year, prepared ~January before the fiscal year begins. Contains information about tax actions roughly two calendar years earlier.
4. **Presidential speeches and statements**: State of the Union, Annual Budget Message, speeches announcing proposals, signing statements, nominating convention acceptance speeches. Rich sources of motivation.

**Legislative sources:**

5. **House Ways and Means Committee reports**: Typically include motivation and revenue estimates.
6. **Senate Finance Committee reports**: Used when House report covers a version very different from the final bill.
7. **Congressional Record**: Floor debate; used when reports don't cover fundamental amendments.
8. **Conference reports**: Final bill version; typically no motivation discussion, but detailed revenue estimates.
9. **Joint Committee on Internal Revenue Taxation** (post-1975: Joint Committee on Taxation): Summaries with timing and revenue details.
10. **Congressional Budget Office** (post-1974): Revenue estimates via Budget and Economic Outlook reports.

**Specialized sources (Social Security):**

11. **Social Security Bulletin**: One or two articles on any Social Security tax change; discusses both motivation and revenue effects.
12. **Annual Report of the Board of Trustees** of the Federal Old-Age and Survivors Insurance Trust Fund: Abbreviated version of Social Security Bulletin material.

**Key insight for codebook design**: ERP is best for motivation classification (C2); Conference reports and Joint Committee summaries are best for revenue estimates (C4). Multiple sources should agree on motivation for confident classification.

### 1.2 The "Significant Mention" Rule

From R&R companion paper, Section I.B (pp. 4-5) and main paper, Section II.B (pp. 768-769):

**Operationalization:**

- An action is "significant" if it receives more than incidental reference in the primary sources
- Measures referred to only in passing or discussed only in lists of all measures that affected revenues are excluded
- Even very small tax changes often receive detailed discussion, so this rule captures all economically meaningful actions

**Inclusion criteria:**

- All legislated changes that actually change tax liabilities from one quarter to the next
- Executive actions that substantially changed depreciation guidelines
- Changes in personal and corporate income taxes, payroll taxes, excise taxes, and investment incentives

**Exclusion criteria:**

- Laws that merely extend an existing tax (no change in liabilities)
- Executive actions that merely change withholding timing without changing total liabilities
- Renewals of excise taxes that are virtually automatic (minimal news value)
- Non-policy revenue changes (stock prices, inflation, income distribution effects on revenues)

**Total count**: R&R identify 50 significant federal tax actions in the postwar era (1945-2007). A few involve multiple measures (e.g., a legislated change and an executive action that are hard to disentangle). Many lead to changes in multiple quarters due to phased implementation.

### 1.3 Motivation Classification

From R&R companion paper, Section I.C (pp. 5-8) and main paper, Section II.C-E (pp. 769-774).

**Note on C2 codebook scope (2026-05-01).** The 4-class taxonomy below is **diagnostic context, not codebook content** under C2 v0.7.0. The C2b codebook outputs a binary exogenous flag plus a sign of effect on fiscal liabilities, following the proxy convention of Das et al. (2026, IMF WP/26/43); see Section 2 of this document for the full methodological treatment. The 4-class R&R categories remain the authoritative ground-truth source on `aligned_data` (used to derive `true_exogenous` and to group acts in error analysis), and the boundary cases below remain the conceptual basis for what counts as exogenous. They are no longer encoded as decision rules in the prompt because (a) iter 35 diagnosed a structural ceiling under any v0.5–v0.6.x rule density and (b) iter 36's evidence-shuffle leakage diagnostic showed the dense rules were overfit to F-cluster US edge cases (F–A median-stability gap = −0.333). See `docs/strategy.md` C2 Blueprint for the v0.7.0 design.

**The four categories (diagnostic context):**

| Category | Definition | Exogeneity | Key Evidence Phrases |
|----------|-----------|------------|---------------------|
| **Spending-driven** | Tax change motivated by a change in government spending | Endogenous | War financing, new social programs (Medicare), defense buildup, "pay for increased spending," "finance the defense effort" |
| **Countercyclical** | Tax change designed to return output growth to normal | Endogenous | "Stimulate economy," "check downward slide," "return growth to normal," responding to recession forecasts, unemployment predicted to rise |
| **Deficit-driven** | Tax increase to reduce an inherited budget deficit | Exogenous | "Inherited deficit," "past decisions," "prudent fiscal policy," "actuarial soundness," Social Security trust fund solvency |
| **Long-run** | Tax change aimed at raising long-run growth or other structural goals | Exogenous | "Fairness," "efficiency," "smaller government," "improved incentives," "long-run growth," "raise potential output" |

**Critical boundary cases:**

1. **Countercyclical vs. Long-run** (the most important distinction for our pipeline):
   - Key test: Is the goal to "return growth to normal" (countercyclical) or "raise growth above normal" (long-run)?
   - If unemployment is predicted to rise, growth is below normal, so action is countercyclical
   - If unemployment is predicted to fall or remain stable, growth is at or above normal, so action is long-run
   - If the action was proposed when the economy was growing normally but motivated by a desire for faster growth, it is long-run even if the economy weakened by the time of passage
   - R&R take policymakers' statements at face value regarding what they consider "normal growth"

2. **Spending-driven vs. Deficit-driven** (temporal boundary):
   - Tax increase to pay for a contemporaneous spending increase: spending-driven
   - Tax increase to pay for a past spending increase: deficit-driven if >1 year after the spending increase
   - Specific rule: "A tax increase to pay for a past spending increase is classified as spending-driven if it occurs within a year of the spending increase, and as deficit-driven if it occurs more than a year after" (companion paper, p. 7)
   - Six observations are reclassified from deficit-driven to spending-driven in the present-value series because the news of the tax change occurred simultaneously with the spending increase

3. **Mixed motivations** (uncommon but important):
   - Most acts have a single dominant motivation consistently cited across sources
   - When sources suggest conflicting motivations: use the most frequently cited motivation
   - When motivation changes over time during deliberations: use prevailing motivation at time of passage
   - When multiple motivations are genuinely present: apportion revenue effects among motivations
   - Example: EGTRRA 2001 — rebate component (retroactive to Jan 2001) classified as countercyclical; rate reductions effective 2002+ classified as long-run

4. **Offsetting exogenous changes**:
   - When policymakers cut taxes to counteract a previous exogenous tax increase because the economy is weakening, the offsetting cut is classified with the same motivation as the original change (not as countercyclical)
   - Rationale: Avoids identifying two tax changes of different motivations in a quarter when liabilities did not actually change

### 1.4 Revenue Estimation

From R&R companion paper, Section I.D (pp. 7-10) and main paper, Section II.D (pp. 771-772):

**Measure**: Impact when implemented on current tax liabilities at prevailing GDP level. This is consistent with evidence that consumers respond to changes in current disposable income.

**Source priority (fallback hierarchy for C4):**

1. Expected revenue effect at implementation quarter from ERP (preferred; especially good in 1960s-1970s)
2. First full calendar year estimate (from Conference reports, Joint Committee summaries)
3. First full fiscal year estimate
4. Conference report or Joint Committee estimates for any available period

**Key conventions:**

- All revenue estimates expressed at **annual rate**
- Use **expected** (real-time) revenue effects, not retrospective figures
- Whenever possible, derive a **consensus estimate from multiple sources**
- If projected revenue effects increase over time due to economic growth (not further law changes), exclude the growth-driven portion
- Policymakers focus on effects at a given level of income, which is what we want

**Present-value alternative series:**

- Discounts all future tax changes in a bill back to the quarter of passage
- Uses the three-year Treasury bond rate for discounting
- Assigns the full present value to the passage quarter (rather than spreading across implementation quarters)
- Six deficit-driven observations reclassified as spending-driven in this series (because news of the tax change was contemporaneous with the spending increase)

### 1.5 Timing Rules

From R&R companion paper, Section I.D (pp. 7-10) and main paper, Section II.D (pp. 771-772):

**Assignment rule**: Date to the quarter in which tax liabilities actually changed, NOT the date of legislation.

**Midpoint rule**: If a tax change takes effect before the midpoint of a quarter, assign it to that quarter. If after the midpoint, assign it to the next quarter.

**Phased changes**: If a law implements changes in steps, record each step as a separate revenue effect in its respective implementation quarter.

**Retroactive components (two series):**

1. **Standard series** (excludes retroactive): Simply ignores retroactive features for cleaner analysis
2. **Adjusted series** (includes retroactive): Treats retroactive component as a one-time levy or rebate in the quarter to which the bill is assigned

**Retroactive calculation example** (Excess Profits Tax Act of 1950):

- Tax imposed retroactive to July 1950, signed January 1951
- Ongoing effect: $3.5B annual rate starting 1951Q1
- Retroactive component: covers 2 quarters (July 1950 to Dec 1950), so one-time levy = 2 × ($3.5B / 4) = $1.75B per quarter, or $7B at annual rate
- Combined 1951Q1: $3.5B + $7B = $10.5B (annual rate)
- 1951Q2: $3.5B (annual rate), with a change of -$7B from Q1

### 1.6 Act-by-Act Reference Index

The companion paper (pp. 16-95) contains detailed documentation for each of the 50 acts. Each entry follows a consistent template:

**Template structure:**

- Act name and date signed
- Change in liabilities: quarter, amount (billions), motivation category for each implementation quarter
- Present value: quarter, amount, motivation category
- Narrative: 1-3 pages of analysis with quotations from primary sources
- Nature and permanence: brief characterization of the type of tax change

**Page index for key acts** (companion paper line numbers in extracted text):

| Act | Lines |
|-----|-------|
| Revenue Act of 1945 | ~3889 |
| Social Security Amendments of 1947 | ~3979 |
| Revenue Act of 1948 | ~4009 |
| Social Security Amendments of 1950 | ~4096 |
| Revenue Act of 1950 | ~4162 |
| Excess Profits Tax Act of 1950 | ~4227 |
| Revenue Act of 1951 | ~4276 |
| Expiration of Excess Profits Tax | ~4325 |
| Excise Tax Reduction Act of 1954 | ~4400 |
| Internal Revenue Code of 1954 | ~4460 |
| Social Security Amendments of 1954 | ~4550 |
| Federal-Aid Highway Act of 1956 | ~4586 |
| Social Security Amendments of 1956 | ~4641 |
| Tax Rate Extension Act of 1958 | ~4659 |
| Social Security Amendments of 1958 | ~4723 |
| Federal-Aid Highway Act of 1959 | ~4765 |
| Social Security Amendments of 1961 | ~4827 |
| Depreciation Guidelines / Revenue Act of 1962 | ~4862 |
| Revenue Act of 1964 | ~4943 |

Acts from 1965 onward follow sequentially. Use `grep` on `docs/articles/Romer and Romer - A NARRATIVE ANALYSIS OF POSTWAR TAX CHANGES.pdf` (extracted to text) for specific act lookups.

## Section 2: Das et al. (2026) — LLM-Based Narrative Identification at Scale

**Source paper**: Das, Furceri, Patel, and Peralta-Alva (2026), "AI Meets Fiscal Policy: Mapping Government Spending Actions Across 64 Countries," IMF Working Paper WP/26/43 (89 pp)

This paper is the methodological precedent closest to ours: it is the first study to operationalize the Romer & Romer narrative method at scale using an off-the-shelf LLM, producing a quarterly cross-country dataset of exogenous *spending* shocks for 64 countries from 1952Q1 to 2023Q4. It governs three concrete design choices in our C2 codebook (v0.7.0): the binary exogenous flag plus sign-of-effect output schema; the "critical clarifier" prompt language; and the conservative aggregation rule for mixed-action passages.

### 2.1 Methodological Framework: Romer & Romer (2023)'s Four Requirements

Das et al. organize their construction around the four "requirements" Romer & Romer (2023) lay out for any narrative-identification exercise. These are useful as a checklist for our project as well:

1. **A reliable narrative source** (Section 2.2 below)
2. **A clear idea of the information sought in the source** (Section 2.3)
3. **A dispassionate and consistent approach to the source** (Section 2.4 — the LLM prompt)
4. **Careful documentation of the narrative evidence** (verbatim excerpts retained alongside coded series)

Our project inherits this framing: ERP/Budget/Treasury reports are our "reliable source"; the C1-C4 codebooks operationalize "the information sought"; the fixed YAML prompt + temperature settings provide "a dispassionate and consistent approach"; and the chunk-level evidence excerpts retained in pipeline outputs satisfy the documentation requirement.

### 2.2 Source Selection

**Primary source**: Economist Intelligence Unit (EIU) Country Reports.

**Why EIU over alternatives:**

- Standardized, centralized editorial workflow (country analyst draft → specialist review → published) promotes comparability across countries and time
- Quarterly frequency for a broad cross-section (later monthly for some countries), with coverage extending back to the 1950s for many countries
- Reports describe fiscal measures *and* the motivations emphasized at the time, which makes them well suited for narrative identification
- Higher-frequency and longer historical coverage than OECD or IMF country reports

**Quarterly aggregation rule**: One report per country–quarter (March/June/September/December calendar). When multiple reports exist within a quarter (e.g., 2000–2007 short "Updaters" + longer "Main Reports"), retain the chronologically last comprehensive "Main Report" — overlapping coverage provides limited incremental information on fiscal policy actions.

**Coverage**: 64 advanced and developing economies (subset of EIU's ~140-country archive selected by macro-data availability), 16,029 country-quarter observations, 8,636 nonzero (53.9%) — 50.6% expansions / 49.4% contractions. Low-income countries account for 22.2% of nonzero quarters.

### 2.3 Information Sought: Two-Condition Exogeneity Test

Das et al. (Section 2.2) operationalize R&R's exogeneity criterion as a **conjunction of two conditions** that must simultaneously hold for an action to count as exogenous:

1. The stated motive is unrelated to near-term macroeconomic conditions; AND
2. The narrative does *not* cite contemporaneous growth, inflation, unemployment, interest-rate movements, exchange-rate pressure, or financing stress as the rationale.

Failing either condition → action is endogenous and excluded from the exogenous series.

**Two non-cyclical motive families** (per R&R 2010): (i) measures addressing inherited fiscal imbalances; (ii) measures reflecting long-run objectives for size/composition of the public sector (growth, fairness, institutional design). These are the only motivations Das et al. retain as exogenous — collapsing R&R's 4-category taxonomy to a binary flag.

**Critical clarifier** (verbatim, p. 9): *"Acknowledging current conditions does not by itself imply endogeneity if the stated motive is explicitly non-cyclical."*

This clarifier is load-bearing because it corrects a natural LLM failure mode: passages where text describes both current conditions *and* a non-cyclical motive often get misclassified as endogenous on the basis of the cyclical context alone. Our C2b v0.7.0 codebook adopts this clarifier verbatim.

### 2.4 The Fixed Prompt Specification

Das et al. use a single fixed GPT-4.1 prompt held invariant across all 64 countries and ~16,000 country-quarters. **No fine-tuning, no in-context examples, no task-specific training, no sample-specific tailoring.** The fixed-prompt design serves three purposes: (a) prevents look-ahead bias and overfitting to particular country contexts; (b) enables replication by other researchers; (c) ensures the coding rubric is identical across the panel.

**Prompt structure** (paraphrased from pp. 9-10):

- **Task**: "Read the EIU country report excerpt for country C and quarter Q. Identify exogenous government spending actions in Q based on the stated motivations in the text, and summarize their net directional impact on spending."
- **Definition of exogenous action**: enumerates the two-condition test above plus the critical clarifier
- **Outputs**: structured 5-field schema (see below)
- **Notes**: "Base the classification strictly on the provided text; do not infer unstated motives. If net direction is not supported by the text, return NEUTRAL or UNCLEAR."

**Output schema (5 fields):**

| Field | Type | Notes |
|-------|------|-------|
| `EXOG_NET_SPENDING` | {EXP_, CON_, NEUTRAL, UNCLEAR} | Optional small/large suffix when intensity cue present |
| `MOTIVATION` | free text | Brief phrase citing the stated motive(s) |
| `COMPONENT` | free text (optional) | Spending component(s) referenced |
| `INTENSITY_ORDINAL` | integer in [-10, +10] (optional) | Directional intensity |
| `CONFIDENCE` | self-assessment (optional) | Brief classification confidence |

**Note on announcement vs. implementation**: The prompt records whether identified measures are implemented in the current quarter or announced for future quarters, but the baseline shock series does *not* perform an announcement/implementation split at the classification stage. They explicitly defer this to future work, treating the indicator as "a qualitative proxy for discretionary spending actions as recorded in real time, which may reflect a mixture of announcement and implementation elements."

### 2.5 Construction of the Quarterly Shock Series

Report-level outputs are aggregated into a country–quarter proxy:

```
z_{i,t} ∈ {-1, 0, +1}
       = +1 if EXOG_NET_SPENDING = EXP_
       = -1 if EXOG_NET_SPENDING = CON_
       =  0 if EXOG_NET_SPENDING ∈ {NEUTRAL, UNCLEAR}
```

**Conservative aggregation**: Whenever the stated motive is not explicitly non-cyclical — or the report links the action to contemporaneous macro conditions — the prompt classifies the action as non-exogenous and it does not contribute to the net effect. This conservative rule matters for mixed-action passages where multiple measures with different signs co-occur: the model extracts each individually, but the net stance is conservatively coded NEUTRAL when relative magnitudes are not explicitly stated.

**Use in econometrics**: `z_{i,t}` is used as an *internal instrument* for innovations to realized government spending in country-by-country Bayesian VARs (following Plagborg-Møller and Wolf 2021; Li et al. 2024). Because the contemporaneous response of measured G pins the scale of the structural innovation, the qualitative nature of the proxy (no magnitude information) is non-critical for identification.

### 2.6 Validation Strategy — Four Complementary Exercises

This is the most important section for our purposes: Das et al. design four orthogonal validation exercises, each testing a different aspect of the AI-narrative pipeline.

**Validation 1: Benchmark against expert human coding (Romer & Romer 2019, "RR19")**

- RR19 examined 200 EIU reports across 19 OECD countries (1980-2017) using expert coders to classify fiscal stance + motivations during financial-distress episodes
- Das et al. apply a *separate*, RR19-mirroring fixed prompt to the same 200 reports and compare cell-by-cell
- **Expansions**: stance match 14/16 (87.5%); motivation match 32/34 (94.1%)
- **Contractions**: stance match 18/19 (95%); motivation match 44/45 (97.8%)
- Footnote 3 (p. 21) discloses that 4 boundary cases (Finland 1993Q1, Sweden 1993Q2, Greece 2009M7, Ireland 2009M7) are excluded from the baseline because RR19 codes them as net expansions on the basis of large financial-rescue measures while EIU describes concurrent contraction; including them lowers the stance match to 14/20 (70%). The authors interpret this as a difference in aggregation rule, not interpretation failure.
- The *headline* "exceeds 93% accuracy" claim aggregates stance + motivation matches across both panels.

**Critical methodological insight**: They distinguish stance disagreement from motivation disagreement and score them independently — a report can show a stance disagreement (because the conservative aggregation rule yields a different net direction) but still match motivation. This separation is directly analogous to the {exogenous, sign} decomposition our C2b v0.7.0 outputs.

**Validation 2: Replicability across reruns**

- Re-ran the prompt **51 times** on a subset of 20 reports under identical fixed prompt
- For each (report, field), they compute the **modal share** = fraction of runs in which the most frequent value was returned (1 = perfect replicability)
- ECDFs of modal shares across the 20 reports show:
  - **Direction**: perfectly stable (modal share = 1 for all 20 reports — every run assigned the same sign)
  - **Motivation**: high but not perfect (multi-category construct with multiple plausible motives)
  - **Confidence and Intensity**: lower replicability (finer quantitative judgments more sensitive to phrasing)
- Interpretation: coarse binary classifications are robust; fine-grained ordinal/quantitative outputs are more sensitive to sampling.

This methodology is directly relevant to our pipeline's evidence-shuffle / order-invariance diagnostics (Test IV in H&K) and to the multi-run consistency checks our self-consistency sampling already performs.

**Validation 3: AI shocks predict realized government spending**

Local-projection regression of log G on shock indicators, country and time FEs, 4 lags of G, Y, and the shock:

- At impact, contractions (z = -1) reduce log G by ~-0.005 (0.5% level); expansions (z = +1) raise log G by ~+0.002 one quarter later
- Cumulatively at h = 8: contractions reach ~-0.06, expansions reach ~+0.04
- Confirms the narrative shocks have economic content beyond noise

**Validation 4: External alignment with Adler et al. (2024)**

Adler et al. (2024) provide an annual *quantitative* dataset of action-based fiscal consolidation packages (size in % of GDP) for 31 countries since 1978. Das et al. show:

- **Extensive margin**: Of 138 country-years that Adler codes as ≥0.5% GDP spending consolidation, 96.4% have at least one consolidation quarter in Das et al.'s database; 100% match for ≥2.0% GDP packages
- **Probability model**: Conditional on country FE, observing a consolidation quarter is associated with a 12.6 pp higher probability of being in Adler's "sizable consolidation" set
- **Intensity alignment**: The annual net stance index (consol_quarters − expand_quarters)/4 has a coefficient of 0.263 (s.e. 0.044) when regressed on Adler's spend size — moving from purely expansionary year to purely consolidation year corresponds to ~0.5 pp of GDP additional consolidation in Adler's dataset

### 2.7 Predictability / Orthogonality Check

A complementary validation: are the shocks orthogonal to lagged macro conditions? This addresses the Jordà–Taylor (2015) critique that earlier narrative-shock series (Guajardo et al. 2014) were forecastable from standard macro indicators.

Panel regression of `z_{i,t}` on lagged debt/GDP, output gap, GDP growth, and `z_{i,t-1}` with country FE:

- Across all three samples (full / Guajardo subset / Adler subset), only the lagged shock is significant; macro lags are insignificant
- R² ≤ 0.10 — limited explanatory power
- *When aggregated to annual frequency*, predictability emerges (R² up to 0.31 for Adler shocks, with significant lagged GDP growth)
- Interpretation: quarterly frequency is itself an exogeneity-protective design choice; annual aggregation contaminates with predictable within-year cyclical responses.

**Implication for our pipeline**: We work at sub-quarterly chunk granularity and aggregate to act-level, but the same logic suggests a predictability/orthogonality check on our final shock series should be part of Phase 1 validation.

### 2.8 Stylized Facts on the Resulting Database

- 8,636 nonzero quarters across 64 countries; 50.6% expansions / 49.4% contractions
- LICs disproportionately represented (22.2% of nonzero quarters) — narrative coverage that did not previously exist for this group
- **Asymmetry by country group**:
  - Advanced: 45.8% expansion share (more contractions, possibly reflecting fiscal rules)
  - Emerging: 49.5% expansion share (near-balanced)
  - LIC: 60.7% expansion share (majority expansionary)
- **Asymmetry by motive type** (text-dictionary classification of a random subsample):
  - Expansions: ~60% are public investment / infrastructure / capital projects
  - Contractions: >2/3 are explicit consolidation / deficit-reduction measures
  - Suggests fiscal expansions and consolidations are *not* mirror images of each other

### 2.9 Adaptations and Inheritance for Our Project

**What our C2 codebook v0.7.0 inherits directly:**

| Das et al. design choice | C2b v0.7.0 adoption |
|---------------------------|---------------------|
| Binary exogenous flag (collapsing R&R's 4 motive classes) | Yes — primary output is `exogenous ∈ {true, false}` |
| Sign of net effect on spending: {-1, 0, +1} | Adapted to `sign ∈ {increase, decrease, no_change}` for fiscal liabilities |
| Critical clarifier ("Acknowledging current conditions...") | Yes — verbatim in C2b prompt |
| Conservative aggregation: NEUTRAL/UNCLEAR → 0 | Yes — when sign is ambiguous or evidence is mixed, return `unclear` rather than guess |
| Fixed prompt across all examples (no per-act tailoring) | Yes — reinforced by iter 36 leakage diagnostic showing v0.6.x rules were overfit |
| No in-context few-shot examples in production prompt | Yes — v0.7.0 removes the dense decision rules and class definitions |
| Explicit confidence field as auxiliary diagnostic | Yes — `confidence` retained in C2b output schema |

**What is genuinely different about our setting:**

| Dimension | Das et al. | Our project |
|-----------|------------|-------------|
| Source | EIU Country Reports (curated, analyst-edited, summary-style) | ERP / Budget / Treasury reports (official, primary, longer, more legalistic) |
| Unit of analysis | One report per country–quarter (~3-15 pages) | Sub-document chunks pre-filtered by C1 (typically 1-3 paragraphs) |
| Granularity of measure | Net stance per country–quarter | Per-act, with C3/C4 separating implementation quarters |
| Ground truth | RR19 (200 reports, 19 countries) — non-public expert codings | R&R (2010) + companion paper — 50 acts US-only, public, fully documented |
| LLM | GPT-4.1 (closed-weight, OpenAI) | Claude (closed-weight, Anthropic) — currently Haiku for cost; Sonnet for headline runs |
| Scope of fiscal action | Spending only | Tax/revenue (R&R 2010 corpus) — mirrors Romer & Romer (2010), not (2019) |
| Validation against quantitative external dataset | Adler et al. (2024) annual consolidation sizes | `us_shocks.csv` (R&R 2010 series, quarterly, US-only) — Phase 1 validation target |

**Methodology gaps we still need to fill** (Phase 1 / Phase 2 work):

- A predictability/orthogonality check on our final aggregated shock series (R² of `z_{i,t}` on lagged macro controls)
- A multi-run replicability ECDF on a held-out subset (analogous to Das et al.'s 51-rerun exercise)
- An external alignment exercise once Phase 2 (Malaysia) data exists — likely against IMF Article IV report-based codings or the Adler et al. (2024) panel where overlap exists

## Section 3: H&K Framework — Implementation Specifications

**Source paper**: Halterman and Keith (2025), "Codebook LLMs: Evaluating LLMs as Measurement Tools for Political Science Concepts," arXiv:2407.10747v2 (53 pp)

### 3.1 Codebook Format Specification

From H&K Section 5, Figure 1 (pp. 7-9):

The semi-structured format consists of:

```
Instructions: [overall task description, role, valid label reminder]
Classes:
  Label: [exact string to return — UPPER_CASE recommended]
  Definition: [single sentence, succinct]
  Clarification: [inclusion criteria, can be multi-item]
  Negative Clarification: [exclusion criteria, addresses confusion cases]
  Positive Example: [document text + explanation of why it fits]
  Negative Example: [document text + explanation of why it does not fit]
  ...repeat for each class...
Document: [text to classify]
Output reminder: [enumerate valid labels, specify format]
```

**Key empirical finding**: Semi-structured format outperforms original codebook format across datasets (Table 3: +0.02 to +0.13 weighted F1). The improvement comes from explicit separation of components enabling the LLM to attend to each part.

**Format design principles:**

- Separating components enables ablation testing (removing one component at a time)
- Each component serves a distinct purpose: definition for core meaning, clarification for boundary cases, examples for in-context learning
- Output reminder is critical for ensuring legal label output

### 3.2 Behavioral Tests I-IV (Label-Free)

From H&K Section 6, Table 2, Figure 3 (pp. 10-13):

| Test | What It Measures | Implementation | Pass Criteria |
|------|-----------------|----------------|---------------|
| **I: Legal Labels** | LLM returns only valid labels | Run on N documents, check if output matches valid label set | 100% valid labels |
| **II: Definition Recovery** | LLM can match definition to label | Provide verbatim class definition as "document," check if correct label returned | 100% correct |
| **III: In-Context Examples** | LLM can match examples to labels | Provide verbatim positive/negative examples as "documents" | 100% correct |
| **IV: Order Invariance** | Labels unchanged by category order | Run with original, reversed, and shuffled codebook order; measure consistency | Fleiss's kappa > 0.8 (near-perfect); <5% label changes |

**Implementation details for Test IV:**

- Create three versions of the codebook: original order, reversed order, randomly shuffled
- Run all N documents through each version
- Calculate: (a) percentage of labels that remain the same between original and each variant; (b) Fleiss's kappa across all three versions
- Use Landis & Koch (1977) interpretation: <0.20 poor, 0.21-0.40 fair, 0.41-0.60 moderate, 0.61-0.80 substantial, 0.81-1.00 near-perfect

**H&K empirical findings:**

- Mistral-7B, Llama-8B performed well on Tests I-III (near 100%)
- All models showed sensitivity to category order (Test IV), suggesting attention issues with long prompts
- OLMo-7B performed so poorly it was dropped from later stages
- Test IV is the most informative label-free test for our use case, since our codebooks will have semantically loaded category names

### 3.3 Behavioral Tests V-VII (Labels-Required)

From H&K Section 8.1, Table 2, Figure 4 (pp. 14-16):

| Test | What It Measures | Implementation |
|------|-----------------|----------------|
| **V: Exclusion Criteria** | LLM follows specific exclusion rules | Add trigger word ("elephant") to document + exclusion criterion to codebook; test all 4 combinations: (normal/modified doc) × (normal/modified codebook). LLM must respond correctly to all 4 to pass. |
| **VI: Generic Label Accuracy** | LLM doesn't rely on label names | Replace all labels with non-informative names (LABEL_1, LABEL_2, etc.); measure F1 on labeled dataset |
| **VII: Swapped Label Accuracy** | LLM follows definitions over names | Permute labels across definitions (each label paired with wrong definition); measure F1 on labeled dataset |

**Test V detail** (from H&K footnote 2, p. 15):

The four test conditions are:
1. Normal codebook + normal document → should classify correctly
2. Normal codebook + modified document (contains "elephant") → should classify correctly (no exclusion rule exists)
3. Modified codebook (has elephant exclusion) + normal document → should classify correctly (trigger not present)
4. Modified codebook + modified document → should apply exclusion rule

An LLM passes only if all four conditions are handled correctly for each example.

**Critical H&K finding for our project:**

Tests VI and VII show that LLMs rely heavily on label names rather than definitions. When labels are replaced with generic terms (LABEL_1, etc.), F1 drops significantly. When labels are swapped across definitions, models follow the label name rather than the definition.

**Implication for C2 (Motivation)**: Our category names are semantically loaded ("deficit-driven," "countercyclical"). The model may classify a passage as "deficit-driven" simply because it mentions the word "deficit," even if the R&R operationalization says otherwise. Tests VI and VII will reveal whether this is happening.

### 3.4 Ablation Methodology

From H&K Section 8.2, Table 4 (pp. 16-17):

**Procedure**: Systematically remove codebook components one at a time, measure impact on weighted F1.

**Components to ablate** (from Table 4, tested on BFRS with Mistral-7B):

| Ablated Component | Dev F1 | Change from Full |
|-------------------|--------|-----------------|
| None (full codebook) | 0.53 | baseline |
| Negative Example | 0.42 | -0.11 |
| Positive Example | 0.46 | -0.07 |
| Negative Clarification | 0.43 | -0.10 |
| Clarification + Neg. Clarification + Examples | 0.20 | -0.33 |
| Definition (labels only) | 0.29 | -0.24 |

**Key findings:**

- All components contribute to performance; removing any single component decreases F1
- Removing negative examples had the largest single-component impact (-0.11)
- Surprisingly, removing the definition (leaving only labels) yielded F1 = 0.29, suggesting the model derives some accuracy purely from label names
- The full codebook with all components yielded the best performance, but the margin was not always large

**Our ablation plan for each codebook:**

1. Remove clarifications only
2. Remove negative clarifications only
3. Remove positive examples only
4. Remove negative examples only
5. Remove output reminder only
6. Remove definition (labels only)
7. Remove all examples + clarifications (definition + label only)

### 3.5 Manual Error Analysis

From H&K Section 8.3, Table 5 (pp. 17-18):

**Six error categories for classifying model outputs:**

| Category | Description | Action |
|----------|------------|--------|
| A. LLM correct | LLM prediction matches gold standard | No action |
| B. Incorrect gold standard | Human label was wrong | Review and potentially correct gold label |
| C. Document error | Scraping artifact, missing context, truncation | Fix document processing |
| D. LLM non-compliance | Invalid output (wrong format, hallucinated label, multiple labels) | Improve output instructions |
| E. LLM semantics/reasoning | LLM applied wrong definition or used heuristic | Improve codebook clarifications |
| F. Other | Uncategorizable | Case-by-case analysis |

**H&K findings on error patterns:**

- Non-compliance rates varied dramatically: 0% (BFRS) to 45% (Manifestos)
- Evidence of **lexical overlap heuristics**: models select labels whose words appear in the text, even when incorrect. Example: word "rally" in text leads to prediction of "rally" label even when the codebook definition of "demonstration" fits better.
- Evidence of **background concept reliance**: model predicts based on pretraining knowledge rather than codebook operationalization. Example: education funding passage labeled "WELFARE POSITIVE" despite codebook explicitly stating "This category excludes education."

**Implications for our project:**

- Category E errors (semantics/reasoning) are most critical for C2 Motivation. A passage mentioning "deficit" might trigger "DEFICIT_DRIVEN" even when the R&R operationalization says it's "SPENDING_DRIVEN" (because the tax increase pays for contemporaneous spending).
- Category B errors (incorrect gold standard) are possible since our 44-act dataset derives from R&R's own judgments, which may have borderline cases.
- Category D errors (non-compliance) should be minimal with Claude, which generally follows format instructions well.

### 3.6 Evaluation Metrics

From H&K Section 7 (pp. 11-14):

**Primary metric**: Weighted F1 score

- Weighted average of per-class F1 scores, weighted by sample size
- Accounts for class imbalance
- Implementation: `sklearn.metrics.f1_score(y_true, y_pred, average='weighted')` or R equivalent via `yardstick`

**Bootstrap confidence intervals:**

- 500 resamples of (predicted, true) pairs
- 95% confidence intervals
- Report as: `0.57 [0.55-0.58]`

**Inter-coder agreement** (for Test IV order sensitivity):

- Fleiss's kappa across original, reversed, and shuffled codebook predictions
- Landis & Koch interpretation scale
- Implementation via R `irr` package

**Per-class metrics:**

- F1, precision, recall per category
- Confusion matrix for detailed error patterns
- Particularly important for our project: exogenous precision (C2) and recall (C1)

**Adaptations for our project:**

- LOOCV instead of train/test split (44 acts is too small for reliable splitting)
- Cohen's kappa for pairwise agreement (2 coders: LLM vs. R&R ground truth)
- Bootstrap with 500-1000 resamples for all primary metrics

### 3.7 Key Adaptations for Our Project

H&K used open-weight 7-12B parameter models (Mistral-7B, Llama-8B). Our project uses Claude (closed-weight, much larger). Key implications:

**Advantages:**

- Likely much better zero-shot performance (Claude significantly outperforms 7-12B models on instruction following)
- Better long-context handling (200K token context vs. 4K-128K for H&K models)
- Lower non-compliance rates expected (Claude follows format instructions reliably)
- S4 fine-tuning even less likely to be needed

**Constraints:**

- Cannot do parameter-efficient fine-tuning (LoRA/QLoRA) on Claude; API-only access
- Must rely on prompt engineering (S0 codebook quality) rather than weight updates
- If S4 is needed, would require fine-tuning an open-weight model, losing Claude's advantages

**Dataset size differences:**

- H&K: 4,000-20,000 training examples per dataset
- Our project: 44 labeled acts total
- Consequence: LOOCV is the appropriate evaluation strategy (each act serves as test once)
- Bootstrap CIs will be wider due to small N

**Model behavior differences to test:**

- Does Claude follow codebook definitions over background knowledge? (Tests VI/VII will reveal)
- Is Claude more robust to label name reliance? (Larger models may attend better to instructions)
- Does self-consistency sampling (already implemented) compensate for any label sensitivity?

### 3.8 Memorization mechanics for the S1 memorization test (Carlini et al. 2022)

*Added 2026-06-24 (lit intake, `read-deep`). The mechanistic backing for our S1 memorization test — the threat that the model "recognizes" a US fiscal act from pretraining rather than reading the supplied chunk. H&K's Tests I–VII (§3.2–3.3) do not address this; Carlini supplies both the risk model and the control design.*

Carlini et al. measure verbatim memorization by prompting a model with true training-set prefixes and checking exact-suffix reproduction under greedy decoding. Three robust, log-linear laws:

1. **Model size.** Extractable memorization rises ≈+19 pp per 10× parameters (2–5× across a model family). *Implication:* the recall threat **increases** as we move to larger Sonnet/Opus-class deployment models, so S1 cannot be a one-time check — re-run it whenever the deployment model changes.
2. **Duplication.** Sequences repeated more often in training are far more extractable. *Implication:* the published 44-act R&R list and canonical fiscal-act descriptions are widely re-quoted online (plausibly high-duplication), exactly the regime where memorization is strongest — and we cannot inspect the proprietary pretraining corpus, so we must assume the US reference set *may* be memorized and test behaviorally rather than rely on absence-of-contamination claims.
3. **Prompt context length ("discoverability").** Memorized strings stay hidden until prompted with enough context (33%→65% extractable from 50→450 tokens). *Implication:* long, verbatim chunks carrying the act name, public-law number, and year are the **highest-risk** prompts for triggering recall over reading.

**The control design is the test design.** Carlini's identification strategy — prompt a model on data it could *not* have memorized (GPT-2 on The Pile) and compare against one that could (GPT-Neo) — is the template for S1:

- **Perturbation probe.** Re-classify the chunk with the identifying surface forms (act name, P.L. number, year) redacted or paraphrased, holding the substantive rationale fixed. If the label survives *only* when identifiers are present, that is recall, not reading.
- **Trivial-baseline guard.** Some correct outputs come from generic competence, not memorization (GPT-2 "hit" ~6% on boilerplate/number runs). The S1 pass bar must distinguish "got it from the text" from "any model would guess this."
- **Regime match.** Carlini measures verbatim recall under greedy decoding (temp = 0) — the same deterministic regime we deploy — so the recall threat applies at our operating point, not only under sampling.

This complements the contamination-detection angle in §5.2 (Asirvatham's staggered-cutoff test, which is infeasible for our 1945–2022 US corpus): Carlini gives the *mechanism* and the behavioral control, while staggered cutoffs would give a *detection* protocol we cannot run.

## Section 4: Cross-Paper Synthesis — Codebook Design Decisions

### 4.1 Mapping R&R Steps to Codebooks

| Codebook | R&R Step | Input | Output | Key R&R Concepts to Operationalize |
|----------|----------|-------|--------|-----------------------------------|
| **C1: Measure ID** | RR2 (Identifying measures) | Document passage | Binary (fiscal measure or not) + extracted text | "Significant mention" rule; actual liability change requirement; exclusion of extensions, withholding-only changes, automatic renewals |
| **C2: Motivation** | RR5 (Motivation classification) | Identified measure passage | 4-class motivation + exogenous flag | All 4 categories with boundary rules; spending-driven vs. deficit-driven temporal boundary; countercyclical vs. long-run "return to normal" test; mixed motivation apportionment; source agreement weighting |
| **C3: Timing** | RR4 (Timing assignment) | Identified measure passage | List of (quarter, amount) tuples | Midpoint rule; phased changes as separate entries; retroactive handling (standard vs. adjusted); implementation date vs. passage date |
| **C4: Magnitude** | RR3 (Revenue estimation) | Identified measure passage | Revenue effect in domestic currency, billions | Fallback hierarchy (ERP > calendar year > fiscal year > Conference report); annual rate convention; exclude growth-driven revenue increases; present-value alternative |

### 4.2 Country-Agnostic Language Mapping

For each R&R concept, what needs to be generalized for cross-country transfer:

| R&R US-Specific Concept | Country-Agnostic Equivalent | Notes |
|--------------------------|---------------------------|-------|
| "Tax liabilities" | "Fiscal liabilities or obligations" | Broader to include non-tax fiscal measures |
| "Ways and Means Committee" | "Relevant legislative committee" | Country-specific committees vary |
| "Economic Report of the President" | "Official economic outlook documents" | May be central bank reports, ministry white papers, budget speeches |
| "Congressional Record" | "Legislative debate records" | Hansard in Commonwealth, Diario Oficial in Latin America |
| "Revenue in billions USD" | "Revenue in domestic currency, billions" | Magnitude should be in local currency |
| "GDP normalization" | Same (universal concept) | No change needed |
| "Quarter assignment" | Same (calendar quarters) | Universal, though fiscal years differ |
| "Social Security trust fund" | "Social insurance/pension fund" | Specific program names vary |
| "Excise taxes" | "Indirect taxes / consumption taxes" | Terminology varies (VAT, GST, excise) |
| "Executive actions" | "Executive/administrative orders" | Presidential decrees, ministerial orders |

### 4.3 Anticipated LLM Challenges

Based on H&K error analysis findings and our knowledge of the R&R domain:

**1. Label name reliance (Tests VI/VII)**

"Deficit-driven" and "countercyclical" are semantically loaded labels. A model may classify a passage as "deficit-driven" whenever it encounters the word "deficit," even when the R&R operationalization says the change is actually "spending-driven" (because the deficit resulted from a recent spending increase, making the tax change within the 1-year spending-driven window).

*Mitigation*: Strong negative clarifications in C2 codebook; test with generic labels; consider using less semantically loaded labels (e.g., CATEGORY_A vs DEFICIT_DRIVEN) as a robustness check.

**2. Lexical overlap heuristics**

Passages mentioning "stimulate growth" might be classified as "long-run" even when the full context makes clear the goal is to return growth to normal (countercyclical). The key phrases "stimulate" and "growth" overlap with the long-run label.

*Mitigation*: Negative examples in C2 must include near-miss passages with overlapping vocabulary; clarifications must emphasize the "return to normal vs. raise above normal" distinction.

**3. Long-context attention**

Full codebook + long passage + examples may challenge effective attention, especially for C2 where four class definitions with multiple clarifications and examples could exceed several thousand tokens.

*Mitigation*: Claude handles 200K tokens, so context length is less of a concern than for H&K's 7B models. However, codebook conciseness is still important for attention quality.

**4. Mixed motivations**

R&R's apportionment logic for mixed-motivation acts is complex (e.g., EGTRRA 2001 splits into countercyclical for 2001 rebates and long-run for 2002+ rate reductions). LLMs may struggle to apply this nuanced rule.

*Mitigation*: C2 codebook should include a mixed-motivation handling instruction; EGTRRA 2001 serves as a prime positive example of mixed motivation; consider allowing the model to output multiple motivations with apportionment rationale.

**5. Temporal reasoning**

The midpoint rule and phased changes (C3) require precise date reasoning. The spending-driven vs. deficit-driven boundary (C2) requires reasoning about whether a tax change occurs within 1 year of the associated spending change.

*Mitigation*: Provide explicit date arithmetic examples; C3 codebook should include worked examples of the midpoint calculation and phased change decomposition.

**6. R&R background knowledge**

Claude likely has knowledge of R&R's work from pretraining. This creates a risk that the model classifies acts based on memorized R&R classifications rather than following the codebook operationalization applied to the passage text.

*Mitigation*: Test with fictional country-agnostic examples; Tests VI/VII will reveal reliance on background knowledge; LOOCV inherently tests generalization since the held-out act's classification must come from codebook application, not memorization.

### 4.4 Codebook Development Sequence

**Order**: C1 → C2 → C3 → C4

**Rationale**: In production, C1 output feeds C2, which feeds C3/C4:

```
Documents → C1 (Measure ID) → C2 (Motivation) → C3 (Timing) + C4 (Magnitude) → Aggregation
```

**Per-codebook development cycle** (H&K stages):

1. **S0**: Draft codebook YAML following `codebook-yaml` skill conventions
2. **S1**: Run behavioral tests I-IV (label-free); iterate on S0 if tests fail
3. **S2**: Run LOOCV on 44 US acts with primary metrics
4. **S3**: Run Tests V-VII, ablation studies, manual error analysis; iterate on S0 if patterns emerge
5. **S4**: Only if S3 shows unacceptable patterns AND codebook improvements exhausted

**Success criteria** (from `docs/strategy.md`):

| Codebook | Primary Metric | Target |
|----------|---------------|--------|
| C1 | Recall | ≥90% |
| C1 | Precision | ≥80% |
| C2 | Weighted F1 | ≥70% |
| C2 | Exogenous Precision | ≥85% |
| C3 | Exact Quarter | ≥85% |
| C3 | ±1 Quarter | ≥95% |
| C4 | MAPE | <30% |
| C4 | Sign Accuracy | ≥95% |

## Section 5: Downstream Inference & Validation Robustness

*Added 2026-06-24 (literature-review intake). Distilled from `read-deep` sources that extend, rather than duplicate, Sections 1–3: `@ludwig_large_2025` (the §6 generated-regressor pillar) and `@asirvatham_gpt_2026` (the §5 validation pillar), plus the three §6 generated-regressor correction methods `@battaglia_inference_2024`, `@angelopoulos_prediction-powered_2023`, and `@egami_using_2023` (§5.4). Brief notes on two §2 country/method-scrutiny extensions (`@cloyne_discretionary_2013`, `@mertens_reconciliation_2014`) close the section. Implementation reference only — review prose lives in `docs/lit_review.qmd`.*

### 5.1 Ludwig, Mullainathan & Rambachan (2025) — the estimation/prediction split

The single most consequential framing for how our outputs may be *used*. They treat the LLM as a black box and split empirical uses into two problems with different validity requirements:

- **Prediction problem** (forecast an outcome from text): valid iff **no training leakage** between the LLM's training data and the researcher's sample.
- **Estimation/measurement problem** (automate measurement of a concept that then feeds a downstream parameter): valid downstream inference requires **combining LLM outputs with a small labeled validation sample**.

**Our pipeline is squarely the estimation case.** LLM-classified fiscal shocks ($\hat{V}_r$) become regressors in VARs / local projections, so the binding requirement is a validation sample, not behavioral-test accuracy.

**Key results to honor:**

1. **Accuracy is not validity (Lemma 3).** Even a uniformly $\delta$-accurate model can yield estimation error $\geq G\cdot\sum|\delta(r)|\cdot q_{D_r}$, because LLM errors can correlate with economic variables. Plug-in validity holds across all contexts *iff* measurement error is exactly zero (Prop. 2). High S1–S3 accuracy does **not** license raw plug-in use downstream.
2. **The dangerous error is correlated error.** Plug-in bias $\beta = \beta^* + \lambda_{\Delta|W}$, where $\lambda_{\Delta|W}$ is the regression of the LLM error $\Delta_r = \hat{V}_r - V_r$ on covariates $W_r$. For us the dangerous $W$ is the business cycle — the exact axis exogeneity hinges on. We must show mislabeling is uncorrelated with the cycle.
3. **Debias against a random validation sample (Eq. 14).** $\hat\beta_{debiased} = \hat\beta + \hat\lambda_{\Delta|W}$: regress $\hat{V}_r$ on $W_r$ in the primary sample, regress $\Delta_r$ on $W_r$ in the validation sample, subtract; bootstrap both for inference. Properly done, "LLM outputs amplify rather than replace existing measurements" and can give *tighter* SEs than the validation sample alone (precision-gain condition Eq. 16). Simulations: validation samples of **125–250 items** already help materially.
4. **Specification-search risk.** Without debiasing, "seemingly innocuous choices — which LLM, which prompt — lead to dramatically different parameter estimates" (varying in magnitude, sign, significance). Lock the estimand to expert R&R labels $f^*$, not to "what Sonnet outputs." Directly implicates our Haiku→Sonnet C0 swap and any codebook iteration as downstream-inference risks unless debiasing absorbs them.
5. **Leakage enforcement is design, not prompting.** "Ignore information after date $\tau$" prompts failed empirically and sometimes *worsened* leakage. They advise against closed models (Anthropic/OpenAI) for the prediction case because training data is undisclosed. For the *measurement* case, leakage is mechanically zero under random sampling or full-population coverage — so our dominant US threat is measurement error (fix: validation sample), with contamination a separate concern for the prediction-framed contamination probe.

**Project implication:** the Malaysia corpus (20–40 acts) cannot supply 125–250 random expert labels, so the honest options are fraction-of-corpus validation, pooled-regional validation, or scope-limiting the inferential multiplier claim. This is an open design decision flagged in `brainstorm.qmd`, not a solved problem.

### 5.2 Asirvatham, Mokski & Shleifer (2026) — validating GPT-as-measurement (GABRIEL)

Closest external template for "is the LLM output good enough to be a measurement," built on two pillars — **accuracy** (agreement with benchmarks) and **directness** (the measurement comes from the text, not from a proxy). Validates OpenAI GPT models; the *framing* transfers to Claude, the exact correlations do not.

**Borrowable methods:**

1. **Contamination via staggered cutoffs.** Date each dataset by first-posting date; compare a model's accuracy on pre- vs. post-training-cutoff data. They find "no statistically significant difference in mean accuracy before versus after" cutoffs — no contamination *use*, even where memorization is possible. **Hard for us:** US fiscal documents (1945–2022) and the R&R label set are deep in pretraining and we cannot date past a cutoff. Borrow the *directness logic* instead (next point).
2. **Directness / shortcut-inference test (signal stripping).** Remove the signal (e.g., all environmental content) holding everything else fixed; a direct measure collapses toward zero. They report a **98% reduction** in the stripped attribute while the proxy attribute barely moves. **High-value, low-cost addition for C2:** mask the stated motivation sentences and re-classify exogenous/endogenous — if the call survives, the model is inferring from act name / era / party (a construct-validity failure), not reading the rationale.
3. **Human-parity, not raw accuracy (MH vs. leave-one-out HH).** Compare model-vs-consensus correlation to human-vs-consensus; "disagreement with human annotations does not necessarily mean GPT error." This is exactly the right frame for our no-ground-truth Phase 2 expert-agreement gates (≥80% / ≥70%): report expert-vs-expert agreement as the ceiling.
4. **No-cherry-picking benchmark + held-out discipline.** They test against 1000+ tasks (not hand-picked positive cases) and prescribe doing all tuning on a random training subsample with a held-out test set — endorsing our stage-independence (S2/S3 split) convention against the "you tuned on the test set" critique.
5. **Prompt-robustness with a caveat.** 100 prompt variants and 100 attribute-definition variants give near-identical ratings ("not due to our specific prompt, but a general capability"), but *leading* wording still biases. Supports not over-engineering codebook prose and the deferred re-validations after cosmetic edits (e.g., the C1 `{country}` token) — while warning that exogeneity-criterion phrasing must stay neutral.

**Caution:** their "manual validation often unnecessary" claim is hedged ("similar enough to the broad range of comprehension tasks we demonstrate"). Fiscal-exogeneity classification is narrower and more adversarial than generic comprehension, so our small-N manual S3 audit gate is justified, not redundant.

### 5.3 §2 country / method-scrutiny extensions (abstract-depth)

- **`@cloyne_discretionary_2013` (UK).** Applies the R&R narrative strategy to a new country and finds "remarkably similar" magnitudes (a 1% tax cut raises GDP ~0.6% on impact, ~2.5% over three years). The only non-US tax-narrative precedent — the empirical anchor for our country-transfer claim. Captured from the detailed abstract; no codebook change implied (it validates the R&R operationalization already in Section 1).
- **`@mertens_reconciliation_2014` (method scrutiny).** Shows pure SVARs cannot recover the tax multiplier without assuming the output-elasticity of revenue, and that narrative proxies used as instruments yield larger multipliers (~2 on impact, up to 3). Reinforces why the narrative record (not a statutory-rate or SVAR series) is the necessary input, and that measurement error in narrative series matters — links directly to §5.1's debiasing argument.

### 5.4 The generated-regressor correction toolkit (Battaglia / PPI / DSL)

*Added 2026-06-24 (lit intake, three `read-deep` §6 sources). §5.1 establishes the *general* "debias against a validation sample" idea; these three specialize it into the concrete inference machinery our downstream VAR/LP would actually use. All three address the same object — an LLM-measured shock entering a downstream regression — and differ in their assumptions and what they require of our design.*

**`@battaglia_inference_2024` — the bias diagnosis (no labels).** Formalizes the two-step strategy (upstream model estimates latent variables from text; downstream regression treats them as observed) as a measurement-error problem whose bias scales with the average inverse information per observation (κ = lim √n · E[1/Cᵢ]).

- **The error mode is mis-centering, not mis-sizing.** When κ > 0, OLS stays consistent but its asymptotic distribution is *re-centered*; ordinary (Eicker–Huber–White) standard errors remain consistent, so the confidence interval has the right *width* but the wrong *center* and under-covers **silently**. We cannot detect this bias by inspecting reported SEs — a tight, "significant" downstream coefficient is no evidence the inference is valid.
- **Tail observations dominate.** Because bias scales with the *average inverse* information, a few poorly-measured acts (low-confidence / short-document classifications) drive the bias more than the well-measured majority. Validation effort and any down-weighting should target the worst-measured acts.
- **Their baseline fix does not transfer cleanly.** Their one-step joint upstream+downstream likelihood (HMC) presumes a generative IR likelihood an LLM judge does not provide (the authors flag this as the open frontier). Because we *have* a validation sample, the operative correction for us is the labeled-subset strand below — Battaglia supplies the diagnosis, not our fix.

**`@angelopoulos_prediction-powered_2023` — PPI, the assumption-light general machinery.** Builds provably valid CIs for a population estimand from a small gold-labeled sample (n) plus a large prediction-labeled sample (N ≫ n), via a *rectifier* (the prediction error measured only on the gold sample) that debiases the imputation.

- **Distribution-free, model-free coverage.** Validity holds for *any* ML algorithm and *any* data distribution — the right frame for a classifier we cannot certify as unbiased (cross-country, no retraining).
- **Three-way framing for downstream macro inference.** Treating LLM labels as truth = the *imputation* estimator that fails to cover; expert-only = valid but underpowered; PPI = the principled middle. Covers means, quantiles, and OLS/logistic coefficients, with covariate-/label-shift variants that are the natural hook for the Phase 2→3 transfer claim.
- **Caveat:** no gain when predictions are weak or N/n too small — a live risk at SEA corpus sizes. Reference implementation `ppi-py` exists.

**`@egami_using_2023` — DSL, the design-based version closest to our workflow.** Uses imperfect LLM "surrogate" labels as outcomes while keeping valid inference, via a doubly-robust pseudo-outcome corrected on a *probability-sampled* expert subset.

- **Sampling design is the load-bearing assumption (concrete protocol change).** Guarantees require the validated acts to be drawn with a *known* sampling probability π bounded away from zero. Phase 2 should therefore **probability-sample** which acts experts validate — simple or stratified, with π *recorded* — not pick the interesting/borderline ones. This is a low-cost change that converts expert validation from an agreement check into a debiasing instrument.
- **Surrogate quality buys efficiency, not validity.** A better codebook (higher agreement) only shrinks variance; it does not change whether the downstream estimate is unbiased. This reframes our ≥80%/≥70% agreement targets as an *efficiency* lever for any DSL-style analysis, not a validity gate.
- **Quantified caution.** Naive surrogate-only use gave ~40% coverage of nominal-95% CIs at 90% accuracy in their sims — the baseline §6 should cite against treating LLM fiscal-shock labels as ground truth.
- **Why DSL over vanilla PPI for us:** it exploits researcher-controlled sampling (removing the nuisance-rate requirement), which our fully-controlled corpus naturally satisfies. **Scope caveat:** DSL targets the known-corpus outcome-regression case, so the US→Malaysia cross-country transfer sits at the edge of its domain-shift scope.

**Net for our design.** Battaglia tells us the bias is invisible in standard SEs; PPI and DSL tell us a small, *correctly sampled* expert set is structurally load-bearing — not optional QA — for honest downstream inference. This sharpens the §5.1 open problem (the Malaysia corpus of 20–40 acts cannot supply 125–250 random labels): DSL's efficiency-not-validity result means even a modest probability sample yields *valid* (if wider) inference, which is the more defensible claim than chasing accuracy alone.
