---
name: lit-synthesize
description: Synthesis pass of the literature loop — refresh docs/lit_review.qmd in place from the annotated bibliography in docs/lit_base.qmd, citing only citekeys that resolve in references.bib, marking gaps as PENDING ACQUISITION, then render HTML and run a final citekey reconciliation.
user-invocable: true
---

# Literature Synthesize Skill

The synthesis step: it turns the per-source annotated bibliography (`docs/lit_base.qmd`) into the §1–§7 narrative review (`docs/lit_review.qmd`). It reads from `lit_base`, does not read papers itself, and edits the review **in place** so the human's prose edits survive.

## When to Use

- After `/lit-digest` has populated enough `lit_base.qmd` entries (especially the pillars) that the review can be written or refreshed.
- When new sources have been intaken/digested and the review needs their citations woven in, or `PENDING ACQUISITION` markers can now be filled.

Do NOT use this skill to tag (that is `/lit-intake`) or to read/summarize sources (that is `/lit-digest`).

## Guardrails (apply throughout)

- **Cite only keys that resolve in `references.bib`.** A dangling `@key` breaks the render and is the classic trap. Sources in Zotero but not yet exported are named in plain text with "citekey pending re-export"; convert them to `@key` only once they appear in the bib.
- **Refresh in place.** Read the current `docs/lit_review.qmd` and edit sections; do not overwrite the file (preserves manual edits). Fill `PENDING ACQUISITION` markers as their sources arrive; add new sources to the right §section.
- **Citekeys from `references.bib`, never the MCP. Never commit.**
- Follow the `quarto-style` skill (pacman setup chunk, `tt()` for tables, Chicago author-date, blank line before bullet lists, minimal em dashes, no section-ending `---`).

## Procedure

### Phase 0: Inputs

1. Read `docs/lit_base.qmd` (the per-source summaries + relations + status), `docs/lit_review_plan.md` (the §1–§7 role framing), and the current `docs/lit_review.qmd`.
2. Read `references.bib` and build the set of resolvable citekeys.
3. Note which `lit_base` entries are still `consultation: pending` — their content is thin, so cite them lightly and consider a `PENDING` note rather than leaning on them.

### Phase 1: Refresh each section in place

For each of §1–§7:

- Open with the section's role framing (from `lit_review_plan.md`).
- Synthesize from the `lit_base` summaries/relations into argument — heavier on the pillars (§2 narrative, §5 validation, §6 inference), lighter "position-and-cite" on §1/§3/§7.
- Cite resolvable `@key`s; name not-yet-in-bib sources in plain text + "citekey pending re-export" and add a `RECONCILIATION NOTE` where several cluster.
- Where a needed source is absent (not yet acquired), keep/insert a blockquote `> **PENDING ACQUISITION:** <work> — needed for <claim>`.
- Edit existing prose rather than rewriting wholesale; preserve any human edits.

### Phase 2: Render

- `quarto render docs/lit_review.qmd --to html` and confirm it compiles. (Render Typst too only if the doc is paper-bound and a figure/table changed.)

### Phase 3: Final reconciliation

- Grep every `@key` used across `.qmd`/`.md` and confirm each resolves in `references.bib` (no dangling keys). Reuse the pattern: extract `@[\w-]+`, diff against the bib's `^@type{key` entries.
- List bib entries not yet cited (coverage notes), in-bib-not-filed items, and a reminder to pin `_nodate` citekeys before the next export.

#### PAUSE POINT 1

Present the refreshed section list, the render result, the reconciliation result (dangling keys, if any), and the remaining `PENDING ACQUISITION` markers. Let the user review before they decide to commit (commits are theirs).

## Error Handling

- **Render fails on a citation:** find the offending `@key` (not in bib), replace with plain-text "citekey pending re-export," re-render.
- **`lit_base.qmd` mostly `pending`:** warn that the review will be thin; offer to run `/lit-digest` first.
- **Section has no sources yet:** write the role framing + a `PENDING ACQUISITION` marker rather than inventing content.

## Composability

Final step of the literature skill set:

- `.claude/skills/lit-intake/SKILL.md` — establishes status + citekeys.
- `.claude/skills/lit-digest/SKILL.md` — populates the `lit_base.qmd` bodies this skill synthesizes.

Process and ownership: `docs/lit_review_workflow.md`. The positioning argument the review serves lives in `docs/brainstorm.qmd`.
