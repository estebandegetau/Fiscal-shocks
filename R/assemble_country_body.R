#' Pull the manifest slice for one country from `country_urls`
#'
#' `country_urls` is a list-iterated dynamic-branched target; depending on
#' how `{targets}` resolves it at the call site, the symbol may resolve to
#' a list of per-country tibbles or to a single combined tibble. This
#' helper accepts either and returns one tibble for the named country.
#'
#' @param country_urls List of tibbles or single combined tibble from the
#'   `country_urls` target
#' @param country Lowercase country slug (e.g. `"malaysia"`)
#' @return One tibble — the manifest rows for that country
#' @export
country_urls_for <- function(country_urls, country) {
  combined <- if (is.data.frame(country_urls)) {
    country_urls
  } else {
    dplyr::bind_rows(country_urls)
  }
  combined[combined$country == country, , drop = FALSE]
}


#' Assemble per-country body tibble from manifest + per-file extractions
#'
#' Replaces the URL-driven body assembly used in the legacy pipeline.
#' Joins the manifest (`country_urls` for one country) onto extracted text
#' (one tibble per file from per-file branches of `extract_pdf_file`),
#' surfaces orphan files (on disk but absent from the manifest), and
#' preserves the schema downstream targets expect.
#'
#' Schema invariants (so `verify_country_body.qmd` and `make_chunks()`
#' continue working unchanged):
#'   - Every column from `country_urls` is preserved
#'   - Five extraction columns appended: `text`, `n_pages`, `ocr_used`,
#'     `extraction_time`, `extracted_at`
#'   - Manifest rows with no file: `n_pages = 0L`, `text = list(character(0))`
#'   - On-disk files with no manifest match: synthesized row with
#'     `access_status = "orphan"` and `body = "ORPHAN: <series>"`
#'
#' @param file_paths Character vector of PDF paths (sorted; same order
#'   the per-file branches were created in)
#' @param text_branches List of one-row tibbles from `extract_pdf_file()`
#'   branches (one per element of `file_paths`)
#' @param country_urls_for_country Tibble — the manifest for one country
#' @return Tibble matching the legacy `country_body` schema
#' @export
assemble_country_body <- function(file_paths,
                                  text_branches,
                                  country_urls_for_country) {
  if (length(file_paths) != length(text_branches)) {
    stop(sprintf(
      "assemble_country_body: file_paths (%d) and text_branches (%d) length mismatch",
      length(file_paths), length(text_branches)
    ))
  }

  parsed <- purrr::map(file_paths, parse_pdf_path) |> dplyr::bind_rows()

  text_tbl <- dplyr::bind_rows(text_branches)
  text_tbl$abs_path <- file_paths

  extracted <- dplyr::left_join(parsed, text_tbl, by = "abs_path")

  matched <- country_urls_for_country |>
    dplyr::left_join(
      extracted |>
        dplyr::select(country, package_id_inferred, text, n_pages, ocr_used,
                      extraction_time, extracted_at),
      by = c("country", "package_id" = "package_id_inferred")
    ) |>
    dplyr::mutate(
      n_pages = dplyr::coalesce(n_pages, 0L),
      ocr_used = dplyr::coalesce(ocr_used, FALSE),
      text = ifelse(
        purrr::map_lgl(text, is.null),
        list(list(character(0))),
        text
      ),
      access_status = dplyr::if_else(
        n_pages > 0L & access_status == "manual_pending",
        "manual_ready",
        access_status
      )
    )

  pending_with_text <- matched |>
    dplyr::filter(access_status == "manual_ready",
                  package_id %in% country_urls_for_country$package_id[
                    country_urls_for_country$access_status == "manual_pending"
                  ])
  if (nrow(pending_with_text) > 0L) {
    warning(sprintf(paste0(
      "assemble_country_body: %d row(s) flipped from manual_pending ",
      "to manual_ready by file presence; resolve_manual_paths() and ",
      "discover_country_pdfs() disagree."), nrow(pending_with_text)),
      call. = FALSE)
  }

  manifest_ids <- paste(country_urls_for_country$country,
                        country_urls_for_country$package_id, sep = "|")
  extracted_ids <- paste(extracted$country, extracted$package_id_inferred,
                         sep = "|")
  orphan_idx <- which(!extracted_ids %in% manifest_ids &
                        !is.na(extracted$package_id_inferred))

  orphans <- if (length(orphan_idx) > 0L) {
    o <- extracted[orphan_idx, , drop = FALSE]
    tibble::tibble(
      year = o$base_year,
      package_id = o$package_id_inferred,
      pdf_url = NA_character_,
      country = o$country,
      source = NA_character_,
      body = paste0("ORPHAN: ", o$series_folder),
      doc_language = o$doc_language,
      access_status = "orphan",
      local_path = sub(
        paste0("^", normalizePath(here::here(), mustWork = FALSE), "/"),
        "", o$abs_path),
      notes = "On disk but absent from country_urls manifest",
      text = o$text,
      n_pages = dplyr::coalesce(o$n_pages, 0L),
      ocr_used = dplyr::coalesce(o$ocr_used, FALSE),
      extraction_time = o$extraction_time,
      extracted_at = o$extracted_at
    )
  } else {
    matched[0, , drop = FALSE]
  }

  dplyr::bind_rows(matched, orphans)
}
