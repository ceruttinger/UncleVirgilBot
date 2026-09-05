# Prepare corpus source into chapter-level files, QA tables, and a static search index.
#
# Preferred source order:
# 1. data/raw/corpus_raw_from_rds.json   # rebuilt from raw .rds files; preserves numbers/dates
# 2. data/raw/corpus_data.json           # current uploaded JSON; useful, but likely number-stripped

library(jsonlite)
library(readr)
library(dplyr)
library(stringr)
library(purrr)
library(tibble)
library(tidyr)

source("R/utils_text.R")

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed/chapters", recursive = TRUE, showWarnings = FALSE)
dir.create("data/public", recursive = TRUE, showWarnings = FALSE)

preferred_source <- if (file.exists("data/raw/corpus_raw_from_rds.json")) {
  "data/raw/corpus_raw_from_rds.json"
} else {
  "data/raw/corpus_data.json"
}

raw_records <- jsonlite::read_json(preferred_source, simplifyVector = TRUE)
if (!"text" %in% names(raw_records)) {
  stop("Corpus source must contain a text column/field.")
}

metadata <- readr::read_csv("data/chapter_metadata.csv", show_col_types = FALSE)

records <- assign_record_chapters(raw_records, metadata)
readr::write_csv(records, "data/processed/corpus_records_review.csv")

boundary_review <- build_chapter_boundary_review(records)
readr::write_csv(boundary_review, "data/processed/chapter_boundary_review.csv")

ocr_review <- detect_ocr_issues(records)
readr::write_csv(ocr_review, "data/processed/ocr_review.csv")

year_candidates <- extract_year_candidates(records)
readr::write_csv(year_candidates, "data/processed/year_candidates_by_chapter.csv")

n_years <- nrow(year_candidates)
source_warning <- if (preferred_source == "data/raw/corpus_data.json" && n_years < 20) {
  "Current corpus_data.json appears to be missing many dates/years, likely because setup.R removed numbers before exporting JSON. Rebuild from raw RDS/PDF with R/00_rebuild_raw_text_from_rds.R or R/00_ocr_scanned_pdfs.R before final timeline work."
} else {
  "Source text appears usable for initial chapter/timeline extraction. Still review OCR and boundaries."
}

chapters <- records |>
  filter(assigned_chapter != 12) |>
  group_by(chapter = assigned_chapter, chapter_title) |>
  summarise(
    text = paste(clean_text[!likely_title_only], collapse = "\n\n") |> clean_ocr_light(),
    source_record_start = min(source_record_id),
    source_record_end = max(source_record_id),
    source_records = dplyr::n(),
    heading_records = sum(is_heading_record),
    .groups = "drop"
  ) |>
  left_join(metadata, by = c("chapter", "chapter_title")) |>
  mutate(
    approx_start_year = suppressWarnings(as.integer(approx_start_year)),
    approx_end_year = suppressWarnings(as.integer(approx_end_year)),
    word_count = count_words_simple(text),
    char_count = nchar(text),
    boundary_confidence = dplyr::case_when(
      chapter %in% c(1, 2, 3, 10) ~ "medium",
      chapter == 12 ~ "not_applicable",
      TRUE ~ "needs_review"
    )
  ) |>
  select(chapter, chapter_title, approx_start_year, approx_end_year, life_stage, primary_locations,
         date_confidence, boundary_confidence, source_record_start, source_record_end,
         source_records, heading_records, word_count, char_count, text)

full_text <- paste(chapters$text, collapse = "\n\n") |> clean_ocr_light()

full_row <- metadata |>
  filter(chapter == 12) |>
  transmute(
    chapter,
    chapter_title,
    approx_start_year = NA_integer_,
    approx_end_year = NA_integer_,
    life_stage,
    primary_locations,
    date_confidence,
    boundary_confidence = "not_applicable",
    source_record_start = min(records$source_record_id),
    source_record_end = max(records$source_record_id),
    source_records = nrow(records),
    heading_records = sum(records$is_heading_record),
    word_count = count_words_simple(full_text),
    char_count = nchar(full_text),
    text = full_text
  )

chapters_with_full <- bind_rows(chapters, full_row)

readr::write_csv(chapters_with_full, "data/processed/chapter_text.csv")
readr::write_csv(
  chapters_with_full |>
    select(chapter, chapter_title, approx_start_year, approx_end_year, life_stage, primary_locations,
           date_confidence, boundary_confidence, source_record_start, source_record_end,
           source_records, heading_records, word_count, char_count),
  "data/processed/chapter_stats.csv"
)

purrr::pwalk(chapters_with_full, function(chapter, chapter_title, approx_start_year, approx_end_year, life_stage, primary_locations, date_confidence, boundary_confidence, source_record_start, source_record_end, source_records, heading_records, word_count, char_count, text) {
  out <- file.path("data/processed/chapters", sprintf("chapter_%02d.md", chapter))
  writeLines(c(
    sprintf("# Chapter %s: %s", chapter, chapter_title),
    "",
    sprintf("- Source records: %s–%s", source_record_start, source_record_end),
    sprintf("- Date confidence: %s", date_confidence),
    sprintf("- Boundary confidence: %s", boundary_confidence),
    "",
    text
  ), out, useBytes = TRUE)
})

# Static search index.
chunks <- chapters |>
  select(chapter, chapter_title, approx_start_year, approx_end_year, life_stage, primary_locations,
         source_record_start, source_record_end, text) |>
  mutate(chunk = purrr::map(text, chunk_text)) |>
  select(-text) |>
  tidyr::unnest_longer(chunk, values_to = "text") |>
  group_by(chapter) |>
  mutate(chunk_number = row_number()) |>
  ungroup() |>
  mutate(
    id = sprintf("ch%02d_p%03d", chapter, chunk_number),
    source_label = sprintf("Chapter %02d, passage %03d", chapter, chunk_number),
    excerpt = if_else(nchar(text) > 280, paste0(str_sub(text, 1, 280), "..."), text),
    search_text = normalize_for_search(text)
  ) |>
  select(id, source_label, chapter, chapter_title, chunk_number, approx_start_year, approx_end_year,
         life_stage, primary_locations, source_record_start, source_record_end, text, search_text, excerpt)

readr::write_csv(chunks, "data/processed/passage_index.csv")
jsonlite::write_json(chunks, "data/public/search_index.json", pretty = TRUE, auto_unbox = TRUE)

summary <- list(
  source_file = preferred_source,
  source_records = nrow(records),
  detected_chapter_headings = sum(records$is_heading_record),
  detected_chapters = sort(unique(records$assigned_chapter)),
  narrative_chapters = nrow(chapters),
  search_chunks = nrow(chunks),
  year_candidates = n_years,
  source_warning = source_warning,
  note = "Review chapter_boundary_review.csv, ocr_review.csv, and year_candidates_by_chapter.csv before treating timeline plots as final."
)
jsonlite::write_json(summary, "data/processed/build_summary.json", pretty = TRUE, auto_unbox = TRUE)

message("Prepared corpus from ", preferred_source, ": ", nrow(chapters), " narrative chapters and ", nrow(chunks), " search chunks.")
message(source_warning)
