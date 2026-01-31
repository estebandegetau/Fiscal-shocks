# Post-Extraction Processing for Model A
# Groups and deduplicates extracted passages across document chunks
# Prepares data for Models B & C

#' Group extracted passages by act across all chunks
#'
#' Takes flattened extraction results and groups passages that refer to the
#' same fiscal act, using fuzzy matching to handle naming variations.
#'
#' @param extracted_acts Tibble from flatten_extracted_acts() with columns:
#'   doc_id, chunk_id, year, act_name, act_year, passages_text, page_numbers,
#'   confidence, agreement_rate, reasoning
#' @param match_threshold Fuzzy match threshold for act names (default 0.85)
#'
#' @return Tibble with grouped acts, one row per unique act:
#'   - act_name: Canonical name (most common form)
#'   - year: Act year (from extraction or document)
#'   - passages_text: Combined passages from all chunks
#'   - page_numbers: All page numbers where act is mentioned
#'   - source_docs: List of source document IDs
#'   - n_chunks: Number of chunks mentioning this act
#'   - avg_confidence: Average extraction confidence
#'   - avg_agreement_rate: Average self-consistency agreement
#' @export
group_extracted_passages <- function(extracted_acts, match_threshold = 0.85) {

  if (nrow(extracted_acts) == 0) {
    return(tibble::tibble(
      act_name = character(),
      year = integer(),
      passages_text = character(),
      page_numbers = list(),
      source_docs = list(),
      n_chunks = integer(),
      avg_confidence = numeric(),
      avg_agreement_rate = numeric()
    ))
  }

  # Normalize act names for matching
  extracted_acts <- extracted_acts |>
    dplyr::mutate(
      act_name_normalized = normalize_act_name_for_grouping(act_name)
    )

  # Find act name clusters using fuzzy matching
  act_clusters <- cluster_act_names(
    extracted_acts$act_name_normalized,
    extracted_acts$act_name,
    threshold = match_threshold
  )

  # Add cluster ID to data
  extracted_acts$cluster_id <- act_clusters$cluster_id

  # Group by cluster
  grouped <- extracted_acts |>
    dplyr::group_by(cluster_id) |>
    dplyr::summarize(
      # Use most common act name as canonical
      act_name = get_canonical_name(act_name),

      # Use most common year (or median if numeric)
      year = get_canonical_year(act_year, year),

      # Combine all passages, deduplicating
      passages_text = combine_passages(passages_text),

      # Flatten and unique page numbers
      page_numbers = list(unique(unlist(page_numbers))),

      # Source documents
      source_docs = list(unique(doc_id)),

      # Counts and averages
      n_chunks = dplyr::n(),
      avg_confidence = mean(confidence, na.rm = TRUE),
      avg_agreement_rate = mean(agreement_rate, na.rm = TRUE),

      .groups = "drop"
    ) |>
    dplyr::select(-cluster_id) |>
    dplyr::arrange(year, act_name)

  message(sprintf(
    "Grouped %d extracted passages into %d unique acts",
    nrow(extracted_acts),
    nrow(grouped)
  ))

  grouped
}


#' Normalize act name for grouping/matching
#'
#' More aggressive normalization than the extraction-time normalize_act_name.
#'
#' @param act_name Character vector of act names
#'
#' @return Normalized character vector
normalize_act_name_for_grouping <- function(act_name) {
  act_name |>
    tolower() |>
    # Remove common prefixes/suffixes
    stringr::str_replace_all("\\bthe\\b", "") |>
    stringr::str_replace_all("\\bof\\b", "") |>
    stringr::str_replace_all("\\bact\\b", "") |>
    stringr::str_replace_all("\\band\\b", "") |>
    # Remove punctuation except digits
    stringr::str_replace_all("[^a-z0-9 ]", "") |>
    # Normalize whitespace
    stringr::str_replace_all("\\s+", " ") |>
    stringr::str_trim()
}


#' Cluster act names using fuzzy matching
#'
#' Groups similar act names together using Jaro-Winkler distance.
#'
#' @param normalized_names Character vector of normalized act names
#' @param original_names Character vector of original act names (for canonical name selection)
#' @param threshold Similarity threshold (default 0.85)
#'
#' @return List with cluster_id vector
cluster_act_names <- function(normalized_names, original_names, threshold = 0.85) {

  n <- length(normalized_names)
  cluster_id <- seq_len(n)  # Start with each name in its own cluster

  if (n <= 1) {
    return(list(cluster_id = cluster_id))
  }

  # Compute pairwise similarities
  for (i in 2:n) {
    for (j in 1:(i - 1)) {
      # Skip if already in same cluster
      if (cluster_id[i] == cluster_id[j]) next

      # Compute similarity
      sim <- 1 - stringdist::stringdist(
        normalized_names[i],
        normalized_names[j],
        method = "jw"
      )

      if (sim >= threshold) {
        # Merge clusters: assign all in cluster i to cluster j
        old_cluster <- cluster_id[i]
        cluster_id[cluster_id == old_cluster] <- cluster_id[j]
      }
    }
  }

  # Renumber clusters to be contiguous
  unique_clusters <- unique(cluster_id)
  cluster_mapping <- setNames(seq_along(unique_clusters), unique_clusters)
  cluster_id <- unname(cluster_mapping[as.character(cluster_id)])

  list(cluster_id = cluster_id)
}


#' Get canonical act name from a group
#'
#' Selects the most common form, preferring longer names (more complete).
#'
#' @param names Character vector of act names in the group
#'
#' @return Single canonical name
get_canonical_name <- function(names) {
  # Count occurrences
  name_counts <- table(names)

  # Among the most common, prefer the longest
  max_count <- max(name_counts)
  top_names <- names(name_counts)[name_counts == max_count]

  # Return the longest among the most common
  top_names[which.max(nchar(top_names))]
}


#' Get canonical year from a group
#'
#' Uses the most common year, falling back to document year if act_year is NA.
#'
#' @param act_years Integer vector of extracted act years
#' @param doc_years Integer vector of document years
#'
#' @return Single canonical year
get_canonical_year <- function(act_years, doc_years) {
  # Prefer act_year when available
  years <- ifelse(is.na(act_years), doc_years, act_years)

  # Use most common
  year_counts <- table(years)
  as.integer(names(year_counts)[which.max(year_counts)])
}


#' Combine passages with deduplication
#'
#' Merges passage texts, removing duplicates and near-duplicates.
#'
#' @param passages_texts Character vector of passage texts
#' @param similarity_threshold Threshold for deduplication (default 0.8)
#'
#' @return Single combined text
combine_passages <- function(passages_texts, similarity_threshold = 0.8) {

  # Split into individual passages
  all_passages <- unlist(stringr::str_split(passages_texts, "\n\n---\n\n"))
  all_passages <- stringr::str_trim(all_passages)
  all_passages <- all_passages[nchar(all_passages) > 50]  # Filter very short

  if (length(all_passages) == 0) {
    return(paste(passages_texts, collapse = "\n\n"))
  }

  # Deduplicate
  keep <- rep(TRUE, length(all_passages))

  for (i in seq_along(all_passages)) {
    if (!keep[i]) next

    for (j in seq_len(i - 1)) {
      if (!keep[j]) next

      # Compute Jaccard similarity on words
      words_i <- unique(strsplit(tolower(all_passages[i]), "\\s+")[[1]])
      words_j <- unique(strsplit(tolower(all_passages[j]), "\\s+")[[1]])

      intersection <- length(intersect(words_i, words_j))
      union <- length(union(words_i, words_j))

      if (union > 0 && intersection / union >= similarity_threshold) {
        # Keep the longer passage
        if (nchar(all_passages[i]) <= nchar(all_passages[j])) {
          keep[i] <- FALSE
        } else {
          keep[j] <- FALSE
        }
      }
    }
  }

  paste(all_passages[keep], collapse = "\n\n---\n\n")
}


#' Match extracted acts to known acts (for validation)
#'
#' Matches grouped extracted acts to ground truth acts using fuzzy matching.
#'
#' @param grouped_acts Tibble from group_extracted_passages()
#' @param known_acts Tibble with known acts (act_name, year columns)
#' @param match_threshold Fuzzy match threshold (default 0.85)
#'
#' @return Tibble with match results
#' @export
match_act_names <- function(grouped_acts, known_acts, match_threshold = 0.85) {

  if (nrow(grouped_acts) == 0 || nrow(known_acts) == 0) {
    return(tibble::tibble(
      extracted_name = character(),
      extracted_year = integer(),
      known_name = character(),
      known_year = integer(),
      similarity = numeric(),
      match_type = character()
    ))
  }

  # Normalize names
  extracted_normalized <- normalize_act_name_for_grouping(grouped_acts$act_name)
  known_normalized <- normalize_act_name_for_grouping(known_acts$act_name)

  # For each extracted act, find best match
  matches <- purrr::map_dfr(seq_len(nrow(grouped_acts)), function(i) {
    ext_name <- extracted_normalized[i]
    ext_year <- grouped_acts$year[i]

    # Compute similarities to all known acts
    sims <- 1 - stringdist::stringdist(ext_name, known_normalized, method = "jw")

    # Consider year match bonus
    year_bonus <- ifelse(
      !is.na(ext_year) & !is.na(known_acts$year) &
        abs(known_acts$year - ext_year) <= 1,
      0.05,  # Small bonus for year match
      0
    )

    adjusted_sims <- sims + year_bonus

    best_idx <- which.max(adjusted_sims)
    best_sim <- sims[best_idx]  # Report unadjusted similarity

    if (best_sim >= match_threshold) {
      tibble::tibble(
        extracted_name = grouped_acts$act_name[i],
        extracted_year = ext_year,
        known_name = known_acts$act_name[best_idx],
        known_year = known_acts$year[best_idx],
        similarity = best_sim,
        match_type = if (best_sim >= 0.95) "exact" else "fuzzy"
      )
    } else {
      tibble::tibble(
        extracted_name = grouped_acts$act_name[i],
        extracted_year = ext_year,
        known_name = NA_character_,
        known_year = NA_integer_,
        similarity = best_sim,
        match_type = "unmatched"
      )
    }
  })

  # Report match statistics
  n_exact <- sum(matches$match_type == "exact", na.rm = TRUE)
  n_fuzzy <- sum(matches$match_type == "fuzzy", na.rm = TRUE)
  n_unmatched <- sum(matches$match_type == "unmatched", na.rm = TRUE)


  message(sprintf(
    "Act matching: %d exact, %d fuzzy, %d unmatched (of %d extracted)",
    n_exact, n_fuzzy, n_unmatched, nrow(grouped_acts)
  ))

  matches
}


#' Deduplicate passages across documents
#'
#' Removes duplicate passages that appear in multiple documents (e.g., from
#' overlapping chunks or cross-document references).
#'
#' @param grouped_acts Tibble from group_extracted_passages()
#' @param similarity_threshold Jaccard similarity threshold (default 0.9)
#'
#' @return Tibble with deduplicated passages
#' @export
deduplicate_passages <- function(grouped_acts, similarity_threshold = 0.9) {

  if (nrow(grouped_acts) <= 1) {
    return(grouped_acts)
  }

  # For each pair of acts, check for high passage overlap
  keep <- rep(TRUE, nrow(grouped_acts))

  for (i in 2:nrow(grouped_acts)) {
    if (!keep[i]) next

    for (j in 1:(i - 1)) {
      if (!keep[j]) next

      # Compare passage text similarity
      words_i <- unique(strsplit(tolower(grouped_acts$passages_text[i]), "\\s+")[[1]])
      words_j <- unique(strsplit(tolower(grouped_acts$passages_text[j]), "\\s+")[[1]])

      if (length(words_i) == 0 || length(words_j) == 0) next

      intersection <- length(intersect(words_i, words_j))
      union <- length(union(words_i, words_j))

      if (union > 0 && intersection / union >= similarity_threshold) {
        # Check if act names are also similar
        name_sim <- 1 - stringdist::stringdist(
          normalize_act_name_for_grouping(grouped_acts$act_name[i]),
          normalize_act_name_for_grouping(grouped_acts$act_name[j]),
          method = "jw"
        )

        if (name_sim >= 0.8) {
          # These are likely the same act - keep the one with more sources
          if (grouped_acts$n_chunks[i] <= grouped_acts$n_chunks[j]) {
            keep[i] <- FALSE
          } else {
            keep[j] <- FALSE
          }
        }
      }
    }
  }

  n_removed <- sum(!keep)
  if (n_removed > 0) {
    message(sprintf("Removed %d duplicate act entries", n_removed))
  }

  grouped_acts[keep, ]
}


#' Prepare grouped acts for Model B classification
#'
#' Formats grouped extracted acts for input to Model B.
#'
#' @param grouped_acts Tibble from group_extracted_passages()
#'
#' @return Tibble ready for model_b_classify_motivation_batch()
#' @export
prepare_for_model_b <- function(grouped_acts) {

  grouped_acts |>
    dplyr::select(
      act_name,
      passages_text,
      year
    ) |>
    dplyr::rename(
      passages_texts = passages_text,
      years = year
    )
}


#' Full post-extraction pipeline
#'
#' Runs the complete post-extraction processing:
#' 1. Flatten batch results
#' 2. Group passages by act
#' 3. Deduplicate
#' 4. Prepare for Model B
#'
#' @param batch_results Tibble from model_a_extract_passages_batch()
#' @param match_threshold Fuzzy match threshold (default 0.85)
#'
#' @return Tibble ready for Model B
#' @export
process_extracted_passages <- function(batch_results, match_threshold = 0.85) {

  message("Step 1: Flattening extraction results...")
  flattened <- flatten_extracted_acts(batch_results)
  message(sprintf("  -> %d act mentions extracted", nrow(flattened)))

  if (nrow(flattened) == 0) {
    message("No acts extracted. Returning empty result.")
    return(tibble::tibble(
      act_name = character(),
      passages_text = character(),
      year = integer()
    ))
  }

  message("Step 2: Grouping passages by act...")
  grouped <- group_extracted_passages(flattened, match_threshold)
  message(sprintf("  -> %d unique acts identified", nrow(grouped)))

  message("Step 3: Deduplicating...")
  deduped <- deduplicate_passages(grouped)
  message(sprintf("  -> %d acts after deduplication", nrow(deduped)))

  message("Step 4: Preparing for Model B...")
  ready <- prepare_for_model_b(deduped)

  message(sprintf("Post-extraction complete: %d acts ready for classification", nrow(ready)))

  # Return with additional metadata columns for traceability
  deduped |>
    dplyr::select(
      act_name,
      year,
      passages_text,
      page_numbers,
      source_docs,
      n_chunks,
      avg_confidence,
      avg_agreement_rate
    )
}
