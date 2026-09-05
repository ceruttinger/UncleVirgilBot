library(readr)
library(dplyr)
library(stringr)
library(tidyr)
library(tidytext)
library(jsonlite)

dir.create("data/public", recursive = TRUE, showWarnings = FALSE)

chapter_file <- "data/processed/chapter_text.csv"

if (!file.exists(chapter_file)) {
  message("chapter_text.csv not found. Running R/01_prepare_corpus.R first.")
  source("R/01_prepare_corpus.R")
}

chapters <- readr::read_csv(chapter_file, show_col_types = FALSE)

required_cols <- c("chapter", "chapter_title", "text")
missing_cols <- setdiff(required_cols, names(chapters))

if (length(missing_cols) > 0) {
  stop("Missing required columns in chapter_text.csv: ", paste(missing_cols, collapse = ", "))
}

word_freq <- chapters |>
  select(chapter, chapter_title, text) |>
  tidytext::unnest_tokens(word, text) |>
  mutate(word = str_to_lower(word)) |>
  filter(str_detect(word, "^[a-z][a-z']+$")) |>
  filter(nchar(word) > 2) |>
  anti_join(tidytext::stop_words, by = "word") |>
  count(chapter, chapter_title, word, sort = TRUE) |>
  group_by(chapter, chapter_title) |>
  slice_max(order_by = n, n = 75, with_ties = FALSE) |>
  mutate(
    min_n = min(n),
    max_n = max(n),
    font_size = if_else(max_n == min_n, 1.5, 0.8 + 2.6 * ((n - min_n) / (max_n - min_n))),
    font_size = round(font_size, 2)
  ) |>
  ungroup() |>
  select(chapter, chapter_title, word, n, font_size) |>
  arrange(chapter, desc(n), word)

readr::write_csv(word_freq, "data/public/word_frequencies.csv")
jsonlite::write_json(word_freq, "data/public/word_frequencies.json", pretty = TRUE, auto_unbox = TRUE)

message("Wrote data/public/word_frequencies.csv")
message("Wrote data/public/word_frequencies.json")
