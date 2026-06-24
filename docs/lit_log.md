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
  silent-rename risk. Other `_nodate` keys remain on the pin list (`das_mapping_nodate`,
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
- **Pin `_nodate` citekeys** before the next BBT export (`das_mapping_nodate`, `fritsch_high-frequency_nodate`, `aruoba_identifying_nodate`, `latifi_fiscal_nodate`, `romer_trouble_nodate`, `jorda_local_nodate`) — dates will silently rename them.

**Acquisition shopping list (human Acquire → Export), priority order:**

1. **§6 inference pillar (highest referee risk, currently 1 item):** Battaglia, Christensen, Hansen & Sacher (2024) *Inference for Regression with Variables Generated by AI/ML*; Angelopoulos et al. (2023) *Prediction-Powered Inference*; Egami et al. (design-based supervised learning / imperfect surrogates). → tag `s6-generated-reg` + `read-deep`.
2. **§5 record-linkage + contamination + cross-lingual:** Fellegi & Sunter (1969); Abramitzky, Boustan & Eriksson (2021); Binette & Steorts (2022); a memorization/contamination cite; a multilingual/low-resource-eval cite. → `s5-validation` (`read-deep` for the C0 entity-resolution ones, else `cite-only`).
3. **§4 annotation canon:** Ash & Hansen (2023, ARE); Grimmer, Roberts & Stewart (2022); Gilardi, Alizadeh & Kubli (2023, PNAS). → `s4-llm-text` + `cite-only`.
4. **§1/§3/§7 single-cite fills:** an IMF tax-composition–growth cite (§1); Ramey & Zubairy (§3); Devries-Guajardo-Leigh-Pescatori (2011) + IMF Tax Policy Reform Database (§7).

**Next:** after Acquire + Export, re-run Tag/Annotate on new arrivals, fill the
`PENDING ACQUISITION` markers in `docs/lit_review.qmd`, and reconcile citekeys.
