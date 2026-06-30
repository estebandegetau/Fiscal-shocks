# Literature Log

An append-only audit trail of literature decisions: what was added, why, which
section of the paper it supports, and at what read-depth. Mirrors the discipline
of `docs/deltas.md` — one entry per decision, newest at the top, never rewrite
history. The workflow that produces these entries lives in
`docs/lit_review_workflow.md`.

Each entry records a *decision* (add / reclassify / drop / read), so peer-review
defense can trace why every source is in (Research Companion Principle 3:
credibility tracks involvement).

**Entry format** (mirrors `deltas.md`):

- Heading: `## YYYY-MM-DD: <verb> <work> (<section-tag>, <role-tag>)`
- `**Supports:**` — the specific claim or move this source backs
- `**Section:**` — the `lit_review_plan.md` section it lands in (`s1`–`s7`)
- `**Read-depth:**` — `read-deep` / `cite-only` / `verify-then-slot`
- `**Note:**` — one or two lines of rationale or open question

---

## 2026-06-30: Intake of 2 incentive-component cites + 1 Das re-tag (§3, §7, §4)

Fourth intake-loop run against `_Fiscal Shocks` (now 76 items). **Decision:** tag the 2
genuinely new arrivals acquired to support the just-frozen incentive component, re-tag the
Das paper (re-imported under a new Zotero key, lost its tags), write `lit_base.qmd` status
stubs at `consultation: pending`, and reconcile. Tags applied by Claude via the Zotero MCP
on user confirmation; all 3 citekeys resolve in `references.bib`.

**Outcome.** 3 tag operations applied (one section + one role each):

- **§7 datasets — incentive comparator.** Klemm & Van Parys 2012 (`@klemm_empirical_2012`,
  Zotero `Z9MQ9NVB`) → `s7-datasets` + `benchmark`. A cross-country tax-incentive dataset
  (40+ LAC/Africa countries, 1985–2004) named in `docs/deltas.md` (2026-06-30) as the
  **incentive-leg statistical-validation source** — the incentive analog of `@das_ai_2026`
  for spending. **Dual-fit** flagged §1/§3 in `lit_base.qmd`.
- **§3 effects — consumption-holiday support.** Agarwal, Marwell & McGranahan 2017
  (`@agarwal_consumption_2017`, Zotero `HYU4XB2C`) → `s3-effects` + `cite-only`. A
  DiD micro study of the spending response to state sales-tax holidays, supporting the
  consumption-holiday sub-scope of the incentive component.
- **§4 — Das re-tag.** Das et al. 2026 (`@das_ai_2026`) → `s4-llm-text` + `competitor`
  re-applied to the surviving copy (see flag).

**Flags for the human (source-side):**

- **Das re-imported under a new key.** The previously-tagged `WBYNNC32` recorded in
  `lit_base.qmd` is gone from the collection; Das now appears once, untagged, under
  `VHHJLLXL`. Re-tagged it and updated the Zotero key in `lit_base.qmd` (`WBYNNC32` →
  `VHHJLLXL`). If `WBYNNC32` is in the Zotero Trash, empty it so it cannot resurface on a
  future export.
- **Pin `das_ai_2026` before the next BBT export** — it has a date and will silently
  rename, breaking `@das_ai_2026` across `brainstorm.qmd`, `lit_review.qmd`,
  `CIT_forward.qmd`, and `deltas.md`. Still on the pin list with the other `_nodate` keys.
- **Junk still in bib.** `noauthor_gpt_nodate` ("gPT AS A MEASUREMENT TOOL — Google Search")
  remains in `references.bib` but not in the collection — delete at source and re-export.
- **Carried-over duplicates** (Ramey & Zubairy PDF vs no-PDF copy; Aruoba two copies) —
  unchanged; merge at source when convenient.

**Reconciliation.** All 3 new/re-tagged keys resolve in `references.bib`; no live dangling
`@`-citations across `docs/*.qmd`/`*.md` (the lone `embedding_gemma_2025` mention is prose
inside a prior log entry, not a citation).

**Coverage note.** The two new cites give the **incentive component** its first literature
support; the §1–§7 plan has no dedicated incentive section, so they slot into existing
§3/§7 homes. Remaining named gaps unchanged and minor: **§2** Hayo & Uhl (Germany Bundestag
textual analysis); **§7** the Giavazzi expansionary-austerity extension.

**Next steps.** Human pins `das_ai_2026` and re-exports `references.bib` (dropping the junk
entry); then run `/lit-digest` to read the 2 new `consultation: pending` entries and fill
their Summary/Relation.

## 2026-06-24: Intake of 14 new arrivals — §5 contamination + cross-lingual cores, §4 meta layer (all sections)

Third intake-loop run against `_Fiscal Shocks` (now 75 items). **Decision:** tag the 14
items missing section/role tags, write their `lit_base.qmd` status stubs at
`consultation: pending`, and reconcile. Tags applied by Claude via the Zotero MCP on
user confirmation; all 14 citekeys resolve in `references.bib`.

**Outcome.** 14 items tagged (one section + one role each). This run builds out the two
newest §5 sub-bullets and the §4 meta layer:

- **§5 contamination/memorization core (backs the H&K S1 test).** Carlini et al. 2022
  (`@carlini_quantifying_2022`, `read-deep` — upgraded from the proposed `cite-only` per
  user: memorization mechanics warrant distillation into `codebook_sources.md`), Golchin &
  Surdeanu 2024 (`@golchin_time_2024`), Deng et al. 2024 (`@deng_unveiling_2024`) →
  `s5-validation`. These give the S1 memorization test a literature spine.
- **§5 cross-lingual / low-resource core (backs the EN/BM stress test).** Ahuja et al. 2023
  (`@ahuja_mega_2023`, MEGA), Singh et al. 2024 (`@singh_indicgenbench_2024`, IndicGenBench),
  Xuan et al. 2025 (`@xuan_mmlu-prox_2025`, MMLU-ProX) → `s5-validation` + `cite-only`. The
  parallel-question benchmark design (MMLU-ProX) is the template for a like-for-like EN/BM
  comparison.
- **§4 LLM-for-economists + annotation + central-bank meta layer.** Dell 2025
  (`@dell_deep_2025`), Ziems et al. 2024 (`@ziems_can_2024`), Törnberg 2025
  (`@tornberg_large_2025`), Gambacorta et al. 2024 (`@gambacorta_cb-lms_2024`, CB-LMs),
  Araujo et al. 2024 (`@araujo_artificial_2024`, the BIS LLM primer) → `s4-llm-text` +
  `cite-only`. §4 now covers the meta/annotation/central-bank slots the plan named.
- **§1/§3 dual-fit tax-policy cites.** Crispolti et al. 2022 (`@crispolti_cross-country_2022`)
  filed §1 motivation but flagged defensibly §7; Dabla-Norris & Lima 2023
  (`@dabla-norris_macroeconomic_2023`) filed §3 effects but flagged defensibly §7. Both
  marked **dual-fit** in `lit_base.qmd` to revisit at synthesis.

**Reconciliation finding (the headline of this run).** The human's bib re-export means **11
prior `lit_base.qmd` "pending re-export" placeholders now resolve to real citekeys.** Updated
both the status table and the entry citekey lines from descriptive labels / `_pending
re-export_` to the resolved `@key`: `@kaminsky_when_2004`, `@romer_fiscal_2019`,
`@romer_new_2017`, `@blanchard_empirical_nodate`, `@auerbach_measuring_2012`,
`@gechert_what_2015`, `@riera-crichton_tax_2016`, `@ramey_ten_2019`,
`@fernandez-fuertes_monetary_2025`, `@adler_updated_2024`, `@guajardo_expansionary_2014`.
Each verified by Zotero-key + author/year/title against the bib. No live dangling citations
(`embedding_gemma_2025` appears only in a prior log note, not as a citation).

**Flags for the human (source-side):**

- **Duplicate (Ramey & Zubairy 2018).** Two Zotero copies: the PDF copy `WRUHDRNP` (now
  tagged `s3-effects` / `cite-only` / `duplicate-review`) and a no-PDF copy `46AXGD36` (also
  tagged). **Merge at source keeping the PDF copy**; citekey `@ramey_government_2018`
  unaffected.
- **Junk in bib.** `noauthor_gpt_nodate` ("gPT AS A MEASUREMENT TOOL — Google Search" HTML
  capture) is in `references.bib` but not in the collection — delete at the Zotero source and
  re-export.
- **Kaminsky duplicate cleared.** The former `QJWG8RSN` duplicate no longer appears in the
  collection (merged at source); `lit_base.qmd` note updated.

**Acquisition shopping list (remaining gaps — minor).**

- **§2** Hayo & Uhl (Germany, Bundestag textual analysis) — plan-listed; we currently hold
  Latifi/Tillmann as alternates.
- **§7** the Giavazzi (expansionary-austerity) extension named in the plan.

**Next steps.** Human re-exports `references.bib` (to drop the junk entry and pick up the
merged Ramey copy); then run `/lit-digest` to read the new `pending` entries — priority the
`read-deep` Carlini memorization paper for the S1-test distillation.

## 2026-06-24: Intake of 15 new arrivals — §6 pillar de-risked, §5/§4 cores filled (all sections)

Second intake-loop run against `_Fiscal Shocks` (now 62 items). **Decision:** tag the
15 items that arrived since the bulk pass, write their `lit_base.qmd` status stubs at
`consultation: pending`, and reconcile. Tags applied by Claude via the Zotero MCP on
user confirmation; all 15 citekeys resolve in `references.bib`.

**Outcome.** 15 items tagged (one section + one role each). This run closes most of the
acquisition shopping list from the 2026-06-24 bulk pass:

- **§6 generated-regressor pillar — de-risked.** Battaglia et al. 2024
  (`@battaglia_inference_2024`), Angelopoulos et al. 2023
  (`@angelopoulos_prediction-powered_2023`), Egami et al. 2023 (`@egami_using_2023`)
  all filed `s6-generated-reg` + `read-deep`. The pillar goes from single-sourced
  (`@ludwig_large_2025`) to four read-deep sources — the highest referee risk is now
  covered (deep read still pending `/lit-digest`).
- **§5 record-linkage core.** Fellegi & Sunter 1969 (`@fellegi_theory_1969`),
  Abramitzky et al. 2021 (`@abramitzky_automated_2021`), Binette & Steorts 2022
  (`@binette_almost_2022`) → `s5-validation` + `cite-only`. **Role call (note):** the
  prior log proposed `read-deep` for the C0 entity-resolution ones; downgraded to
  `cite-only` because the C0 method-comparison is largely built and these situate it
  rather than drive new codebook design — revisit if the C0 writeup needs distillation.
- **§4 annotation canon.** Ash & Hansen 2023 (`@ash_text_2023`), Grimmer, Roberts &
  Stewart 2022 (`@grimmer_text_2022`, book — no PDF, citekey resolves), Gilardi et al.
  2023 (`@gilardi_chatgpt_2023`) → `s4-llm-text` + `cite-only`.
- **§1/§3/§7 single-cite fills.** Acosta Ormaechea & Yoo 2012
  (`@acosta_ormaechea_tax_2012`, §1); Ramey & Zubairy 2018 (`@ramey_government_2018`,
  §3); Devries-Guajardo-Leigh-Pescatori 2011 (`@pescatori_new_2011`, §7, benchmark);
  plus Hebous & Zimmermann 2018 (`@hebous_revisiting_2018`, §2 method-scrutiny).
- **Two prior "in-bib-not-filed" items resolved:** `@frankel_graduation_2013`
  (`R64M3ZMY`) and `@ilzetzki_how_2013` (`XWMP6F75`) are now filed and tagged; their
  `lit_base.qmd` status flipped file ✓ / tag ✓.

**Flags for the human (source-side):**

- **Junk, still untagged:** `BBEM65RQ` ("gPT AS A MEASUREMENT TOOL - Google Search") —
  carried over from last pass; still needs deletion at the Zotero source.
- **Pin-risk cleared for Ramey & Zubairy:** the user fixed `ramey_government_nodate` →
  `ramey_government_2018` (pinned) before this run, so it no longer carries the
  silent-rename risk. Other `_nodate` keys remain on the pin list (`das_ai_2026`,
  `fritsch_high-frequency_nodate`, `aruoba_identifying_nodate`, `latifi_fiscal_nodate`,
  `romer_trouble_nodate`, `jorda_local_nodate`).
- **No duplicates detected** in the current collection (the earlier Kaminsky dup
  `QJWG8RSN` is no longer present — likely merged at source).

**Reconciliation.** All 15 new keys resolve in `references.bib`; no dangling
`@`-citations across `docs/*.qmd`/`*.md` (the lone `embedding_gemma_2025` mention is
prose inside the prior log entry, not a citation).

**Remaining gaps (deferred per user — leave noted in `lit_review.qmd`, not blocking):**
§4 (Dell 2024, Ziems et al. 2024, Törnberg 2024, BIS LLM primer); §5 (a dedicated
contamination/memorization cite; a multilingual/low-resource-NLP eval cite); §7 (IMF
Tax Policy Reform Database, Dabla-Norris & Lima, statutory-rate panels).

**Next:** run `/lit-digest` on the new `consultation: pending` entries (esp. the three
§6 read-deep sources); then `/lit-synthesize` to fold the now-filled §4/§5/§6 cites
into `lit_review.qmd` and retire its `PENDING ACQUISITION` markers.

## 2026-06-24: Bulk intake + reconciliation of the 48-item `_Fiscal Shocks` library (all sections)

First run of the intake loop (`docs/lit_review_workflow.md`) against the existing
library. **Decision:** tag every item against the §1–§7 plan, log each, deep-read
the two genuinely new pillar sources, draft the synthesized review
(`docs/lit_review.qmd`), and hand the human a prioritized acquisition list. Tags
were applied by Claude via the Zotero MCP for this bulk pass (user-authorized
override of the human-owned Tag step); please spot-check the ambiguous calls below.

**Outcome (summary).** 47 items tagged against §1–§7 (1 junk webpage left untagged
on purpose — see flags); section is the single best-fit home, with span-multiple
items resolved to one tag for self-organizing filtering. Coverage: pillars §2 strong
and §5 well-stocked on exemplars but missing its record-linkage / contamination /
cross-lingual core; **§6 single-sourced on `@ludwig_large_2025` — the highest risk.**
§1/§3/§7 adequate; §4 competitor set complete but annotation canon thin.

**Per-source catalog moved out.** The coverage matrix and the per-source intake
notes that were drafted here now live in `docs/lit_base.qmd` (the annotated
bibliography — status + summary + relation, one entry per source). This log keeps
only the *decision* trail.

**Read-deep this pass** (full distillations folded into `docs/codebook_sources.md`
§5; per-source entries in `lit_base.qmd`): `@ludwig_large_2025` (s6) and
`@asirvatham_gpt_2026` (s5) read in full; `@cloyne_discretionary_2013` and
`@mertens_reconciliation_2014` (s2) captured at abstract-depth since they extend
already-distilled R&R doctrine.

**Flags for the human (source-side, not Claude's to fix):**

- **Junk, left untagged:** `BBEM65RQ` ("gPT AS A MEASUREMENT TOOL - Google Search", citekey `noauthor_gpt_nodate`) — a stray Google-search webpage. Delete at the Zotero source; it should not reach `references.bib`.
- **Duplicate:** Kaminsky-Reinhart-Végh "When It Rains" appears twice (`C375EN8P`, `QJWG8RSN`); the second is tagged `duplicate-review`. Merge at source.
- **In `references.bib` but NOT filed in `_Fiscal Shocks`:** `@ilzetzki_how_2013`, `@frankel_graduation_2013` (both cited in `brainstorm.qmd`), and `@embedding_gemma_2025`. File them into the collection so the library stays the single source of truth. (`@ilzetzki_how_2013`/`@frankel_graduation_2013` bib entries also carry a "Verify against Zotero copy" note.)
- **Pin `_nodate` citekeys** before the next BBT export (`das_ai_2026`, `fritsch_high-frequency_nodate`, `aruoba_identifying_nodate`, `latifi_fiscal_nodate`, `romer_trouble_nodate`, `jorda_local_nodate`) — dates will silently rename them.

**Acquisition shopping list (human Acquire → Export), priority order:**

1. **§6 inference pillar (highest referee risk, currently 1 item):** Battaglia, Christensen, Hansen & Sacher (2024) *Inference for Regression with Variables Generated by AI/ML*; Angelopoulos et al. (2023) *Prediction-Powered Inference*; Egami et al. (design-based supervised learning / imperfect surrogates). → tag `s6-generated-reg` + `read-deep`.
2. **§5 record-linkage + contamination + cross-lingual:** Fellegi & Sunter (1969); Abramitzky, Boustan & Eriksson (2021); Binette & Steorts (2022); a memorization/contamination cite; a multilingual/low-resource-eval cite. → `s5-validation` (`read-deep` for the C0 entity-resolution ones, else `cite-only`).
3. **§4 annotation canon:** Ash & Hansen (2023, ARE); Grimmer, Roberts & Stewart (2022); Gilardi, Alizadeh & Kubli (2023, PNAS). → `s4-llm-text` + `cite-only`.
4. **§1/§3/§7 single-cite fills:** an IMF tax-composition–growth cite (§1); Ramey & Zubairy (§3); Devries-Guajardo-Leigh-Pescatori (2011) + IMF Tax Policy Reform Database (§7).

**Next:** after Acquire + Export, re-run Tag/Annotate on new arrivals, fill the
`PENDING ACQUISITION` markers in `docs/lit_review.qmd`, and reconcile citekeys.
