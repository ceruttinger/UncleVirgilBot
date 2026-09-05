library(readr)
library(dplyr)
library(stringr)

metadata_path <- "data/chapter_metadata.csv"
summary_path <- "data/processed/corpus_build_summary.csv"
out_path <- "data/public/chapter_timeline.csv"

dir.create("data/public", recursive = TRUE, showWarnings = FALSE)

if (!file.exists(metadata_path)) {
  stop("Missing data/chapter_metadata.csv")
}

metadata <- readr::read_csv(metadata_path, show_col_types = FALSE)

if (file.exists(summary_path)) {
  summary <- readr::read_csv(summary_path, show_col_types = FALSE) |>
    select(any_of(c("chapter", "word_count", "char_count", "year_count", "year_candidates", "needs_review", "source_used", "rds_file_count", "pdf_file_count")))
} else {
  summary <- tibble(chapter = metadata$chapter)
}

timeline <- metadata |>
  left_join(summary, by = "chapter") |>
  mutate(
    duration_years = approx_end_year - approx_start_year + 1,
    timeline_label = paste0("Chapter ", chapter, ": ", chapter_title),
    is_aggregate = chapter == 12,
    timeline_review_note = case_when(
      is_aggregate ~ "Aggregate full-text row; exclude from chapter timeline charts.",
      is.na(year_candidates) | year_candidates == "" ~ "No year candidates were detected; review source scan/OCR.",
      TRUE ~ "Curated date range. Year candidates may include historical background or retrospective references."
    )
  ) |>
  arrange(chapter)

readr::write_csv(timeline, out_path)
message("Wrote ", out_path)
