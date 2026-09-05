# Utility functions for the UncleVirgilBot Quarto rebuild
#
# Design rule: preserve the memoir's historical wording for reading and citations,
# but maintain separate cleaned/normalized fields for search and analysis. Do not
# destructively remove numbers from the canonical text layer.

chapter_words <- c(
  `1` = "one", `2` = "two", `3` = "three", `4` = "four", `5` = "five",
  `6` = "six", `7` = "seven", `8` = "eight", `9` = "nine", `10` = "ten",
  `11` = "eleven"
)

chapter_word_lookup <- c(
  one = 1L, two = 2L, three = 3L, four = 4L, five = 5L, six = 6L,
  seven = 7L, eight = 8L, light = 8L, nine = 9L, ten = 10L, eleven = 11L,
  twelve = 12L
)

clean_ocr_light <- function(x) {
  x |>
    stringr::str_replace_all("\\r\\n?", "\n") |>
    stringr::str_replace_all("[ \\t]+", " ") |>
    stringr::str_replace_all("\\n{3,}", "\n\n") |>
    stringr::str_trim()
}

# Use this only for search/analysis tokens, not display text.
normalize_for_search <- function(x) {
  x |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("[’‘`´]", "'") |>
    stringr::str_replace_all("[“”]", '"') |>
    stringr::str_replace_all("\\bghapter\\b", "chapter") |>
    stringr::str_replace_all("\\bgid\\b", "did") |>
    stringr::str_replace_all("\\bgidnt\\b", "didnt") |>
    stringr::str_replace_all("\\bvwe\\b", "we") |>
    stringr::str_replace_all("\\bina\\b", "in a") |>
    stringr::str_replace_all("\\bona\\b", "on a") |>
    stringr::str_replace_all("\\btwoanda\\b", "two and a") |>
    stringr::str_replace_all("\\bwelltodo\\b", "well to do") |>
    stringr::str_replace_all("\\bsmoothawley\\b", "smoot hawley") |>
    stringr::str_replace_all("\\s+", " ") |>
    stringr::str_trim()
}

count_words_simple <- function(x) {
  stringr::str_count(x, "[A-Za-z][A-Za-z']*")
}

make_review_snippet <- function(x, n = 240) {
  x |>
    stringr::str_replace_all("\\s+", " ") |>
    stringr::str_trim() |>
    stringr::str_sub(1, n)
}

extract_record_heading <- function(text) {
  first_lines <- stringr::str_split(text, "\\n")[[1]] |>
    stringr::str_trim()
  first_lines <- first_lines[nzchar(first_lines)]
  if (length(first_lines) == 0) {
    return(tibble::tibble(detected_chapter = NA_integer_, detected_heading = NA_character_))
  }

  window <- paste(first_lines[seq_len(min(6, length(first_lines)))], collapse = " ") |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("[^a-z0-9 ]", " ") |>
    stringr::str_squish()

  m <- stringr::str_match(window, "(?:chapter|ghapter|gchapter)\\s+([a-z]+|[0-9]{1,2})")
  if (is.na(m[1,2])) {
    return(tibble::tibble(detected_chapter = NA_integer_, detected_heading = NA_character_))
  }

  raw_num <- m[1,2]
  chapter <- suppressWarnings(as.integer(raw_num))
  if (is.na(chapter)) chapter <- unname(chapter_word_lookup[[raw_num]])
  if (is.null(chapter) || is.na(chapter)) chapter <- NA_integer_

  tibble::tibble(detected_chapter = as.integer(chapter), detected_heading = paste(first_lines[seq_len(min(4, length(first_lines)))], collapse = " | "))
}

assign_record_chapters <- function(raw_records, metadata) {
  raw_df <- tibble::tibble(
    source_record_id = seq_along(raw_records$text),
    raw_text = as.character(raw_records$text)
  ) |>
    dplyr::mutate(
      clean_text = clean_ocr_light(raw_text),
      search_text = normalize_for_search(clean_text),
      word_count = count_words_simple(clean_text),
      snippet = purrr::map_chr(clean_text, make_review_snippet)
    )

  headings <- purrr::map_dfr(raw_df$clean_text, extract_record_heading)

  raw_df <- dplyr::bind_cols(raw_df, headings) |>
    dplyr::mutate(
      detected_chapter = dplyr::if_else(detected_chapter %in% metadata$chapter, detected_chapter, NA_integer_),
      assigned_chapter = detected_chapter
    )

  # Carry the latest detected chapter forward. Records before the first heading
  # are assigned to chapter 1 so they are not dropped, but flagged for review.
  current <- NA_integer_
  assigned <- integer(nrow(raw_df))
  for (i in seq_len(nrow(raw_df))) {
    if (!is.na(raw_df$detected_chapter[[i]])) current <- raw_df$detected_chapter[[i]]
    assigned[[i]] <- ifelse(is.na(current), 1L, current)
  }

  raw_df |>
    dplyr::mutate(
      assigned_chapter = assigned,
      chapter_title = metadata$chapter_title[match(assigned_chapter, metadata$chapter)],
      is_heading_record = !is.na(detected_chapter),
      likely_title_only = is_heading_record & word_count <= 25,
      review_flag = dplyr::case_when(
        source_record_id == 1 & is.na(detected_chapter) ~ "text_before_first_detected_heading",
        is_heading_record & likely_title_only ~ "chapter_title_page_or_heading_only",
        is_heading_record & detected_chapter != assigned_chapter ~ "heading_assignment_mismatch",
        TRUE ~ "ok"
      )
    )
}

build_chapter_boundary_review <- function(records) {
  records |>
    dplyr::select(source_record_id, assigned_chapter, chapter_title, detected_chapter, detected_heading, word_count, review_flag, snippet) |>
    dplyr::arrange(source_record_id)
}

extract_year_candidates <- function(records) {
  # This will expose the current weakness: the existing corpus_data.json was
  # likely built after removeNumbers(), so it may have very few or zero years.
  records |>
    dplyr::mutate(
      year = stringr::str_extract_all(clean_text, "\\b(?:18|19|20)[0-9]{2}\\b")
    ) |>
    dplyr::select(source_record_id, assigned_chapter, chapter_title, year, snippet) |>
    tidyr::unnest_longer(year, values_to = "year", keep_empty = FALSE) |>
    dplyr::mutate(year = as.integer(year)) |>
    dplyr::filter(!is.na(year), year >= 1800, year <= 2100) |>
    dplyr::distinct(assigned_chapter, chapter_title, source_record_id, year, .keep_all = TRUE) |>
    dplyr::arrange(assigned_chapter, year, source_record_id)
}

detect_ocr_issues <- function(records) {
  issue_patterns <- tibble::tribble(
    ~issue_type, ~pattern, ~suggested_review,
    "chapter_heading_ocr", "\\bghapter\\b|\\bgchapter\\b", "Review chapter heading OCR and chapter boundary assignment.",
    "missing_apostrophe", "\\bdidnt\\b|\\bwasnt\\b|\\bdont\\b|\\bcouldnt\\b|\\bwouldnt\\b", "Public display can preserve this; search normalization may add apostrophe-insensitive matching.",
    "run_together_words", "\\btwoanda\\b|\\bwelltodo\\b|\\bcoalfired\\b|\\bgroundup\\b", "Consider adding correction to search/display layer if it affects readability.",
    "known_ocr_did", "\\bgid\\b|\\bgidnt\\b", "Likely OCR for did/didn't.",
    "spacing_join", "\\bina\\b|\\bona\\b|\\bsoi\\b", "Likely joined words: in a, on a, so I.",
    "numbers_missing_marker", "\\bmay\\s+shortly|\\boctober\\s+which|\\bapril\\s+in\\b|\\bdec\\s+japan", "Possible missing dates caused by number removal or OCR gaps. Rebuild from raw RDS/PDF to recover dates."
  )

  purrr::pmap_dfr(issue_patterns, function(issue_type, pattern, suggested_review) {
    records |>
      dplyr::filter(stringr::str_detect(search_text, stringr::regex(pattern, ignore_case = TRUE))) |>
      dplyr::transmute(
        issue_type,
        pattern,
        suggested_review,
        source_record_id,
        assigned_chapter,
        chapter_title,
        snippet
      )
  }) |>
    dplyr::arrange(assigned_chapter, source_record_id, issue_type)
}

chunk_text <- function(text, max_chars = 1400) {
  paragraphs <- stringr::str_split(text, "\\n\\s*\\n+")[[1]] |>
    stringr::str_trim()
  paragraphs <- paragraphs[nzchar(paragraphs)]

  chunks <- character()
  current <- character()
  current_n <- 0

  flush_current <- function() {
    if (length(current) == 0) return(NULL)
    paste(current, collapse = "\n\n")
  }

  for (paragraph in paragraphs) {
    if (current_n + nchar(paragraph) > max_chars && length(current) > 0) {
      chunks <- c(chunks, flush_current())
      current <- paragraph
      current_n <- nchar(paragraph)
    } else {
      current <- c(current, paragraph)
      current_n <- current_n + nchar(paragraph) + 2
    }
  }

  if (length(current) > 0) chunks <- c(chunks, flush_current())
  chunks
}
