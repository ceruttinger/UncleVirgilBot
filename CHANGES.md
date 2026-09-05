# UncleVirgilBot patch v3

## Data/corpus layer

- Adds `Corpus QA` page.
- Adds record-level chapter assignment review.
- Adds OCR issue review table.
- Adds year-candidate extraction table.
- Adds safer corpus preparation that prefers `data/raw/corpus_raw_from_rds.json` if available.
- Adds scripts to rebuild canonical text from raw `CH-*.rds` files or OCR scanned PDFs.
- Updates chapter metadata with boundary/timeline review status.

## AWS/model layer

- Adds `AWS Pipeline` page.
- Adds `backend/aws/README.md`.
- Adds `lambda_basic_rag` AWS Lambda scaffold.
- Adds ingest helper for Bedrock Knowledge Base/source documents.
- Adds Terraform skeleton for S3 + Lambda + API Gateway.
- Updates chatbot config so the static site can later point at API Gateway without exposing keys.

## Important finding

The current `corpus_data.json` appears to be number-stripped. The QA outputs found zero 4-digit year candidates. Rebuild from raw RDS or PDFs before relying on timeline analysis.
