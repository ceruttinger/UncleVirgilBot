# UncleVirgilBot

A Quarto-first rebuild of the Uncle Virgil memoir analysis project.

This repo replaces the old golem/R Shiny app with a static Quarto site plus a future-ready chatbot/search layer.

## What is included

- `data/raw/corpus_data.json` — OCR text exported from the old workflow. Useful, but probably number-stripped.
- `data/chapter_metadata.csv` — starter chapter metadata for timeline and navigation.
- `data/processed/chapter_text.csv` — chapter-split text generated from the OCR corpus.
- `data/processed/chapter_boundary_review.csv` — source-record table for checking chapter splits.
- `data/processed/ocr_review.csv` — rule-based OCR issue list.
- `data/processed/year_candidates_by_chapter.csv` — extracted years if the source text contains them.
- `data/public/search_index.json` — static search chunks for the search/chatbot pages.
- `R/` — scripts to rebuild processed data and analysis tables.
- `backend/aws/` — AWS retrieval/model backend scaffold.
- `legacy/legacy_setup.R` — old pipeline preserved for reference only.

## The biggest current data issue

The old `setup.R` removed numbers during the text-cleaning stage. The uploaded `corpus_data.json` appears to reflect that number-stripped text, so many years and exact dates are missing.

The site can still render and search, but the timeline is provisional until you rebuild the canonical corpus from raw `.rds` OCR files or scanned PDFs.

## Local setup

Install R packages:

```r
install.packages(c(
  "jsonlite", "readr", "dplyr", "tidyr", "stringr", "purrr",
  "ggplot2", "tidytext", "DT", "htmltools", "htmlwidgets", "scales"
))
```

Optional OCR packages, only needed if rebuilding from scanned PDFs:

```r
install.packages(c("pdftools", "tesseract"))
```

## Rebuild from current JSON

```bash
Rscript R/render_all.R
quarto preview
```

## Better: rebuild from raw chapter RDS files

Copy the original chapter RDS files into `data/raw_scans/`:

```text
data/raw_scans/CH-01.rds
data/raw_scans/CH-02.rds
...
data/raw_scans/CH-11.rds
```

Then run:

```bash
Rscript R/00_rebuild_raw_text_from_rds.R
Rscript R/render_all.R
quarto preview
```

## If you only have scanned PDFs

Copy PDFs into `assets/pdf/`:

```text
assets/pdf/CH-01.pdf
assets/pdf/CH-02.pdf
...
assets/pdf/CH-11.pdf
```

Then run:

```bash
Rscript R/00_ocr_scanned_pdfs.R
Rscript R/00_rebuild_raw_text_from_rds.R
Rscript R/render_all.R
quarto preview
```

## Corpus QA

Open the `Corpus QA` tab after rendering. Review:

- detected chapter headings
- source record assignment
- likely title-only records
- OCR issue flags
- year candidates

This is the main place to clean the weak layer before trusting the timeline.

## GitHub Pages path deployment

This starter is configured for a separate repository named `UncleVirgilBot` that can publish at:

```text
https://clarkruttinger.info/UncleVirgilBot/
```

That URL does not need to be linked from the main `clarkruttinger.info` navigation. It is still publicly reachable by anyone who knows or discovers the URL. A `noindex` meta tag is included in `assets/html/noindex.html` to reduce search-engine indexing during development. Remove that include later if this becomes a public portfolio case study.

## Scanned PDFs

To add original scanned chapter PDFs to the site, copy them into `assets/pdf/` and run:

```bash
Rscript R/06_build_pdf_manifest.R
quarto preview
```

Anything in `assets/pdf/` is public when the site is deployed publicly. Use private S3 signed links later if the scans should not be public.

## Word clouds

The rebuild includes browser-rendered word clouds driven by `data/public/word_frequencies.json`. Run this any time the corpus changes:

```bash
Rscript R/05_wordclouds.R
```

## AWS chatbot path

Safe production architecture:

```text
Quarto page -> API Gateway -> Lambda -> S3/Knowledge Base/vector store -> model API
```

First AWS milestone:

```bash
Rscript R/render_all.R
python3 backend/aws/ingest/build_bedrock_kb_documents.py
```

Then upload `data/public/search_index.json` or `data/aws_kb_documents/` to S3 and deploy the Lambda/API Gateway scaffold in `backend/aws/`.

Do not put model keys in the static site.
