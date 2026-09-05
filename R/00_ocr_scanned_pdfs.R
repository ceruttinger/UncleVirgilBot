# Optional: OCR scanned PDFs into chapter .rds files.
#
# This is a safer, repo-relative rewrite of the OCR section in legacy/setup.R.
# It is intentionally separate from the normal render pipeline because OCR is slow
# and needs system libraries plus tesseract language data.
#
# Expected input:
#   assets/pdf/CH-01.pdf ... CH-11.pdf
# Output:
#   data/raw_scans/CH-01.rds ... CH-11.rds
#
# Required R packages: pdftools, tesseract, dplyr, stringr, purrr, readr

library(pdftools)
library(tesseract)
library(dplyr)
library(stringr)
library(purrr)
library(tibble)
library(readr)

source("R/utils_text.R")

dir.create("data/raw_scans", recursive = TRUE, showWarnings = FALSE)
dir.create("data/interim/ocr_pages", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

pdf_files <- list.files("assets/pdf", pattern = "^CH[-_ ]?0?([0-9]{1,2})\\.pdf$", full.names = TRUE, ignore.case = TRUE)
if (length(pdf_files) == 0) {
  stop("No CH-*.pdf files found in assets/pdf/. Copy scanned chapter PDFs there first.")
}

inventory <- tibble(pdf_file = pdf_files) |>
  mutate(
    file_name = basename(pdf_file),
    chapter = as.integer(str_match(file_name, "(?i)^CH[-_ ]?0?([0-9]{1,2})\\.pdf$")[,2])
  ) |>
  filter(!is.na(chapter), chapter >= 1, chapter <= 11) |>
  arrange(chapter)

results <- pmap_dfr(inventory, function(pdf_file, file_name, chapter) {
  message("OCR chapter ", chapter, ": ", file_name)
  page_prefix <- file.path("data/interim/ocr_pages", sprintf("CH-%02d", chapter))
  png_files <- pdftools::pdf_convert(pdf_file, dpi = 400, filenames = paste0(page_prefix, "_%03d.png"))
  page_text <- tesseract::ocr(png_files) |> clean_ocr_light()
  rds_path <- file.path("data/raw_scans", sprintf("CH-%02d.rds", chapter))
  saveRDS(page_text, rds_path)
  tibble(chapter = chapter, pdf_file = file_name, pages = length(png_files), rds_file = basename(rds_path))
})

write_csv(results, "data/processed/ocr_inventory.csv")
message("OCR complete. Next run: Rscript R/00_rebuild_raw_text_from_rds.R")
