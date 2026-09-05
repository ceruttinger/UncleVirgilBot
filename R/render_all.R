message("Rebuilding UncleVirgilBot data products...")

if (file.exists("R/00_rebuild_raw_text_from_rds.R")) {
  source("R/00_rebuild_raw_text_from_rds.R")
}

source("R/01_prepare_corpus.R")
source("R/02_sentiment_analysis.R")
source("R/03_build_search_index.R")

if (file.exists("R/05_build_word_frequencies.R")) {
  source("R/05_build_word_frequencies.R")
}

if (file.exists("R/06_build_pdf_manifest.R")) {
  source("R/06_build_pdf_manifest.R")
}

message("Done.")
