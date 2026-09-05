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

if (file.exists("R/07_build_corpus_summary.R")) {
  source("R/07_build_corpus_summary.R")
}

if (file.exists("R/08_build_timeline_table.R")) {
  source("R/08_build_timeline_table.R")
}

if (file.exists("R/09_extract_named_entities.R")) {
  source("R/09_extract_named_entities.R")
source("R/10_build_entity_graph.R")
source("R/11_clean_graph_tooltips.R")
}

message("Done.")
source("R/12_build_passage_index.R")
