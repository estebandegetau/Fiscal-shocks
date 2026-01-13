clean_us_shocks <- function(data) {
    long_names <- names(data)
    data_clean <- data |>
        janitor::clean_names() |>
        labelled::set_variable_labels(.labels = long_names) |>
        mutate(
            across(
                matches("quarter"),
                lubridate::ym
            ),
            act_name = str_squish(act_name),
            across(
                matches("_exo$|_category$"),
                # Remove white spaces
                ~ str_remove_all(.x, "\\s+")
            )
        )
    return(data_clean)
} 

clean_us_labels <- function(data, us_shocks) {
    long_names <- names(data)

    data_clean <- data |>
        janitor::clean_names() |>
        labelled::set_variable_labels(.labels = long_names) |>
        mutate(
            date = mdy(date),
            act_name = str_squish(act_name)
        )
    return(data_clean)
}

make_pages <- function(data, keys) {

    data |>
        filter(n_pages > 0) |>
        mutate(
            document_id = row_number()
        ) |>
        unnest_longer(text) |>
        mutate(
            .by = pdf_url,
            page_number = row_number()
        ) |>
        mutate(
            tokens = ntoken(tokens(text)),
            number_count = str_count(text, "\\b\\d+\\b"),
            relevant_text = str_detect(
                text,
                regex(
                    paste0("\\b(", paste(keys, collapse = "|"), ")\\b"),
                    ignore_case = TRUE
                )
            ) |>
                as.integer()
        )
}

make_documents <- function(data) {
    data |>
        summarise(
            .by = c(
                country,
                body,
                year, 
                pdf_url, 
                document_id, 
                source, 
                extracted_at),
            text = str_flatten(text, " "),
            tokens = ntoken(tokens(text))
        )
    
}

make_paragraphs <- function(data, keys) {
    data |>
        unnest_tokens(
            output = paragraph,
            input = text,
            token = "paragraphs"
        ) |>
        mutate(
            tokens = ntoken(tokens(paragraph)),
            relevant_text = str_detect(
                paragraph,
                regex(
                    paste0("\\b(", paste(keys, collapse = "|"), ")\\b"),
                    ignore_case = TRUE
                )
            ) |>
                as.integer(),
            # Count occurrences of numbers
            number_count = str_count(paragraph, "\\b\\d+\\b")
        ) |>
        mutate(
            .by = c(pdf_url, paragraph),
            is_duplicate = as.integer(n() > 1)
        )
}

make_relevant_paragraphs <- function(data) {

    relevant_paragraphs <- data |>
        filter(relevant_text == 1) |>
        filter(is_duplicate == 0) |>
        filter(number_count < tokens * 0.5)
    return(relevant_paragraphs)
}