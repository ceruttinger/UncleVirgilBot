message("Rebuilding UncleVirgilBot data products...")

run_if_exists <- function(path) {
  if (file.exists(path)) {
    message("Running ", path)
    source(path, local = FALSE)
  } else {
    message("Skipping missing script: ", path)
  }
}

run_if_exists("R/00_rebuild_raw_text_from_rds.R")
run_if_exists("R/01_prepare_corpus.R")
run_if_exists("R/02_sentiment_analysis.R")
run_if_exists("R/03_build_search_index.R")

# Both names have been used during patch iterations. Run whichever exists.
run_if_exists("R/05_build_word_frequencies.R")
run_if_exists("R/05_wordclouds.R")

run_if_exists("R/06_build_pdf_manifest.R")
run_if_exists("R/07_build_corpus_summary.R")
run_if_exists("R/08_build_timeline_table.R")
run_if_exists("R/09_extract_named_entities.R")

message("Done.")
