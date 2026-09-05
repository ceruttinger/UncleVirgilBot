# Rebuild canonical corpus JSON from raw chapter .rds OCR files.
#
# Use this when you have the original CH-*.rds files. This preserves numbers and
# dates, unlike the old corpus_data.json that appears to have been exported after
# removeNumbers().
#
# Expected input:
#   data/raw_scans/CH-1.rds ... CH-11.rds
# or:
#   data/raw_scans/CH-01.rds ... CH-11.rds
#
# Output:
#   data/raw/corpus_raw_from_rds.json
#   data/processed/source_inventory.csv

library(readr)
library(dplyr)
library(stringr)
library(purrr)
library(jsonlite)
library(tibble)

source("R/utils_text.R")

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

rds_dir <- "data/raw_scans"
rds_files <- list.files(rds_dir, pattern = "^CH[-_ ]?0?([0-9]{1,2})\\.rds$", full.names = TRUE, ignore.case = TRUE)

if (length(rds_files) == 0) {
  stop("No CH-*.rds files found in data/raw_scans/. Copy the chapter RDS files there first.")
}

inventory <- tibble(file = rds_files) |>
  mutate(
    file_name = basename(file),
    chapter = as.integer(str_match(file_name, "(?i)^CH[-_ ]?0?([0-9]{1,2})\\.rds$")[,2])
  ) |>
  filter(!is.na(chapter), chapter >= 1, chapter <= 11) |>
  arrange(chapter)

missing <- setdiff(1:11, inventory$chapter)
if (length(missing) > 0) {
  warning("Missing chapter RDS files for: ", paste(missing, collapse = ", "))
}

records <- inventory |>
  mutate(
    raw_object = map(file, readRDS),
    text = map_chr(raw_object, ~ paste(as.character(.x), collapse = "\n\n") |> clean_ocr_light()),
    word_count = count_words_simple(text),
    char_count = nchar(text),
    source_file = file_name
  ) |>
  select(source_file, chapter, text, word_count, char_count)

readr::write_csv(records |> select(source_file, chapter, word_count, char_count), "data/processed/source_inventory.csv")
jsonlite::write_json(records |> select(text, source_file, chapter), "data/raw/corpus_raw_from_rds.json", pretty = TRUE, auto_unbox = TRUE)

message("Wrote data/raw/corpus_raw_from_rds.json from ", nrow(records), " chapter RDS files.")
message("Now run: Rscript R/render_all.R")
