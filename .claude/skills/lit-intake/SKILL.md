---
name: lit-intake
description: Archival pass of the literature intake loop — detect untagged/new Zotero sources, propose and (on confirm) apply section/role tags, write status stubs to docs/lit_base.qmd, log the decision in docs/lit_log.md, and reconcile citekeys against references.bib. The cheap, run-often step; leaves reading to /lit-digest.
user-invocable: true
---

# Literature Intake Skill

Operationalizes the archival steps of the intake loop in `docs/lit_review_workflow.md`. Run it after the human acquires (and optionally tags) new PDFs in the Zotero `_Fiscal Shocks` collection, or for a full backfill. It is deliberately light: it tags, records status, and reconciles, but does **not** read papers — the expensive summarize-and-relate work belongs to `/lit-digest`.

This skill maintains the *status* layer of `docs/lit_base.qmd` (the annotated bibliography) and appends a decision entry to `docs/lit_log.md`. The two pillars it must protect are the source-of-truth split (Zotero owns content; `references.bib` owns citekeys, generated never hand-edited) and the human ownership of acquisition, export, and commits.

## When to Use

- After you drag new PDFs into the `_Fiscal Shocks` collection and want them filed into the §1–§7 system.
- For a first-run / backfill over an untagged library.
- When you only need a coverage + citekey reconciliation (run it; if no untagged items are found it falls through to reconcile-only).

Do NOT use this skill to read or summarize sources (that is `/lit-digest`) or to write the review prose (that is `/lit-synthesize`).

## Guardrails (apply throughout)

- **Citekeys come from `references.bib`, never the MCP** (BetterBibTeX-key lookups via the Zotero MCP are unreliable). Cross-reference each Zotero item to its citekey by author/year.
- **Never hand-edit `references.bib`** — it is generated. Sources in Zotero but not yet exported get recorded with citekey "pending re-export" + their Zotero item key; never invent a `@key`.
- **Tag per item by key** with `zotero_update_item` (`add_tags`), never `zotero_batch_update_tags` with a text query (it matches across the whole library and cannot disambiguate duplicates).
- **Never commit.** The human owns commits, acquisition (PDFs), and the `references.bib` re-export.
- One section tag (`s1-motivation` … `s7-datasets`) + one role tag per item.

## Procedure

### Phase 0: Preflight

1. Load the Zotero MCP tools (`ToolSearch` for `zotero_search_collections`, `zotero_get_collection_items`, `zotero_get_item_metadata`, `zotero_update_item`). If the MCP is unreachable, stop and tell the user (see Error Handling).
2. Resolve the `_Fiscal Shocks` collection key (`zotero_search_collections`).
3. Read `references.bib` (the citekey authority), `docs/lit_review_plan.md` (the §1–§7 coverage roles), and `docs/lit_review_workflow.md` (the tagging scheme).
4. Read `docs/lit_base.qmd` to see which sources already have entries.
5. If the user passed args (explicit item keys, a tag, or a date scope), use them to scope the work-list; otherwise auto-detect (Phase 1).

### Phase 1: Detect targets

- Pull the collection (`zotero_get_collection_items`, detail `summary`).
- The work-list is every item **missing a section tag (`s1`–`s7`) or a role tag** — i.e. new arrivals since the last run. On a first run this is the whole library.
- Note any junk (stray search-result webpages), duplicates, and items in `references.bib` but not filed in the collection.

### Phase 2: Reconcile + propose tags

For each work-list item, propose one section + one role tag using the decision rules:

| Role | Assign when |
|---|---|
| `competitor` | an LLM-narrative-fiscal paper we position against (Das / Bhasin / Fritsch class) |
| `read-deep` | a pillar source to distill: §2 narrative core, §5 validation core, §6 inference |
| `benchmark` | an external fiscal dataset/series used for validation or positioning |
| `exemplar-other-domain` | LLM-as-measurement (or paper-architecture template) from another field |
| `cite-only` | everything else — situate and move on |

Section = the single best-fit `lit_review_plan.md` home (span-multiple items resolve to one tag for clean filtering).

Then build the coverage picture: count items per section/role and name the gaps versus `lit_review_plan.md`.

#### PAUSE POINT 1

Present the proposed tag map (one row per item: title · proposed section · role · citekey-or-Zotero-key), plus the flags (junk / duplicates / in-bib-not-filed) and the coverage gaps. Stop:

```
Proposed tags for N items below. Confirm to apply via the Zotero MCP, or correct any assignments first.
[table]
Flags: [...]   Coverage gaps: [...]
```

**Do NOT apply tags until the user confirms.** The user may override the convention to auto-apply, but the default is propose-then-confirm.

### Phase 3: Apply tags (on confirm)

- For each confirmed item, `zotero_update_item(item_key=..., add_tags=[section, role])`.
- Leave junk untagged (flag it for source-side deletion); tag a duplicate with `duplicate-review` alongside its section/role.

### Phase 4: Update `docs/lit_base.qmd`

- For each newly tagged item, add or update its `##` entry anchored `{#sec-<citekey>}` (or a slug if no citekey yet), with the status line (`file` · `tag` · section · `consultation: pending`), role, and a one-line seed under **Summary**; **Relation** is left as `*Pending /lit-digest.*` plus a seed note.
- Regenerate the top `tbl-status` table so it lists every source with current file/tag/consultation state.

### Phase 5: Log + hand off

- Append a dated decision entry to `docs/lit_log.md` (newest at top): what was tagged, the coverage verdict, the flags, and a prioritized acquisition shopping list for the gaps. Keep it decisions-only — the per-source catalog lives in `lit_base.qmd`.
- Run the reconciliation grep: every `@key` used across `.qmd`/`.md` must resolve in `references.bib` (flag dangling keys), and list in-bib-not-filed items + a reminder to pin `_nodate` citekeys before the next export.
- Tell the user the next steps: human re-exports `references.bib`; then run `/lit-digest` to read the new `pending` entries.

## Error Handling

- **Zotero MCP unreachable:** stop after Phase 0; report exactly what failed; do not guess tags.
- **Item already fully tagged:** skip it (idempotent); report the skip count.
- **No untagged items found:** fall through to reconcile-only (Phase 5 grep + coverage report) and say so.
- **Citekey cannot be resolved in the bib:** record "pending re-export" + Zotero key; never fabricate a `@key`.

## Composability

Part of the literature skill set; pairs with:

- `.claude/skills/lit-digest/SKILL.md` — `/lit-digest` reads the `consultation: pending` entries this skill creates and fills their Summary/Relation.
- `.claude/skills/lit-synthesize/SKILL.md` — `/lit-synthesize` reads the populated `lit_base.qmd` to write `docs/lit_review.qmd`.

Process and ownership are defined in `docs/lit_review_workflow.md`; the coverage targets are in `docs/lit_review_plan.md`.
