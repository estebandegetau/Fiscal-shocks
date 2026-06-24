# Literature Review Workflow

How sources flow from discovery into the paper, and who owns each step. This is
the process doc for the methodological leg's literature review. It is the shell —
it defines the machinery; the actual reading, gap analysis, and acquisition are
separate work.

## Three-doc architecture

The literature work lives in three docs with distinct, non-overlapping roles.
Keep them in their lanes; do not duplicate content across them.

| Doc | Role | Becomes |
|-----|------|---------|
| `docs/brainstorm.qmd` (§"where to plant the flag") | **Positioning** — competitors, white space, flagship ranking, credibility bar. The canonical argument. | The paper's Introduction / Related Work |
| `docs/lit_review_plan.md` | **Coverage checklist** — what must be cited, organized by the paper's argument (sections §1–§7). | The reference scaffold, spread across the paper |
| `docs/codebook_sources.md` | **Implementation reference** — R&R / Das / H&K distilled into codebook-design decisions. Not a review. | Methods detail (already in use) |

## Source-of-truth split

Two authorities, two different jobs. Do not collapse them.

- **Zotero `_Fiscal Shocks` collection** = source of truth for *content* — what is
  in scope, the PDFs, and the section/role tags. Nothing enters the paper that is
  not here first.
- **BetterBibTeX export → `references.bib`** = source of truth for *citation keys*
  and what compiles in Quarto. This file is **generated, never hand-edited**.
- **Claude (via Zotero MCP)** = reader and reconciler over the library. Claude does
  **not** acquire PDFs and does **not** own citekeys.

**MCP caveat (tested 2026-06-23):** the Zotero MCP runs in web-API mode. It reads
metadata, abstracts, recent items, and PDF full text reliably, but it **does not
reliably resolve BetterBibTeX citation keys** (a `search_by_citation_key` lookup
missed `das_mapping_nodate`). So citekeys always come from `references.bib`, not
from the MCP.

## Tagging scheme

Every item in the collection gets two tags. This makes the library
self-organizing against the plan: filter by section tag to see coverage gaps,
filter by role tag to see what needs deep reading.

**Section tags** (mirror `docs/lit_review_plan.md`):

- `s1-motivation`
- `s2-narrative`
- `s3-effects`
- `s4-llm-text`
- `s5-validation`
- `s6-generated-reg`
- `s7-datasets`

**Role tags:**

- `read-deep` — a pillar source to distill, not just cite
- `cite-only` — situate-and-move-on
- `competitor` — an LLM-narrative-fiscal paper we position against
- `benchmark` — an external dataset/series used for validation/positioning
- `exemplar-other-domain` — LLM-as-measurement-tool from another field

## The 5-step intake loop

Each new source moves through five steps with one owner each.

1. **Acquire** *(human)* — find it, drag the published PDF into the `_Fiscal
   Shocks` collection. Human owns paywalls, blocking, and published-vs-working-paper
   choice (the things LLMs fail at).
2. **Tag** *(human)* — apply one section tag + one role tag.
3. **Annotate** *(Claude, via MCP)* — read metadata (+ full text for `read-deep`),
   write a short intake note (which claim it supports, which section, read-depth),
   and log it in `docs/lit_log.md`. Pillar papers get a longer distillation into
   `docs/codebook_sources.md`-style form.
4. **Export** *(human)* — re-export `references.bib` from Zotero (BBT; auto-export
   on change is ideal).
5. **Reconcile** *(Claude)* — diff citekeys used in `.qmd`/`.md` against the new
   bib (flag missing), and bib entries not yet cited (coverage gaps per section).
   Record decisions in `docs/lit_log.md`.

## Rules

- **Never hand-edit `references.bib`.** Fix content at the Zotero source and
  re-export. This also cleans junk entries at the source.
- **Human retrieves PDFs.** Claude does not fetch PDFs from the web for deep reads
  (paywall / blocking / wrong-version / contamination risk).
- **Pin BetterBibTeX citekeys** for `_nodate` items so a re-export cannot rename
  them. Known live risk: `das_mapping_nodate` now has a date and will silently
  rename on the next export, breaking `@das_mapping_nodate` in `brainstorm.qmd`.
  Other `_nodate` keys (e.g. `fritsch_high-frequency_nodate`,
  `aruoba_identifying_nodate`, `latifi_fiscal_nodate`) carry the same risk.

## Read-depth tiering

Not every section earns equal effort.

- **Deep-read + annotate** — the pillars: §2 narrative identification, §5
  validation, §6 generated-regressor inference. These carry the contribution and
  the referee risk. Distill them into `docs/codebook_sources.md`-style notes.
- **Position-and-cite** — §1 motivation, §3 effects, §7 datasets. Cite to situate;
  no deep read needed.
- **Verify-then-slot** — candidate works listed in `docs/lit_review_plan.md` are
  web-sweep leads; verify author/year/venue before they enter Zotero.
