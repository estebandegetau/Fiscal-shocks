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

## YYYY-MM-DD: Example — Added <Author Year> (s6-generated-reg, read-deep)

*(Template entry — delete when the first real entry lands.)*

**Supports:** the §6 pillar that LLM-measured fiscal shocks are a generated
regressor requiring bias correction downstream.
**Section:** s6 (Using LLM-generated variables in inference).
**Read-depth:** read-deep — distilled into `docs/codebook_sources.md`-style notes.
**Note:** de-single-sources the pillar, which currently rests on
`@ludwig_large_2025` alone.
