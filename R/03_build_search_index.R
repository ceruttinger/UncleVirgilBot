# Rebuild only the search index from existing processed chapter_text.csv.

library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(purrr)
library(jsonlite)

source("R/utils_text.R")

dir.create("data/public", recursive = TRUE, showWarnings = FALSE)

if (!file.exists("data/processed/chapter_text.csv")) {
  source("R/01_prepare_corpus.R")
}

chapters <- read_csv("data/processed/chapter_text.csv", show_col_types = FALSE) |>
  filter(chapter != 12)

chunks <- chapters |>
  select(chapter, chapter_title, approx_start_year, approx_end_year, text) |>
  mutate(chunk = map(text, chunk_text)) |>
  select(-text) |>
  unnest_longer(chunk, values_to = "text") |>
  group_by(chapter) |>
  mutate(chunk_number = row_number()) |>
  ungroup() |>
  mutate(
    id = sprintf("ch%02d_%04d", chapter, row_number()),
    excerpt = if_else(nchar(text) > 280, paste0(str_sub(text, 1, 280), "..."), text)
  ) |>
  select(id, chapter, chapter_title, approx_start_year, approx_end_year, text, excerpt)

write_json(chunks, "data/public/search_index.json", pretty = TRUE, auto_unbox = TRUE)
message("Wrote ", nrow(chunks), " search chunks.")
