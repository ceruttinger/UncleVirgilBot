# AWS deployment notes

Recommended MVP architecture:

```text
S3/CloudFront or GitHub Pages: Quarto static site
API Gateway: /ask endpoint
Lambda: retrieval + future model call
S3: search_index.json and processed corpus files
CloudWatch: logs
Secrets Manager: future model API key
```

Initial deployment can skip the backend. The Quarto site already has client-side search and local retrieval.
