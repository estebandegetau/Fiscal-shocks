# Literature Review Workflow

How sources flow from discovery into the paper, and who owns each step. This is
the process doc for the methodological leg's literature review. It is the shell —
it defines the machinery; the actual reading, gap analysis, and acquisition are
separate work.

## Document architecture

The literature work lives in distinct, non-overlapping docs. Keep them in their
lanes; do not duplicate content across them.

| Doc | Role | Becomes |
|-----|------|---------|
| `docs/brainstorm.qmd` (§"where to plant the flag") | **Positioning** — competitors, white space, flagship ranking, credibility bar. The canonical argument. | The paper's Introduction / Related Work |
| `docs/lit_review_plan.md` | **Coverage checklist** — what must be cited, organized by the paper's argument (sections §1–§7). | The reference scaffold, spread across the paper |
| `docs/lit_base.qmd` | **Annotated bibliography** — one entry per source: status (file / tag / `consultation`), summary, relation-to-project. The per-source knowledge base. | Feeds the review; not itself paper text |
| `docs/lit_review.qmd` | **Synthesized review** — §1–§7 narrative prose drawn from `lit_base`. | A draft of the review sections |
| `docs/codebook_sources.md` | **Implementation reference** — R&R / Das / H&K distilled into codebook-design decisions. Not a review. | Methods detail (already in use) |

`docs/lit_log.md` sits alongside these as the append-only audit trail of literature
*decisions* (not a per-source catalog — that is `lit_base.qmd`).

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
missed `das_ai_2026`). So citekeys always come from `references.bib`, not
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

## Skills that run the loop

Three user-invocable skills operationalize the loop; **Acquire** and **Export**
stay human, as does committing. The shared state across the skills is each
`lit_base.qmd` entry's `consultation:` field (`pending` → `abstract` / `full`).

| Skill | Loop steps it covers | Writes |
|-------|----------------------|--------|
| `/lit-intake` | Tag + the archival half of Annotate + Reconcile | tags (propose→confirm→apply per item); `lit_base.qmd` status stubs; `lit_log.md` decision; citekey reconciliation + shopping list |
| `/lit-digest` | the comprehension half of Annotate | `lit_base.qmd` summary + relation; advances `consultation`; pillar distillations into `codebook_sources.md` |
| `/lit-synthesize` | turns the annotated base into review prose | refreshes `lit_review.qmd` in place; renders; final reconciliation |

Steps 2–3 are listed below as *(human)* by original design, but `/lit-intake`
applies tags by MCP on confirmation (a sanctioned override) and splits Annotate:
the cheap status stub is `/lit-intake`, the heavy read-and-relate is `/lit-digest`.

## Rules

- **Never hand-edit `references.bib`.** Fix content at the Zotero source and
  re-export. This also cleans junk entries at the source.
- **Human retrieves PDFs.** Claude does not fetch PDFs from the web for deep reads
  (paywall / blocking / wrong-version / contamination risk).
- **Pin BetterBibTeX citekeys** for `_nodate` items so a re-export cannot rename
  them. Known live risk: `das_ai_2026` now has a date and will silently
  rename on the next export, breaking `@das_ai_2026` in `brainstorm.qmd`.
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
