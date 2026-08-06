# Pipeline flow diagram
#
# A ggplot-drawn schematic of the route from primary-source government
# documents to the deliverable inventory. Drawn in ggplot rather than mermaid
# or graphviz because the manuscript renders to Typst, where only the plotting
# devices are available.
#
# The same node graph serves three purposes via `highlight`:
#   "none"        — the architecture (section 3)
#   "validated"   — the stages the US benchmark covers (section 5)
#   "unvalidated" — the complement: stages carrying no formal evaluation

#' Node and edge definition for the production pipeline
#'
#' One row per stage. `lane` separates the corpus-building spine (1) from the
#' codebook chain (2) and the agentic component layer (3). `evaluated` marks
#' the stages that carry a formal H&K validation record against US ground
#' truth; everything else is attested some other way, or not at all.
#'
#' @return Tibble of nodes with layout coordinates
pipeline_nodes <- function() {
  tibble::tribble(
    ~id,        ~x, ~y, ~label,             ~detail,                            ~evaluated, ~kind,
    "docs",      1,  2, "Primary\nsources", "Budget speeches, economic reports, plans (EN + BM)", FALSE, "corpus",
    "corpus",    2,  2, "Corpus",           "Extract, clean, chunk",             FALSE,     "corpus",
    "c1",        3,  2, "C1\nMeasure ID",   "Scan every chunk for fiscal measures", TRUE,   "codebook",
    "agentic",   4,  3, "Agentic\nsearch",  "Per-instrument narrative sweep, recall recovery", FALSE, "agentic",
    "freeze",    5,  3, "Frozen acts",      "One row per announced act, human-stamped", FALSE, "agentic",
    "c2a",       6,  2, "C2a\nEvidence",    "Motivation evidence for the named act", TRUE,  "codebook",
    "c2b",       7,  2, "C2b\nClassify",    "Motivation, sign, exogeneity",      TRUE,      "codebook",
    "deliver",   8,  2, "Inventory",        "51 Malaysia events, expert-ready",  FALSE,     "output"
  )
}

#' Edges between pipeline stages
#' @return Tibble of edges with from/to node ids
pipeline_edges <- function() {
  tibble::tribble(
    ~from,      ~to,
    "docs",     "corpus",
    "corpus",   "c1",
    "c1",       "agentic",
    "agentic",  "freeze",
    "freeze",   "c2a",
    "c2a",      "c2b",
    "c2b",      "deliver"
  )
}

#' Pipeline flow diagram
#'
#' @param highlight One of "none" (all stages equally weighted), "validated"
#'   (stages with a US H&K validation record lit, the rest faded), or
#'   "unvalidated" (the complement).
#' @return ggplot object
plot_pipeline_flow <- function(highlight = c("none", "validated", "unvalidated")) {
  highlight <- match.arg(highlight)

  nodes <- pipeline_nodes() |>
    dplyr::mutate(
      lit = switch(highlight,
        none        = TRUE,
        validated   = evaluated,
        unvalidated = !evaluated
      ),
      fill_col = dplyr::case_when(
        !lit           ~ "#F5F5F5",
        kind == "codebook" ~ "#DDEBF7",
        kind == "agentic"  ~ "#FDE9D9",
        kind == "output"   ~ "#E4F0E2",
        TRUE               ~ "#EFEFEF"
      ),
      line_col = dplyr::if_else(lit, "grey25", "grey80"),
      text_col = dplyr::if_else(lit, "grey10", "grey60"),
      # Wrap the descriptions to the box, not to the plotting device.
      detail   = stringr::str_wrap(detail, width = 18)
    )

  # Compact colour key, drawn as three swatches on a row beneath the spine so
  # the figure reads without its caption.
  key <- tibble::tibble(
    x = c(1.0, 3.0, 5.4),
    label = c("Corpus building", "Validated codebook (LLM)", "Agentic + human"),
    fill_col = c("#EFEFEF", "#DDEBF7", "#FDE9D9")
  )

  edges <- pipeline_edges() |>
    dplyr::left_join(
      nodes |> dplyr::select(from = id, x0 = x, y0 = y),
      by = "from"
    ) |>
    dplyr::left_join(
      nodes |> dplyr::select(to = id, x1 = x, y1 = y),
      by = "to"
    )

  half_w <- 0.47
  half_h <- 0.42

  # Trim each edge to the box boundary so arrowheads land on the edge, not
  # inside the node.
  edges <- edges |>
    dplyr::mutate(
      dx = x1 - x0, dy = y1 - y0,
      len = sqrt(dx^2 + dy^2),
      shrink = half_w / pmax(abs(dx), 1e-6),
      shrink = pmin(shrink, 0.42),
      xs = x0 + dx * shrink, ys = y0 + dy * shrink,
      xe = x1 - dx * shrink, ye = y1 - dy * shrink
    )

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = edges,
      ggplot2::aes(x = xs, y = ys, xend = xe, yend = ye),
      arrow = ggplot2::arrow(length = ggplot2::unit(0.16, "cm"), type = "closed"),
      colour = "grey45", linewidth = 0.4
    ) +
    ggplot2::geom_rect(
      data = nodes,
      ggplot2::aes(xmin = x - half_w, xmax = x + half_w,
                   ymin = y - half_h, ymax = y + half_h,
                   fill = fill_col, colour = line_col),
      linewidth = 0.35
    ) +
    ggplot2::geom_text(
      data = nodes,
      ggplot2::aes(x = x, y = y + 0.24, label = label, colour = text_col),
      family = "Libertinus Serif", fontface = "bold", size = 2.5,
      lineheight = 0.9, vjust = 1
    ) +
    ggplot2::geom_text(
      data = nodes,
      ggplot2::aes(x = x, y = y - 0.05, label = detail, colour = text_col),
      family = "Libertinus Serif", size = 1.9, lineheight = 0.95, vjust = 1
    ) +
    ggplot2::geom_rect(
      data = key,
      ggplot2::aes(xmin = x - 0.10, xmax = x + 0.10,
                   ymin = 1.16, ymax = 1.30, fill = fill_col),
      colour = "grey45", linewidth = 0.25
    ) +
    ggplot2::geom_text(
      data = key,
      ggplot2::aes(x = x + 0.18, y = 1.23, label = label),
      family = "Libertinus Serif", size = 1.9, hjust = 0, colour = "grey25"
    ) +
    ggplot2::scale_fill_identity() +
    ggplot2::scale_colour_identity() +
    ggplot2::coord_cartesian(xlim = c(0.45, 8.55), ylim = c(1.12, 3.5)) +
    ggplot2::theme_void(base_family = "Libertinus Serif") +
    ggplot2::theme(plot.margin = ggplot2::margin(2, 2, 2, 2))
}
