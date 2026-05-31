---
name: quarto-style
description: Style guide for writing and editing Quarto (.qmd) documents in this project. Apply when creating or modifying any .qmd file.
user-invocable: false
---

# Quarto Style Guide

This skill defines conventions for all `.qmd` files in the project. Apply these rules when creating or editing Quarto documents.

## Two document classes

This guide serves two kinds of document, with different rendering targets:

- **Notebooks** (`notebooks/*.qmd`): render to **HTML + built-in Typst** (see `notebooks/_metadata.yml`). They may use the full **portable article-layout** toolkit (margin notes, margin figures, page-width floats, sidenotes).
- **The paper** (`index.qmd`): renders to **academic-typst** (the vendored `_extensions/estebandegetau/academic/` format). It is **single-column** and does **not** support margin layout.

Two consequences shape everything below:

- **Article layout is notebook presentation only.** Margin and full-width features render in HTML and built-in Typst, but the paper ignores them. Never rely on margin layout to carry meaning that must survive into the paper.
- **The bridge to the paper is the figure / table / equation conventions.** Label prefixes (`fig-`, `tbl-`, `eq-`), the caption style, `tt()` tables, and the `tar_read()` graduation workflow are identical across both classes, so content drafted in a notebook transplants into the paper unchanged.

## Configuration Inheritance

Settings cascade from project-level down. **Do not repeat inherited settings** in individual `.qmd` files.

### Inheritance chain

```
_quarto.yml              (project-wide defaults)
  ├── docs/_metadata.yml   (docs/ directory defaults)
  ├── notebooks/_metadata.yml  (notebooks/ directory defaults)
  └── reports/_metadata.yml    (reports/ directory defaults)
        └── individual.qmd   (only document-specific overrides)
```

### Before writing a `.qmd` file

**Read the relevant config files** to know what's already inherited:

1. **Always read** `_quarto.yml` for project-wide defaults (citations, execute, layout options)
2. **Read the directory's** `_metadata.yml` (e.g., `reports/_metadata.yml`) for format and execute defaults
3. **Do not repeat** any setting that is already defined at a higher level

Two settings worth knowing: `_quarto.yml` already sets `reference-location: margin` (so footnotes render as sidenotes), and `notebooks/_metadata.yml` already declares both `html` and `typst` formats. Notebook layout defaults belong in `notebooks/_metadata.yml` (notebook-only), never in `_quarto.yml` (site-wide).

### What individual `.qmd` files should specify

Only settings **unique to that document**:

```yaml
---
title: "Document Title"
subtitle: "Optional Subtitle"
date: today              # or explicit date; author's choice
date-format: long        # always include this
---
```

Override directory defaults only when necessary (e.g., `number-sections: true` for a proposal).


## Setup Chunk

Include the targets setup block **only when the document reads pipeline data**.

Use `pacman::p_load()` instead of repeated `library()` calls. It installs missing packages and loads them in one call.

```r
#| label: setup
#| cache: false

pacman::p_load(targets, tidyverse, tinytable, here)

here::i_am("path/to/this-document.qmd")
tar_config_set(store = here("_targets"))
source(here("R/tt_theme.R"))
set_theme(theme_minimal())

# Load data
data <- tar_read(target_name)
```

Documents that don't use pipeline data (e.g., pure prose proposals) skip this entirely.

## Tables

**Always use `tinytable` (`tt()`) for tables.** Never use `gt`, `kableExtra`, or markdown tables. `tinytable` has native Typst support and is the project standard.

### Project theme

All tables must end with `|> tt_theme_report()` (defined in `R/tt_theme.R`, sourced in setup). This applies booktabs-style formatting: centered, no row lines, header separator and bottom rule only. The helper is format-agnostic, so the same call renders correctly in both HTML and Typst.

Required pattern:

```r
#| label: tbl-descriptive-name
#| tbl-cap: "**Pool summary**. Row counts at each filtering stage."

data |>
  rename(`Readable Name` = col1) |>
  tt() |>
  tt_theme_report()
```

Rename columns upstream via `dplyr::rename()` (or `setNames()`) before piping into `tt()`. tinytable has no `cols_label()` analog and uses the data-frame's existing column names.

### Rules

- Always set both `label: tbl-{ref}` and `tbl-cap:` chunk options. In Typst, a tinytable caption only renders when the chunk has a `tbl-` label, so the label is mandatory, not optional.
- Reference tables in text with `@tbl-{ref}` (e.g., `@tbl-descriptive-name`)
- Do **not** set captions on the table object; always use Quarto's `tbl-cap:` chunk option so Quarto handles numbering and cross-references
- Always pipe `tt_theme_report()` as the **last** step in the tinytable chain
- Let tables take their natural width; use `tt(width = 0.8)` for page-fraction control when needed
- Use `tinytable::footnote_tt()` for methodological notes
- Use `tinytable::style_tt()` for conditional formatting when it aids interpretation
- Use `tinytable::format_tt(fmt = "%.1f%%")`, `format_tt(fmt = "%.0f")`, etc. (sprintf-style format strings) for consistent number formatting
- **`gt()` does not render in Typst.** Some older notebooks still use `gt()` (sourcing `R/gt_theme.R`). When you next edit such a notebook, migrate its tables to `tt()` so it renders to both formats.

### Caption style (cross-format bridge)

Write every `fig-cap` and `tbl-cap` as a bold title, a period, then a sentence-case description:

```
"**Bold title**. Sentence-case description ending in a period."
```

This matches the academic-typst paper, so captions transplant into `index.qmd` unchanged. Never put titles in `labs(title = ...)` or `tt(caption = ...)`; always use the chunk caption so Quarto numbers and cross-references them.

## Plots

Set the global theme once in the setup chunk via `set_theme(theme_minimal())`. Individual plots should **not** add `+ theme_minimal()`.

```r
#| label: fig-descriptive-name
#| fig-cap: "**Surface-form variance**. Distinct C1 forms per gold act (top 25)."

variance_per_act |>
  ggplot(aes(n_surface_forms, gold_act_name)) +
  geom_col() +
  labs(
    x = "Distinct surface forms",
    y = NULL
  )
```

- Always set both `label: fig-{ref}` and `fig-cap:` chunk options; reference figures with `@fig-{ref}`
- Use the caption style above (`**Title**. Description.`); do **not** put the title in `labs(title = ...)`
- Always provide axis labels via `labs()`
- `theme_minimal()` is set globally in setup; do not repeat per plot
- Use `scales::comma`, `scales::percent`, `scales::dollar_format()` for axis formatting
- **Write draft plot code as a single self-contained pipeline over one input data frame.** This lets it lift into a function with no rewrite when the figure graduates to a target (see below).

## Figure & Table Lifecycle

Figures and tables move through three stages. Drafting happens in the notebook; once a figure or table is stable and bound for the paper, it **graduates** into a target that both the notebook and `index.qmd` read.

### Stage 1: Draft (inline)

Author the figure or table directly in the notebook chunk, written as one pipeline over a **single input data frame** (no references to several loose notebook objects):

```r
#| label: fig-foo
#| fig-cap: "**Title**. Description."

my_input |>            # one data frame in
  mutate(...) |>
  ggplot(aes(...)) +
  geom_*()
```

### Stage 2: Graduate (target)

Once the figure/table is stable and paper-bound:

1. Move the pipeline into a pure function in `R/` (e.g. `R/figures_c0.R`). Figures return a **ggplot object**; tables return **tidy data** (apply `tt() |> tt_theme_report()` in the consuming chunk, not in the function).

   ```r
   # R/figures_c0.R
   plot_variance_per_act <- function(variance_per_act) {
     variance_per_act |>
       ggplot(aes(n_surface_forms, gold_act_name)) +
       geom_col() +
       labs(x = "Distinct surface forms", y = NULL)
   }
   ```

2. Add a target in `_targets.R`, prefixed `fig_` / `tbl_` and codebook-scoped:

   ```r
   tar_target(fig_c0_variance_per_act, plot_variance_per_act(variance_per_act))
   ```

### Stage 3: Consume (both documents)

The notebook **and** `index.qmd` read the same target. The **caption and label live in the consuming chunk**, since the paper usually re-words captions:

```r
#| label: fig-variance-per-act
#| fig-cap: "**Surface-form variance**. Distinct C1 forms per gold act."

tar_read(fig_c0_variance_per_act)
```

Notes:

- **Tables: store tidy data, never a `tt` object.** Build the table in the chunk. This avoids coupling the target to a single output format and sidesteps the tinytable caption-needs-label quirk.
- **Theme applies at print time** in the consuming session. With visual identity deferred, each document's `set_theme()` governs. When a shared ggplot theme is later standardized, sourcing it in both setup chunks restyles every graduated figure with no target rebuild.
- This is consistent with the project's data-generation policy: plotting logic lives in `R/`, the object is produced by a `tar_target`, and functions stay pure (no side effects).

## Article Layout

These features render in **both HTML and built-in Typst**, so they are safe for notebooks. They are **notebook presentation only**; the academic-typst paper is single-column and ignores them.

Use only the portable subset below. Do **not** use directional column variants (`.column-*-left`, `.column-*-right`) or `sidebar-width`; those are HTML-only.

| Purpose | Chunk form | Div / inline form |
|---|---|---|
| Margin note | — | `[text]{.aside}` or `::: {.aside} … :::` or `::: {.column-margin} … :::` |
| Margin figure/table | `#\| column: margin` | `::: {.column-margin} … :::` |
| Caption in margin | `#\| fig-cap-location: margin` / `#\| tbl-cap-location: margin` | — |
| Page-width | `#\| column: page` | `::: {.column-page} … :::` |
| Slightly wider | `#\| column: body-outset` | `::: {.column-body-outset} … :::` |
| Full-bleed | `#\| column: screen-inset` | `::: {.column-screen-inset} … :::` |

Margin notes (both forms):

```markdown
The exogenous share rose sharply.[^margin-fn] An inline aside also works.[noisy due to small N]{.aside}

[^margin-fn]: Footnotes render in the margin as sidenotes (`reference-location: margin`).

::: {.column-margin}
A `.column-margin` block holds caveats, a definition, or a small figure without breaking body flow.
:::
```

Margin figure:

```r
#| label: fig-margin-demo
#| fig-cap: "**Side-note figure**. A compact plot in the margin."
#| column: margin

ggplot(df, aes(x, y)) + geom_point()
```

Page-width table:

```r
#| label: tbl-wide-results
#| tbl-cap: "**Full results**. All folds by metric."
#| column: page

results |> tt() |> tt_theme_report()
```

Footnotes already render in the margin project-wide (`reference-location: margin`). To put citations in the margin too, add `citation-location: margin` at the document level.

## Equations

Label display equations by placing the label after the closing `$$`, and reference with `@eq-name`:

```markdown
$$
d_{\text{euc}} = \sqrt{2 \, d_{\text{cos}}}
$$ {#eq-euc}

As shown in @eq-euc, the Euclidean and cosine distances are monotonically related.
```

Typst caveat: labeled equations with heavy LaTeX can fail to convert to Typst math (Quarto issue #7744), and notebooks have no `mitex` import. Therefore:

- Keep paper-bound equations to standard, Typst-translatable LaTeX.
- Add a `{#eq-}` label only to equations you actually cross-reference.
- Render the notebook to Typst to confirm an equation compiles before relying on it for the paper.

## Markdown Formatting

### Blank lines before block elements (CRITICAL)

A blank line is **required** before bullet lists, numbered lists, block quotes, and code blocks. This applies in both markdown body text and `cat()` output in R chunks.

```markdown
<!-- WRONG -->
**Some text:**
- Bullet 1
- Bullet 2

<!-- CORRECT -->
**Some text:**

- Bullet 1
- Bullet 2
```

In R code chunks with `results='asis'`:

```r
# WRONG
cat("Some text:\n")
cat("- Bullet 1\n")

# CORRECT
cat("Some text:\n\n")
cat("- Bullet 1\n")
```

### Horizontal rules

**NEVER end a section or document with a `---` divider.** Horizontal rules should only appear *between* two sections of content, never trailing after the last paragraph of a section. When in doubt, omit the rule entirely. Prefer using headings (`##`, `###`) to separate content rather than horizontal rules.

### Callout boxes

Use Quarto callout boxes for important notes, warnings, or tips:

```markdown
::: {.callout-note}
Important context the reader should know.
:::

::: {.callout-warning}
A caveat or limitation.
:::
```

### Cross-references

Use Quarto cross-reference syntax for figures, tables, equations, and sections when the document is long enough to benefit from it.

- Figures: `label: fig-{ref}` + `fig-cap:` in chunk options, reference with `@fig-{ref}`
- Tables: `label: tbl-{ref}` + `tbl-cap:` in chunk options, reference with `@tbl-{ref}`
- Equations: `{#eq-{ref}}` after the closing `$$`, reference with `@eq-{ref}`
- Sections: `{#sec-label}` on heading, reference with `@sec-label`

Cross-references work regardless of column placement; `@fig-`/`@tbl-` resolve normally even for floats set to `column: margin` or `column: page`.

## Citations

- Use `@key` syntax for in-text citations: `@romer2010`, `@halterman2025`
- Use `[@key]` for parenthetical citations: `[@romer2010]`
- All references go in `references.bib` at the project root
- Citation style and bibliography are configured in `_quarto.yml`; do not override in individual files
- Footnotes already render in the margin (`reference-location: margin`); add `citation-location: margin` if you want citations in the margin too
- End documents that use citations with:

```markdown
## References {.unnumbered}

::: {#refs}
:::
```

## Writing Style

### Tone

- **Active voice** preferred over passive
- **Concise and direct.** Say what happened and what it means
- Write for an informed reader (World Bank economist) who is not a machine learning specialist
- Explain technical LLM concepts; assume fiscal policy knowledge

### Emphasis

- **Bold** for key terms, findings, and important numbers on first use
- *Italics* for emphasis within sentences and for terms being defined
- Do not overuse either; if everything is bold, nothing stands out

### Dashes

Minimize use of em dashes. Prefer shorter sentences, colons, or parentheses instead.

```markdown
<!-- Avoid -->
The model achieved 92% accuracy --- exceeding the target --- on the test set.

<!-- Prefer -->
The model achieved 92% accuracy, exceeding the target, on the test set.
The model achieved 92% accuracy (exceeding the target) on the test set.
```

### Numbers and metrics

- Report percentages with one decimal: `92.3%`, not `92.307%`
- Always include the target alongside the result: "92.3% accuracy (target: >85%)"
- Use `scales::comma()` for large numbers in R output
- Dollar amounts in billions: `$8.4B` in prose, `scales::dollar_format(suffix = "B")` in code

### Structure

- **No mandatory section template.** Structure follows the document's purpose
- When a summary/overview section is included, place it first
- End with References section (if citations used) and optionally a Technical Appendix

## Code Chunks

### Execute options

Default execute options are set in `_metadata.yml` per directory (read it first). Override in individual chunks only when needed:

```r
#| echo: true               # Show this specific chunk in a report
#| cache: true              # Cache expensive computation
#| fig-width: 8             # Control figure size
#| fig-height: 5
#| column: page             # Article-layout placement (page, margin, body-outset, screen-inset)
#| fig-cap-location: margin # Caption in the margin (fig-cap-location / tbl-cap-location)
```

### Dynamic markdown

When generating markdown from R, use `results: 'asis'` and `cat()`:

```r
#| results: 'asis'

cat(sprintf("**Result:** %.1f%% accuracy\n\n", value * 100))

# Remember blank line before bullets
cat("**Key findings:**\n\n")
cat("- Finding 1\n")
cat("- Finding 2\n")
```

### Chunk labels

Use Quarto's `fig-` and `tbl-` prefixes so cross-references work automatically:

```r
#| label: fig-magnitude-distribution
#| fig-cap: "**Magnitude distribution**. Fiscal shock sizes across the corpus."

#| label: tbl-codebook-performance
#| tbl-cap: "**Codebook performance**. Metrics across all stages."
```

Labels must be descriptive kebab-case with the appropriate prefix (`fig-` or `tbl-`). Chunks that produce neither a figure nor a table use plain kebab-case labels (e.g., `label: setup`, `label: load-data`).
