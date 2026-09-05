library(readr)
library(dplyr)
library(stringr)

chapter_path <- "data/processed/chapter_text.csv"

if (!file.exists(chapter_path)) {
  message("data/processed/chapter_text.csv not found. Trying R/01_prepare_corpus.R first...")
  if (file.exists("R/01_prepare_corpus.R")) {
    source("R/01_prepare_corpus.R")
  }
}

if (!file.exists(chapter_path)) {
  stop("Could not find data/processed/chapter_text.csv. Run Rscript R/01_prepare_corpus.R first.")
}

chapters <- readr::read_csv(chapter_path, show_col_types = FALSE)

if (!"chapter" %in% names(chapters)) {
  stop("chapter_text.csv is missing a 'chapter' column.")
}

if (!"text" %in% names(chapters)) {
  stop("chapter_text.csv is missing a 'text' column.")
}

if (!"chapter_title" %in% names(chapters)) {
  chapters$chapter_title <- paste("Chapter", chapters$chapter)
}

extract_years <- function(x) {
  if (is.na(x) || !nzchar(x)) return(character())
  yrs <- stringr::str_extract_all(x, "\\b(?:18|19|20)\\d{2}\\b")[[1]]
  unique(yrs)
}

source_used <- dplyr::case_when(
  file.exists("data/raw/corpus_raw_from_rds.json") ~ "data/raw/corpus_raw_from_rds.json",
  file.exists("data/raw/corpus_data.json") ~ "data/raw/corpus_data.json",
  file.exists("corpus_data.json") ~ "corpus_data.json",
  TRUE ~ "unknown"
)

rds_count <- if (dir.exists("data/raw_scans")) {
  length(list.files("data/raw_scans", pattern = "^CH-[0-9]+\\.rds$", ignore.case = TRUE))
} else {
  0L
}

pdf_count <- if (dir.exists("assets/pdf")) {
  length(list.files("assets/pdf", pattern = "^CH-[0-9]+\\.pdf$", ignore.case = TRUE))
} else {
  0L
}

summary <- chapters |>
  mutate(
    text = if_else(is.na(text), "", text),
    word_count = stringr::str_count(text, "\\S+"),
    char_count = nchar(text),
    year_candidates = vapply(text, function(x) paste(head(extract_years(x), 30), collapse = "; "), character(1)),
    year_count = vapply(text, function(x) length(extract_years(x)), integer(1)),
    source_used = source_used,
    rds_file_count = rds_count,
    pdf_file_count = pdf_count,
    likely_empty = word_count < 50,
    likely_tiny = word_count < 500,
    needs_review = likely_empty | likely_tiny | year_count == 0
  ) |>
  select(
    chapter,
    chapter_title,
    word_count,
    char_count,
    year_count,
    year_candidates,
    likely_empty,
    likely_tiny,
    needs_review,
    source_used,
    rds_file_count,
    pdf_file_count
  ) |>
  arrange(chapter)

readr::write_csv(summary, "data/processed/corpus_build_summary.csv")
readr::write_csv(summary, "data/public/corpus_build_summary.csv")

message("Wrote data/processed/corpus_build_summary.csv")
message("Wrote data/public/corpus_build_summary.csv")
