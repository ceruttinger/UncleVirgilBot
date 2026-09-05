# Basic AWS retrieval Lambda

This is a starter Lambda for the chatbot backend.

## Environment variables

- `CORPUS_BUCKET`: S3 bucket containing the search index.
- `SEARCH_INDEX_KEY`: path to the index, default `data/public/search_index.json`.

## What it does now

- Accepts a POST body like `{ "question": "Tell me about Montevideo" }`.
- Loads `search_index.json` from S3.
- Ranks chunks with simple lexical overlap.
- Returns a retrieval-only answer plus source passages.

## Next backend upgrade

After retrieval works, add one model call:

```text
question + top 5 sources -> model -> answer with chapter citations
```

Keep model API keys in AWS Secrets Manager or Lambda environment variables, never in the Quarto site.
