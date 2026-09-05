# Ingest pipeline

This folder prepares clean source documents for a future Bedrock Knowledge Base or vector database.

## Local build

```bash
Rscript R/render_all.R
python3 backend/aws/ingest/build_bedrock_kb_documents.py
```

Output:

```text
data/aws_kb_documents/chapter_01.txt
...
data/aws_kb_documents/manifest.jsonl
```

Upload `data/aws_kb_documents/` to the S3 source bucket used by Bedrock Knowledge Bases or your custom vector pipeline.
