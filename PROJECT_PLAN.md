# UncleVirgilBot rebuild plan

## Phase 1 — Quarto static MVP

Goal: reproduce the useful parts of the old app without Shiny.

Delivered/stubbed:

- Quarto site scaffold
- chapter metadata table
- cleaned chapter text dataset
- chapter word-count summary
- sentiment-by-chapter page
- NRC/fallback emotion page
- draft timeline page
- browser-based search page
- chatbot shell using local retrieval
- browser-rendered word clouds
- scanned PDF viewer scaffold
- Corpus QA page
- AWS pipeline page
- AWS Lambda/API Gateway scaffold

## Phase 2 — Fix the weak corpus layer

Current issue: the uploaded `corpus_data.json` appears to be generated from already-cleaned text where numbers were removed. That makes exact dates and timeline extraction weak.

Tasks:

1. Copy original `CH-*.rds` files into `data/raw_scans/`.
2. Run `Rscript R/00_rebuild_raw_text_from_rds.R`.
3. Run `Rscript R/render_all.R`.
4. Review `Corpus QA` page.
5. Verify chapter start/end boundaries in `data/processed/chapters/`.
6. Repair OCR artifacts that affect search and analysis.
7. Preserve three layers:
   - raw OCR source
   - lightly cleaned reading text
   - normalized search/analysis text

## Phase 3 — Better digital humanities analysis

Add:

- named entities: people, places, organizations, dates
- entity co-occurrence graph
- life-stage timeline
- topic modeling
- chapter similarity matrix
- keyness analysis by chapter
- readability/style metrics
- institutional narrative tracking: church, Navy, CIA, family, education, geography

## Phase 4 — AWS chatbot backend

Start with retrieval-only:

```text
question -> API Gateway -> Lambda -> S3 search_index.json -> top passages
```

Then add model synthesis:

```text
question + retrieved passages -> model -> answer with chapter citations
```

Recommended model routes:

1. **Bedrock Knowledge Bases** if staying AWS-native and managed.
2. **Custom Lambda + S3 + OpenAI** if you want fast control and strong model quality.
3. **OpenSearch Serverless or Aurora/Postgres pgvector** if you need serious custom retrieval.
4. **Neptune graph** later if the family/place/event network becomes central.

## Phase 5 — Portfolio integration

Options:

1. Host as its own Quarto site in `UncleVirgilBot` repo at `/UncleVirgilBot/`.
2. Render into `/projects/uncle-virgil/` inside `clarkruttinger.info`.
3. Host static site on S3 + CloudFront and link from portfolio.

Recommended first deployment: GitHub Pages from `/docs` for fast iteration.
Recommended production deployment: S3 + CloudFront + API Gateway/Lambda if the chatbot becomes central.
