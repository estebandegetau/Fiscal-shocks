# Quarto RevealJS Slide Deck: LLM Construction Guide

You are building a Quarto RevealJS slide deck (`.qmd` file). This guide covers both the technical format and the compositional logic of academic presentations. Follow it closely.

---

## 1. File Structure and YAML Front Matter

Every deck starts with a YAML header. Here is the baseline structure:

```yaml
---
title: "Title Here"
subtitle: "Authors or subtitle"
author: "Presented by: Name"
date: "YYYY-MM-DD"
format:
  revealjs:
    smaller: true
    scrollable: true
    theme: simple
    fig-align: center
toc: true
toc-depth: 1
slide-number: true
execute:
  echo: false
  error: false
bibliography: references.bib
---
```

### Key YAML options to know

| Option | What it does | When to change it |
|---|---|---|
| `smaller: true` | Reduces base font size | Set `false` for talks with large rooms or few words per slide |
| `scrollable: true` | Allows vertical scroll on overflow slides | Almost always keep `true` as a safety net |
| `theme` | Visual theme (`simple`, `dark`, `moon`, `serif`, etc.) | User preference; `simple` is a safe default |
| `toc: true` / `toc-depth: 1` | Auto-generates a table of contents from level-1 headers | Use for talks >10 slides; disable for short decks |
| `slide-number: true` | Shows slide numbers | Almost always keep on |
| `echo: false` | Hides code by default | Keep `false` for presentation decks; `true` only for teaching/tutorial decks |
| `error: false` | Stops rendering on code errors | Keep `false` in production |
| `bibliography` | Path to `.bib` file for citations | Include if any `@citekey` references are used |

### Additional useful YAML options

```yaml
format:
  revealjs:
    width: 1050          # Slide width in pixels
    height: 700          # Slide height in pixels
    margin: 0.1          # Whitespace margin around content
    transition: fade     # Slide transition (none, fade, slide, convex, concave, zoom)
    incremental: false   # If true, ALL bullet lists become incremental by default
    center: true         # Vertically center slide content
    highlight-style: github  # Code syntax highlighting theme
    code-line-numbers: false # Line numbers in code blocks
    footer: "Footer text here"
    logo: path/to/logo.png
```

Only add options you need. Do not clutter the YAML with defaults.

---

## 2. Slide Hierarchy and Section Logic

### Headers create structure

- `# Level 1 Header` → Creates a **section divider slide** (title only, centered). Use these to break the talk into major logical blocks.
- `## Level 2 Header` → Creates a **content slide**. This is where your actual material goes.
- Do NOT use `### Level 3` headers inside slides for sub-points. Use bold text or incremental reveals instead. Level 3 headers create awkward sub-slides that break flow.

### Section divider slides (`#`)

These are navigational landmarks. They should map to the logical skeleton of the talk. The audience sees these in the table of contents. Keep them short (2-4 words).

Examples of good section names:
- `# Motivation`
- `# Data and Measurement`
- `# Empirical Strategy`
- `# Results`
- `# Model`
- `# Counterfactual Analysis`
- `# Conclusions`

---

## 3. Presentation Flow Templates

Use the following templates as structural skeletons. Adapt based on the content, the time constraint, and what the user specifies.

### Template A: Academic Paper Presentation (seminar, journal club, reading group)

This is the most common case. You are presenting someone else's (or your own) research paper.

```
# Context / Setting
  ## Background slide(s): institutional context, stylized facts, the world the paper lives in
  ## Motivation: why this question matters, what gap exists

# Research Question
  ## State the question clearly
  ## Preview the answer or key finding (optional, but often helpful)

# Data
  ## Data sources, sample construction
  ## Key variables and measurement choices
  ## Descriptive statistics or descriptive figures

# Empirical Strategy / Identification
  ## Research design (DiD, IV, RDD, structural model, etc.)
  ## Key assumptions and their plausibility
  ## Threats to identification

# Results
  ## Main results (figures first, tables if needed)
  ## Robustness checks (keep brief unless they are the point)
  ## Mechanisms / heterogeneity

# Discussion / Conclusion
  ## Summary of findings
  ## Limitations
  ## Policy implications or open questions

# References
```

### Template B: Thesis Defense / Research Progress

Longer, more detailed, emphasizes your contribution.

```
# Introduction
  ## The big picture: why this field matters
  ## Specific gap your work addresses
  ## Research question(s)
  ## Preview of contributions

# Literature and Positioning
  ## Where your work fits (keep to 1-2 slides, not a literature review dump)
  ## What is new relative to closest papers

# Institutional Context (if applicable)
  ## Setting details the committee needs to follow the rest

# Data
  ## Sources, construction, sample
  ## Descriptive evidence (figures preferred)

# Methodology
  ## Empirical strategy or model setup
  ## Identification / estimation approach
  ## If structural: model overview, key assumptions, calibration/estimation

# Results
  ## Main findings
  ## Robustness and sensitivity
  ## Mechanisms and heterogeneity

# Extensions / Ongoing Work (if applicable)

# Conclusions
  ## Contributions (restate clearly)
  ## Limitations and future work

# References
# Appendix (extra slides after References, for Q&A)
```

### Template C: Conference Talk (15-20 minutes, strict time)

Ruthlessly selective. One idea, cleanly delivered.

```
# Motivation (1-2 slides)
  ## Why should the audience care? One compelling fact, figure, or puzzle.

# This Paper (1 slide)
  ## Research question + one-sentence answer

# Setting and Data (1-2 slides)
  ## Only what is needed to understand the results

# Strategy (1-2 slides)
  ## Research design, key equation or diagram

# Results (2-4 slides)
  ## Main result figure/table
  ## One robustness or mechanism slide

# Takeaway (1 slide)
  ## What the audience should remember

# References
# Appendix
```

### Adapting templates

These are starting points, not rigid rules. The user may request variations:
- A **methods-heavy** talk may expand the Strategy section and compress Results.
- A **policy-oriented** talk may lead with the policy question and end with recommendations.
- A **structural model** paper often needs a dedicated Model section between Data and Results.

Always ask the user (or infer from context) which sections to emphasize and which to compress.

---

## 4. Slide Composition Rules

### General principles

1. **One idea per slide.** If you find yourself writing "Additionally..." or "Moreover...", you probably need a new slide.
2. **Slides are visual aids, not documents.** The audience should be able to absorb a slide in under 10 seconds of reading. The presenter's voice carries the explanation.
3. **Front-load the point.** The slide title should state the takeaway, not just the topic. Compare:
   - Weak: `## Regression Results`
   - Better: `## The DTL increased land prices near stations`
4. **Prefer figures over tables. Prefer tables over bullet points. Prefer bullet points over paragraphs.** This is a strict hierarchy for academic presentations.
5. **Limit bullet points to 3-5 per slide.** If you have more, split the slide or cut content.
6. **Bullet points should be sentence fragments or single sentences**, not full paragraphs. Each bullet should be one readable line when rendered.

### Figure slides

Figure slides are the backbone of empirical presentations. Compose them as follows:

```markdown
## Descriptive title stating the takeaway

![](path/to/figure.png){fig-align="center"}
```

Rules for figure slides:
- The title does the interpretive work. It should tell the audience what to see, e.g., "Low-income workers cluster in non-tradable sectors" rather than "Figure 3".
- The figure should be the only content on the slide (no competing bullet points beneath it).
- Use `{fig-align="center"}` to center images.
- If the figure requires brief annotation, place 1-2 lines of text **above** the image, not below.
- If a figure needs extensive setup, put the setup on the preceding slide.
- For **inline code-generated figures**, use a code chunk with `#| label:` and `#| fig-cap:` options:

```{{r}}
#| label: fig-event-study
#| fig-cap: "Housing prices increased near DTL stations after opening"
#| fig-width: 10
#| fig-height: 6
#| echo: false

# plotting code here
```

- For **pre-made images**, use the markdown image syntax: `![optional-caption](Images/filename.png){fig-align="center"}`
- If the user provides both an image file and an inline code option, prefer inline code for reproducibility unless the figure comes from an external source.

### Text slides

Text slides should be sparse. Compose them as follows:

```markdown
## Takeaway as the title

- First key point, one line

- Second key point, one line

- Third key point, one line
```

Rules for text slides:
- Blank lines between bullets improve readability in RevealJS.
- Use **bold** sparingly to direct the eye to the single most important phrase on the slide.
- Do not bold entire bullets. Bold a phrase within a bullet.
- Avoid nested bullets (sub-bullets). If nesting is truly necessary, limit to one level of depth and keep sub-items very short.

### Equation slides

For model-heavy presentations, equation slides need special care:

```markdown
## Workers maximize expected utility

$$
u_{nil}^j (\omega; \theta) = \mathbb{B}_n(\omega; \theta) \cdot \mathbb{W}^j_{ni}(\omega; \theta) \cdot \mathbb{C}_{nl}(\omega; \theta)
$$

Where $\mathbb{B}_n$ captures residential utility, $\mathbb{W}^j_{ni}$ captures work utility, and $\mathbb{C}_{nl}$ captures consumption travel utility.
```

Rules:
- One key equation per slide, maximum two if they are closely related (e.g., a definition and its first-order condition).
- Always provide a one-line verbal interpretation of notation below the equation.
- Do not dump a full system of equations on one slide. Spread them across slides with verbal narration of what each component adds.
- Use `$$...$$` for display math, `$...$` for inline math.
- LaTeX math rendering is native in Quarto RevealJS; no special configuration is needed.

### Table slides

Tables are sometimes necessary (regression output, calibration parameters). Keep them minimal:

```markdown
## Treatment effect is concentrated near stations

| | (1) | (2) | (3) |
|---|---|---|---|
| Treatment | 0.15*** | 0.12*** | 0.10** |
| | (0.03) | (0.04) | (0.05) |
| Controls | No | Yes | Yes |
| FE | No | No | Yes |
| N | 5,000 | 5,000 | 4,800 |
```

Rules:
- If a table has more than 5-6 rows or 4-5 columns, it is too large for a slide. Trim it or move the full version to the appendix and show a simplified version.
- Highlight the key coefficient or result using **bold**.
- For code-generated tables, use `knitr::kable()` or `gt::gt()` with minimal styling.

---

## 5. Incremental Reveals and Pacing

RevealJS supports incremental content display. Use it to control attention.

### The `. . .` syntax

Place `. . .` (three dots with spaces) on its own line between content blocks to create pauses:

```markdown
## Motivation

Notice the DTL serves primarily high-income residential zones.

. . .

Previous research shows poor workers face larger commuting costs.

. . .

If benefits are not shared, **urban inequality** may increase.
```

### When to use incremental reveals

- **Motivation slides**: Build the argument step by step.
- **Research question slides**: State the question, pause, then give the preview of the answer.
- **Mechanism slides**: Walk through the logic chain.

### When NOT to use incremental reveals

- **Figure slides**: Show the figure immediately. Do not hide it behind a reveal.
- **Results slides**: Show the result. Suspense is for talks, not slides.
- **Reference-heavy or technical slides**: Reveals slow down complex content that the audience needs to process as a whole.

### Incremental bullet lists (alternative syntax)

If you want all bullets in a list to appear one at a time:

```markdown
::: {.incremental}
- First point
- Second point
- Third point
:::
```

Or set `incremental: true` in YAML for a global default (use sparingly; it slows down everything).

---

## 6. Slide Count and Time Budgeting

A rough rule: **1 slide per minute** for standard academic talks, with some slides taking more time (complex figures, key results) and some less (section dividers, simple context).

| Talk length | Target slide count (excluding appendix) |
|---|---|
| 15 min (conference) | 12-18 slides |
| 30 min (seminar) | 25-35 slides |
| 45 min (job market / defense) | 35-50 slides |
| 60+ min (thesis defense) | 45-60 slides |

If the user specifies a time constraint, use this table to calibrate. If no time is specified, ask.

---

## 7. The Appendix

Place extra material after the `## References` slide. These slides are not part of the main talk but are available for Q&A.

Common appendix content:
- Full regression tables
- Additional robustness checks
- Data construction details
- Model derivations
- Alternative specifications

Label appendix slides clearly:

```markdown
## Appendix: Full Regression Table {visibility="uncounted"}
```

The `{visibility="uncounted"}` attribute excludes the slide from the slide count.

---

## 8. Citations and References

### Inline citations

Use `@citekey` syntax for author-year citations:

```markdown
@chetty2014 find that urban inequality undermines social cohesion.
```

This renders as "Chetty et al. (2014) find that..."

Use `[@citekey]` for parenthetical citations:

```markdown
Urban inequality may entrench advantages [@chetty2014].
```

### The references slide

End the deck with:

```markdown
## References
```

Quarto auto-generates the bibliography from cited works. If you want to include references that were not cited in the text, add a `nocite` field in YAML:

```yaml
nocite: |
  @lee2024, @ahlfeldt2015
```

### Bibliography file

The `.bib` file must be in the same directory as the `.qmd` (or at the path specified in YAML). The user should provide it or specify the references to include.

---

## 9. Images and Static Assets

### Directory convention

Store images in an `Images/` subdirectory relative to the `.qmd` file:

```
project/
├── presentation.qmd
├── references.bib
└── Images/
    ├── figure1.png
    ├── figure2.png
    └── map.png
```

### Image sizing

If an image is too large or too small, control it with attributes:

```markdown
![](Images/figure.png){fig-align="center" width="80%"}
```

Or with explicit pixel dimensions:

```markdown
![](Images/figure.png){fig-align="center" width="700px"}
```

Prefer percentage widths for portability.

---

## 10. Code Chunks (for inline figures and computation)

### Setup chunk

Always start with a setup chunk that loads packages and sets global options:

```{{r}}
#| label: setup
#| include: false
#| cache: false

library(tidyverse)
library(here)
library(knitr)

# Set global chunk options if needed
knitr::opts_chunk$set(
  fig.align = "center",
  dpi = 300
)
```

### Figure chunks

```{{r}}
#| label: fig-descriptive
#| fig-cap: "Low-income workers are concentrated in non-tradable sectors"
#| fig-width: 10
#| fig-height: 6

ggplot(data, aes(x = low_income_share, y = nontradable_share)) +
  geom_point() +
  theme_minimal()
```

### Useful chunk options

| Option | Purpose |
|---|---|
| `#| echo: false` | Hide code (default for presentations) |
| `#| eval: true/false` | Whether to run the code |
| `#| include: false` | Run code but hide everything (output and code) |
| `#| cache: true` | Cache results for faster re-rendering |
| `#| fig-width` / `#| fig-height` | Figure dimensions in inches |
| `#| fig-cap` | Figure caption |
| `#| output: asis` | Treat output as raw markdown |

---

## 11. Rendering

The deck is rendered via terminal:

```bash
quarto render presentation.qmd
```

This produces an `.html` file that opens in any browser. For PDF output (less common for RevealJS), the user would need to configure `format: revealjs` with print options or use `quarto render --to pdf`.

---

## 12. Common Pitfalls to Avoid

1. **Wall-of-text slides.** If a slide has more than 6 lines of text, it needs trimming or splitting.
2. **Reading the paper aloud.** A presentation is not a compressed version of the paper. It is a guided tour of the key ideas. Cut aggressively.
3. **Orphan slides.** Every slide must connect to the one before and after it. If a slide could be removed without the audience noticing, remove it.
4. **Inconsistent notation.** Define notation once and stick with it. Do not introduce new symbols without explanation.
5. **Burying the lead.** State results early and clearly. The audience should know the main finding by the halfway point of the talk.
6. **Over-using incremental reveals.** They are a pacing tool, not a default. If a slide has 3 short bullets, just show them all at once.
7. **Missing the "so what."** Every results slide should connect findings back to the research question or a policy implication. Do not leave interpretation to the audience.
8. **Forgetting the appendix.** Anticipate likely questions and prepare backup slides. This is especially important for seminars and defenses.

---

## 13. Commented-Out Content for Flexibility

A useful pattern: draft extra slides in the `.qmd` but comment them out with HTML comments. This keeps cut material accessible if the presenter decides to include it or needs it for Q&A:

```markdown
<!-- ## Additional context slide

- Extra detail that was cut for time
- But might be useful in Q&A -->
```

This content will not render but stays in the source file.

---

## 14. Checklist Before Finalizing

Before delivering the final `.qmd` to the user, verify:

- [ ] YAML front matter is complete and valid
- [ ] All image paths exist and are correctly referenced
- [ ] All `@citekey` references have corresponding entries in the `.bib` file
- [ ] No slide has more than 6 lines of body text
- [ ] Every figure slide has a descriptive title (not "Figure 1")
- [ ] Section headers (`#`) map to logical blocks of the talk
- [ ] The research question is clearly stated on its own slide
- [ ] Main results appear before the halfway mark of the slide count
- [ ] The deck ends with `## References` (and optionally appendix slides after)
- [ ] Code chunks have `echo: false` unless the talk is a tutorial
- [ ] Incremental reveals (`. . .`) are used only where pacing demands it
- [ ] The slide count is appropriate for the stated time constraint