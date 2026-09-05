library(jsonlite)
library(readr)
library(dplyr)
library(stringr)

pdf_dir <- file.path("assets", "pdf")
out_dir <- file.path("data", "public")

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

pdfs <- list.files(path = pdf_dir, pattern = "\\.pdf$", full.names = FALSE, ignore.case = TRUE)

chapter_titles <- tibble(
  chapter = 1:11,
  chapter_title = c(
    "Earliest Memories",
    "The Teenage Period",
    "World War 2",
    "My College Years BYU and Colombia",
    "The CIA",
    "Montevideo Uruguay",
    "Headquarters Duty",
    "Rio De Janeiro",
    "The Mclean Va. Years",
    "Making a Career Change",
    "Post Rio to Retirement"
  )
)

manifest <- tibble(file = pdfs) |>
  mutate(
    chapter = as.integer(str_extract(file, "\\d+")),
    url = file.path("assets", "pdf", file)
  ) |>
  left_join(chapter_titles, by = "chapter") |>
  arrange(chapter) |>
  select(chapter, chapter_title, file, url)

readr::write_csv(manifest, file.path(out_dir, "pdf_manifest.csv"))
jsonlite::write_json(manifest, file.path(out_dir, "pdf_manifest.json"), pretty = TRUE, auto_unbox = TRUE)

message("Wrote data/public/pdf_manifest.csv")
message("Wrote data/public/pdf_manifest.json")
