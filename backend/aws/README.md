# AWS backend plan for UncleVirgilBot

This backend keeps the public Quarto site simple while moving actual AI answers behind AWS.

## Recommended first production architecture

```text
Quarto static site
  -> API Gateway /ask
  -> Lambda basic RAG
  -> S3 search_index.json
  -> model provider
  -> answer with chapter/passage citations
```

## Why start here

The memoir corpus is small enough that we can begin with the existing `search_index.json` and simple retrieval. That lets us validate UX, citations, costs, and privacy before adding a vector database.

## Security rule

Never put API keys in Quarto, browser JavaScript, GitHub Pages, or any public file. Use AWS Secrets Manager or Lambda environment variables.

## Upgrade paths

### Bedrock Knowledge Bases

Best AWS-native path. Store source documents in S3, let Bedrock handle parsing/chunking/embedding/retrieval, and use `RetrieveAndGenerate` for citation-backed answers.

### OpenSearch Serverless

Use when you want custom embedding pipelines, custom metadata filters, and low-level vector retrieval control.

### Aurora/PostgreSQL with pgvector

Use when you want SQL tables for chapters, passages, entities, relationships, and logs, plus vector search in the same relational database.

### Neptune/graph

Use later if the person/place/organization/event graph becomes central to the user experience.

## Files

```text
lambda_basic_rag/
  lambda_function.py      # minimal Lambda handler
  requirements.txt        # Python dependencies
  sample_event.json       # local test payload

ingest/
  build_bedrock_kb_documents.py
  README.md

terraform_skeleton/
  main.tf
  variables.tf
  README.md
```

## First deploy checklist

1. Create an S3 bucket for processed corpus artifacts.
2. Upload `data/public/search_index.json` to that bucket.
3. Deploy `lambda_basic_rag`.
4. Give Lambda permission to read that object from S3.
5. Create API Gateway route `POST /ask`.
6. Configure CORS for your Quarto domain.
7. Add endpoint URL to `assets/js/chatbot-config.js`.
8. Test a question and verify citations include chapter/passage labels.
