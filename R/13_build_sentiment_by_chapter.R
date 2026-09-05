suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(tidyr)
  library(tidytext)
  library(jsonlite)
})

message("Building chapter-level and within-chapter sentiment tables...")

safe_word_count <- function(x) {
  x <- ifelse(is.na(x), "", x)
  stringr::str_count(x, stringr::boundary("word"))
}

normalize_text_col <- function(df, preferred = "text") {
  names(df) <- trimws(names(df))
  if (!preferred %in% names(df)) {
    candidates <- c("clean_text", "chapter_text", "passage_text", "raw_text", "body")
    hit <- candidates[candidates %in% names(df)]
    if (length(hit) > 0) {
      df <- dplyr::rename(df, text = !!hit[1])
    }
  }
  df
}

normalize_chapter_cols <- function(df) {
  names(df) <- trimws(names(df))
  if (!"chapter" %in% names(df) && "chapter_number" %in% names(df)) {
    df <- dplyr::rename(df, chapter = chapter_number)
  }
  if (!"chapter_title" %in% names(df) && "title" %in% names(df)) {
    df <- dplyr::rename(df, chapter_title = title)
  }
  if (!"chapter_title" %in% names(df)) {
    df <- df |> mutate(chapter_title = paste("Chapter", chapter))
  }
  df |> mutate(chapter = as.integer(chapter))
}

chapter_path <- dplyr::case_when(
  file.exists("data/processed/chapter_text.csv") ~ "data/processed/chapter_text.csv",
  file.exists("data/public/chapter_text.csv") ~ "data/public/chapter_text.csv",
  TRUE ~ NA_character_
)

if (is.na(chapter_path)) {
  stop("Could not find data/processed/chapter_text.csv or data/public/chapter_text.csv. Run Rscript R/render_all.R first.")
}

chapters <- readr::read_csv(chapter_path, show_col_types = FALSE) |>
  normalize_chapter_cols() |>
  normalize_text_col() |>
  filter(!is.na(chapter), chapter <= 11)

if (!"text" %in% names(chapters)) {
  stop("Chapter data does not contain a text-like column.")
}

chapters <- chapters |>
  mutate(
    text = if_else(is.na(text), "", as.character(text)),
    word_count = if ("word_count" %in% names(chapters)) as.integer(word_count) else safe_word_count(text),
    chapter_label = sprintf("Ch. %02d: %s", chapter, chapter_title)
  ) |>
  select(chapter, chapter_title, chapter_label, word_count, text)

# Bing is bundled with tidytext and avoids the interactive textdata download prompt.
bing <- tidytext::get_sentiments("bing") |>
  mutate(value = if_else(sentiment == "positive", 1L, -1L)) |>
  distinct(word, .keep_all = TRUE)

chapter_tokens <- chapters |>
  select(chapter, chapter_title, chapter_label, word_count, text) |>
  tidytext::unnest_tokens(word, text)

chapter_sent_tokens <- chapter_tokens |>
  inner_join(bing, by = "word")

chapter_sentiment <- chapter_sent_tokens |>
  group_by(chapter, chapter_title, chapter_label) |>
  summarise(
    positive_count = sum(sentiment == "positive", na.rm = TRUE),
    negative_count = sum(sentiment == "negative", na.rm = TRUE),
    sentiment_word_count = n(),
    net_sentiment = sum(value, na.rm = TRUE),
    .groups = "drop"
  )

sentiment_by_chapter <- chapters |>
  select(chapter, chapter_title, chapter_label, word_count) |>
  left_join(chapter_sentiment, by = c("chapter", "chapter_title", "chapter_label")) |>
  mutate(
    across(c(positive_count, negative_count, sentiment_word_count, net_sentiment), ~replace_na(.x, 0L)),
    net_per_1000_words = if_else(word_count > 0, round((net_sentiment / word_count) * 1000, 3), NA_real_),
    positive_share = if_else(sentiment_word_count > 0, round(positive_count / sentiment_word_count, 3), NA_real_),
    negative_share = if_else(sentiment_word_count > 0, round(negative_count / sentiment_word_count, 3), NA_real_),
    sentiment_method = "tidytext_bing_lexicon"
  ) |>
  arrange(chapter)

passage_path <- dplyr::case_when(
  file.exists("data/processed/passage_index.csv") ~ "data/processed/passage_index.csv",
  file.exists("data/public/passage_index.csv") ~ "data/public/passage_index.csv",
  TRUE ~ NA_character_
)

if (is.na(passage_path)) {
  message("No passage index found. Building a simple paragraph-level fallback from chapter text.")
  passages <- chapters |>
    select(chapter, chapter_title, chapter_label, text) |>
    mutate(text = stringr::str_replace_all(text, "\\r\\n", "\n")) |>
    tidyr::separate_rows(text, sep = "\\n\\s*\\n") |>
    group_by(chapter, chapter_title, chapter_label) |>
    mutate(passage_number = row_number()) |>
    ungroup() |>
    mutate(
      text = stringr::str_squish(text),
      passage_id = sprintf("ch%02d_p%03d", chapter, passage_number),
      citation_label = sprintf("Ch. %d: %s, passage %d", chapter, chapter_title, passage_number),
      year_candidates = "",
      entities_mentioned = ""
    ) |>
    filter(text != "")
} else {
  passages <- readr::read_csv(passage_path, show_col_types = FALSE) |>
    normalize_chapter_cols() |>
    normalize_text_col()

  if (!"text" %in% names(passages)) {
    stop("Passage index does not contain a text-like column.")
  }
  if (!"passage_number" %in% names(passages)) {
    passages <- passages |>
      group_by(chapter) |>
      mutate(passage_number = row_number()) |>
      ungroup()
  }
  if (!"passage_id" %in% names(passages)) {
    passages <- passages |>
      mutate(passage_id = sprintf("ch%02d_p%03d", as.integer(chapter), as.integer(passage_number)))
  }
  if (!"citation_label" %in% names(passages)) {
    passages <- passages |>
      mutate(citation_label = sprintf("Ch. %d: %s, passage %d", chapter, chapter_title, passage_number))
  }
  if (!"year_candidates" %in% names(passages)) passages$year_candidates <- ""
  if (!"entities_mentioned" %in% names(passages)) passages$entities_mentioned <- ""
}

passages <- passages |>
  filter(!is.na(chapter), as.integer(chapter) <= 11) |>
  mutate(
    chapter = as.integer(chapter),
    passage_number = as.integer(passage_number),
    text = if_else(is.na(text), "", as.character(text)),
    word_count = if ("word_count" %in% names(passages)) as.integer(word_count) else safe_word_count(text),
    chapter_label = if ("chapter_label" %in% names(passages)) chapter_label else sprintf("Ch. %02d: %s", chapter, chapter_title),
    year_candidates = if_else(is.na(year_candidates), "", as.character(year_candidates)),
    entities_mentioned = if_else(is.na(entities_mentioned), "", as.character(entities_mentioned))
  ) |>
  select(passage_id, chapter, chapter_title, chapter_label, passage_number, citation_label, word_count, text, year_candidates, entities_mentioned, everything())

passage_tokens <- passages |>
  select(passage_id, chapter, chapter_title, chapter_label, passage_number, citation_label, word_count, text) |>
  tidytext::unnest_tokens(word, text)

passage_sent_tokens <- passage_tokens |>
  inner_join(bing, by = "word")

passage_sentiment <- passage_sent_tokens |>
  group_by(passage_id, chapter, chapter_title, chapter_label, passage_number, citation_label) |>
  summarise(
    positive_count = sum(sentiment == "positive", na.rm = TRUE),
    negative_count = sum(sentiment == "negative", na.rm = TRUE),
    sentiment_word_count = n(),
    net_sentiment = sum(value, na.rm = TRUE),
    top_positive_words = paste(names(sort(table(word[sentiment == "positive"]), decreasing = TRUE))[1:min(6, length(sort(table(word[sentiment == "positive"]), decreasing = TRUE)))], collapse = "; "),
    top_negative_words = paste(names(sort(table(word[sentiment == "negative"]), decreasing = TRUE))[1:min(6, length(sort(table(word[sentiment == "negative"]), decreasing = TRUE)))], collapse = "; "),
    .groups = "drop"
  )

sentiment_within_chapter <- passages |>
  select(passage_id, chapter, chapter_title, chapter_label, passage_number, citation_label, word_count, year_candidates, entities_mentioned, text) |>
  left_join(passage_sentiment, by = c("passage_id", "chapter", "chapter_title", "chapter_label", "passage_number", "citation_label")) |>
  mutate(
    across(c(positive_count, negative_count, sentiment_word_count, net_sentiment), ~replace_na(.x, 0L)),
    top_positive_words = replace_na(top_positive_words, ""),
    top_negative_words = replace_na(top_negative_words, ""),
    net_per_1000_words = if_else(word_count > 0, round((net_sentiment / word_count) * 1000, 3), NA_real_),
    sentiment_direction = case_when(
      net_sentiment > 0 ~ "positive",
      net_sentiment < 0 ~ "negative",
      TRUE ~ "neutral"
    ),
    text_preview = stringr::str_trunc(stringr::str_squish(text), 320),
    sentiment_method = "tidytext_bing_lexicon"
  ) |>
  arrange(chapter, passage_number)

passage_summary <- sentiment_within_chapter |>
  group_by(chapter, chapter_title, chapter_label) |>
  summarise(
    passage_count = n(),
    positive_passages = sum(sentiment_direction == "positive", na.rm = TRUE),
    negative_passages = sum(sentiment_direction == "negative", na.rm = TRUE),
    neutral_passages = sum(sentiment_direction == "neutral", na.rm = TRUE),
    strongest_positive_passage = citation_label[which.max(net_sentiment)],
    strongest_negative_passage = citation_label[which.min(net_sentiment)],
    .groups = "drop"
  ) |>
  arrange(chapter)

readr::write_csv(sentiment_by_chapter, "data/processed/sentiment_by_chapter.csv")
readr::write_csv(sentiment_within_chapter, "data/processed/sentiment_within_chapter.csv")
readr::write_csv(passage_summary, "data/processed/sentiment_passage_summary.csv")

readr::write_csv(sentiment_by_chapter, "data/public/sentiment_by_chapter.csv")
readr::write_csv(sentiment_within_chapter, "data/public/sentiment_within_chapter.csv")
readr::write_csv(passage_summary, "data/public/sentiment_passage_summary.csv")

jsonlite::write_json(sentiment_by_chapter, "data/public/sentiment_by_chapter.json", dataframe = "rows", auto_unbox = TRUE, pretty = TRUE, na = "null")
jsonlite::write_json(sentiment_within_chapter, "data/public/sentiment_within_chapter.json", dataframe = "rows", auto_unbox = TRUE, pretty = TRUE, na = "null")
jsonlite::write_json(passage_summary, "data/public/sentiment_passage_summary.json", dataframe = "rows", auto_unbox = TRUE, pretty = TRUE, na = "null")

message("Wrote sentiment-by-chapter and within-chapter sentiment outputs:")
message("- data/public/sentiment_by_chapter.csv")
message("- data/public/sentiment_within_chapter.csv")
message("- data/public/sentiment_passage_summary.csv")
