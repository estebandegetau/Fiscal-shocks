---
name: lit-digest
description: Comprehension pass of the literature loop — read the sources whose docs/lit_base.qmd entry is at consultation pending (or a chosen tier/keys), write their (ii) summary and (iii) relation-to-project, advance the consultation field, and fold read-deep pillars into docs/codebook_sources.md. The heavy, opt-in, cost-gated step.
user-invocable: true
---

# Literature Digest Skill

The heavy comprehension step of the intake loop: it actually *reads* sources and writes the annotated-bibliography bodies in `docs/lit_base.qmd` that `/lit-intake` left as stubs. It is opt-in and scoped because reading is the expensive part — full-text pulls overflow context and are delegated to subagents.

The contract with the other skills is the `consultation:` field in each `lit_base.qmd` entry: this skill consumes `pending` entries and advances them to `abstract` or `full`.

## When to Use

- After `/lit-intake` has created stub entries and you want their summaries/relations filled.
- To deepen specific sources (e.g. the pillars) ahead of writing the review.
- When `docs/lit_review.qmd` shows `PENDING ACQUISITION` markers that are now satisfiable because the PDFs arrived and were intaken.

Do NOT use this skill to tag/triage (that is `/lit-intake`) or to write the synthesized review prose (that is `/lit-synthesize`).

## Guardrails (apply throughout)

- **Read at the depth the role warrants.** `read-deep` (pillar) sources earn a full-text read; everything else is metadata + abstract. Skip the full read entirely when an abstract suffices for a source already distilled elsewhere (e.g. R&R doctrine already in `codebook_sources.md`).
- **Protect context: delegate full-text reads to a subagent.** Zotero full text routinely exceeds the token limit and is saved to a file; never read that file into the main context. Spawn a subagent with a fixed return schema (see Phase 2).
- **Cite only resolvable citekeys** in anything you write; name not-yet-in-bib sources in plain text. Citekeys from `references.bib`, not the MCP.
- **Never commit.**

## Procedure

### Phase 0: Select the work-list

1. Read `docs/lit_base.qmd`. The default work-list is every entry at `consultation: pending`.
2. Honor args if given: an explicit set of citekeys/anchors, or a tier (e.g. "only `read-deep`", "only §6").
3. Order the work-list pillars-first (`read-deep`, then `competitor`/`benchmark`, then the rest), since the pillars carry the most value.
4. Count how many entries would require a **full-text** read (the `read-deep` ones).

#### PAUSE POINT 1 (cost gate)

If more than ~3 entries need full-text reads, stop and present the count and the list:

```
/lit-digest will full-text-read K sources (subagent each) and abstract-read M others.
Full reads: [list]. Proceed, or narrow the scope?
```

**Do NOT spin more than ~3 full-text subagents without confirmation.** Abstract-only batches need no gate.

### Phase 2: Read each source at its depth

- **Abstract depth** (non-`read-deep`): `zotero_get_item_metadata` (include abstract). Summarize from title + abstract + your knowledge; set `consultation: abstract`.
- **Full depth** (`read-deep`): delegate to a subagent. Tell it to call `zotero_get_item_fulltext` for the item key, and that the result will likely overflow to a saved JSON file `{result: string}` — it must probe with `jq 'type, (.result|length)'`, then read the content in full via `jq`/python (not Read's offset/limit), and return a **fixed schema**:
  1. **Summary** (2–5 sentences, what the source says);
  2. **Relation** (how it bears on our project + which other `lit_base` entries it links to);
  3. **Codebook-relevant points** (only if the source is a pillar that should update `codebook_sources.md`; else "none").
  Set `consultation: full`.

### Phase 3: Write the entries

For each processed source, edit its `docs/lit_base.qmd` entry in place:

- Replace the **Summary** seed with the real summary.
- Replace the **Relation** placeholder with the relation prose, adding `[[#sec-<other>]]` cross-links to related entries.
- Update the status line's `consultation:` to `abstract`/`full`.
- Regenerate the `tbl-status` consultation column for the changed rows.

### Phase 4: Pillar distillation (read-deep only, when additive)

For `read-deep` sources whose content extends beyond what `docs/codebook_sources.md` already records, add a concise distillation there (a subsection under the relevant Section), focused on codebook-design / validation / inference implications. Skip when the existing sections already cover it — note that you skipped and why.

### Phase 5: Report

Summarize: which entries advanced (and to what depth), which `codebook_sources.md` sections were touched, and which entries remain `pending`. Suggest `/lit-synthesize` if enough pillar entries are now `full`/`abstract` to refresh the review.

## Error Handling

- **Full text won't extract** (image-only / no OCR): record `consultation: abstract`, write the summary from the abstract, and note the limitation in the entry.
- **Subagent returns thin/empty:** retry once with a sharper prompt; if still thin, fall back to abstract depth and flag it.
- **Source not in the bib:** still digest it; keep the citekey as "pending re-export" + Zotero key.
- **Entry already `full`:** skip unless explicitly asked to re-read.

## Composability

Part of the literature skill set:

- `.claude/skills/lit-intake/SKILL.md` — `/lit-intake` produces the `pending` stubs this skill consumes.
- `.claude/skills/lit-synthesize/SKILL.md` — `/lit-synthesize` reads the populated entries this skill writes.

Process and ownership: `docs/lit_review_workflow.md`. Pillar distillation target: `docs/codebook_sources.md`.
