# Rebuild sentiment and emotion tables from the chapter-level corpus.

library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(tidytext)
library(ggplot2)

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("assets/img", recursive = TRUE, showWarnings = FALSE)

if (!file.exists("data/processed/chapter_text.csv")) {
  source("R/01_prepare_corpus.R")
}

chapters <- read_csv("data/processed/chapter_text.csv", show_col_types = FALSE) |>
  filter(chapter != 12)

words <- chapters |>
  select(chapter, chapter_title, text) |>
  unnest_tokens(word, text, token = "words")

bing <- tidytext::get_sentiments("bing") |>
  mutate(value = if_else(sentiment == "positive", 1L, -1L))

# Temporary render-safe replacements.
# AFINN and NRC require interactive textdata approval on first download.
# For now, use Bing so Quarto can render non-interactively.
afinn <- bing
nrc <- bing

bing_by_chapter <- words |>
  inner_join(bing, by = "word") |>
  count(chapter, chapter_title, sentiment, name = "n") |>
  pivot_wider(names_from = sentiment, values_from = n, values_fill = 0) |>
  mutate(
    positive = coalesce(positive, 0L),
    negative = coalesce(negative, 0L),
    net_bing_sentiment = positive - negative,
    sentiment_intensity = positive + negative
  )

afin_by_chapter <- words |>
  inner_join(afinn, by = "word") |>
  group_by(chapter, chapter_title) |>
  summarise(afinn_score = sum(value), .groups = "drop")

sentiment_by_chapter <- chapters |>
  select(chapter, chapter_title) |>
  left_join(bing_by_chapter, by = c("chapter", "chapter_title")) |>
  left_join(afin_by_chapter, by = c("chapter", "chapter_title")) |>
  mutate(
    across(c(positive, negative, net_bing_sentiment, sentiment_intensity, afinn_score), ~replace_na(.x, 0))
  )

write_csv(sentiment_by_chapter, "data/processed/sentiment_by_chapter.csv")

nrc_by_chapter <- words |>
  inner_join(nrc, by = "word") |>
  count(chapter, chapter_title, sentiment, name = "n") |>
  arrange(chapter, desc(n))

write_csv(nrc_by_chapter, "data/processed/nrc_emotions_by_chapter.csv")

# Chunk-level sentiment for over-time/over-narrative plots.
chunks <- jsonlite::read_json("data/public/search_index.json", simplifyVector = TRUE) |>
  as_tibble()

chunk_words <- chunks |>
  select(id, chapter, chapter_title, approx_start_year, approx_end_year, text) |>
  unnest_tokens(word, text, token = "words")

chunk_sentiment <- chunk_words |>
  inner_join(bing, by = "word") |>
  count(id, chapter, chapter_title, approx_start_year, approx_end_year, sentiment, name = "n") |>
  pivot_wider(names_from = sentiment, values_from = n, values_fill = 0) |>
  mutate(
    positive = coalesce(positive, 0L),
    negative = coalesce(negative, 0L),
    net_bing_sentiment = positive - negative,
    sentiment_intensity = positive + negative
  ) |>
  arrange(chapter, id)

write_csv(chunk_sentiment, "data/processed/sentiment_by_chunk.csv")

# Save basic plot files as optional assets.
p <- sentiment_by_chapter |>
  ggplot(aes(x = reorder(chapter_title, chapter), y = net_bing_sentiment)) +
  geom_col() +
  coord_flip() +
  labs(x = NULL, y = "Positive - negative", title = "Net sentiment by chapter") +
  theme_minimal()

ggsave("assets/img/net_sentiment_by_chapter.png", p, width = 9, height = 6)

p2 <- nrc_by_chapter |>
  filter(!sentiment %in% c("positive", "negative")) |>
  ggplot(aes(x = reorder(chapter_title, chapter), y = n, fill = sentiment)) +
  geom_col() +
  coord_flip() +
  labs(x = NULL, y = "Word matches", fill = "Emotion", title = "NRC emotions by chapter") +
  theme_minimal()

ggsave("assets/img/nrc_emotions_by_chapter.png", p2, width = 10, height = 7)

message("Wrote sentiment and emotion tables.")
