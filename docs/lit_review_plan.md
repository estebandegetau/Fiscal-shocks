# Plan for a complete literature review

*Role: the coverage checklist — what must be cited, by section. Subordinate to the positioning argument in `docs/brainstorm.qmd`; intake mechanics in `docs/lit_review_workflow.md`.*

This outline is organized around the **paper's argument**, not just topics. Each
section states *why it belongs* and lists candidate works. Citations were
gathered in a light, wide web sweep (2026-06-23) and should be **verified
(author / year / venue) before use** — treat them as leads.

The methodological spine: we (i) take a hand-built narrative identification
method, (ii) scale it with LLMs, (iii) validate the LLM as a measurement tool,
and (iv) hand off a generated variable for downstream inference. Sections 2, 5,
and 6 are the load-bearing methodological pillars; sections 1, 3, and 7 motivate
and situate.

## 1. Motivation — why exogenous fiscal measures matter (macro growth & development)

*Role: the "why." For most emerging markets we lack consistent, comparable
measures of exogenous fiscal shocks — the input credible fiscal analysis needs.
Keep compressed into a motivation section; do not let it lead the paper.*

- Empirical growth / taxation–growth: cross-country panels on tax composition
  and growth (e.g., IMF "Tax Composition and Growth"); differential effects in
  developed vs. developing economies; nonlinearities / threshold effects.
- Macro development: fiscal capacity, revenue volatility and GDP instability,
  institutional quality; fiscal policy and multipliers in EMDEs specifically
  (why comparable cross-country shock series are scarce and valuable).

## 2. PILLAR — The narrative identification approach we are scaling

*Role: the method we automate. This is the methodological backbone and must be
visibly its own section, distinct from "effects" (§3) and "datasets" (§7).*

- Foundational: Romer & Romer (2010, AER) — RR1–RR6, exogenous vs.
  endogenous motivation.
- US extensions: Mertens & Ravn (2013, AER); narrative series as proxy-SVAR
  instruments.
- Country extensions: Cloyne (2013, AER, UK; plus interwar-Britain and
  corporate-tax papers); Hayo & Uhl and the Bundestag textual-analysis work
  (Germany).
- Method scrutiny: Hebous & Zimmermann (revisiting narrative tax multipliers);
  narrative vs. VAR identification debates.

## 3. How these shocks get used — effects of fiscal policy

*Role: shows the demand for the variable we produce, and motivates Pillar §6
(what happens when the regressor is LLM-measured).*

- SVAR tradition: Blanchard & Perotti (2002) and successors.
- Proxy-SVAR / external-instrument identification using narrative series.
- Local projections and state-dependent multipliers (Ramey & Zubairy; Ramey's
  multiplier surveys, e.g., JEP).
- Multiplier magnitudes / IMF technical notes as reference points.

## 4. LLMs as measurement tools — text-as-data foundations & social-science deployment

*Role: situates our tooling in both the econ text-as-data canon and the
social-science annotation literature.*

- Econ text-as-data canon: Gentzkow, Kelly & Taddy (2019, JEL); Ash & Hansen
  (2023, ARE); Grimmer, Roberts & Stewart (2022).
- LLMs for economists (meta layer): Korinek (2023); Dell (2024, deep learning
  for economists); Ludwig, Mullainathan & Rambachan (*LLMs: An Applied
  Econometric Framework*); BIS LLM primer.
- LLM annotation in social science: Gilardi, Alizadeh & Kubli (2023, PNAS);
  Ziems et al. (2024); Törnberg (2024).
- Applied measurement exemplars: LLM analysis of central bank communication
  (IMF WP 2025/109); identifying economic narratives in text with LLMs.

## 5. Validation — is the LLM output good enough to be a measurement?

*Role: the H&K spine, plus the broader measurement-validity tradition. Organize
by our three sub-tasks: extraction, aggregation/entity-resolution, categorization.*

- Framework: Halterman & Keith (2025, Political Analysis) — 5-stage S0–S3+;
  "Codebook LLMs" measurement-validity strand; "codebook conceptualization is
  still a first-order concern."
- **Categorization (C1/C2):** zero-shot/few-shot classification validity;
  measuring accuracy against a labeled subset; shallow-shortcut failure modes.
- **Extraction (C1):** LLM information extraction from documents; schema-guided
  structured output; multi-pass extraction; source traceability.
- **Aggregation / entity resolution (C0):** record linkage (Fellegi–Sunter;
  blocking), LLM-based entity matching, clustering; econ-history automated
  linking (Abramitzky, Boustan & Eriksson 2021; Binette & Steorts 2022).
- **Robustness:** prompt-space / order sensitivity; behavioral reliability
  ("When better codebooks are not enough"); intercoder-reliability framing
  (Krippendorff-style) for expert agreement.
- **Contamination / memorization:** pretraining-leakage risk for historical US
  documents — the threat our H&K S1 memorization test guards against.
- **Cross-lingual / low-resource NLP:** multilingual LLM evaluation, translation,
  low-resource-language performance (EN/BM and the SEA extension) — both a risk
  and a contribution angle.

## 6. PILLAR — Using LLM-generated variables in downstream inference

*Role: the riskiest gap. Our output becomes a regressor in a VAR / local
projection, making it a generated-regressor / measurement-error problem. A
methodological paper that emits LLM-measured economic variables must engage this,
and it gives us a "how to use our output responsibly" section.*

- Battaglia, Christensen, Hansen & Sacher (2024) — *Inference for Regression
  with Variables Generated by AI or Machine Learning* (bias + valid-inference
  corrections). Directly on point.
- Angelopoulos et al. (2023) — *Prediction-Powered Inference*.
- Egami et al. — using imperfect surrogates / design-based supervised learning.
- ML-predictions-as-regression-covariates strand (Political Analysis).

## 7. Existing fiscal datasets — the output landscape & comparators

*Role: what already exists, so our contribution and validation targets are legible.*

- Narrative / action-based: Devries, Guajardo, Leigh & Pescatori (2011, IMF WP);
  Guajardo, Leigh & Pescatori (2014, JEEA); Giavazzi extension; Dabla-Norris &
  Lima.
- Statutory / text-mined: IMF Tax Policy Reform Database; statutory-rate panels.
- US reference series: Romer–Romer shock series; `us_shocks.csv` lineage.

---

**Open sequencing note:** §1 (motivation) and §3 (effects) are confirmed as
motivation/demand framing, not application targets. Pillars §2, §5, §6 carry the
methodological contribution.
