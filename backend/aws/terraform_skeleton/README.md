# Terraform skeleton

This is a starting point, not a one-command production deploy. Fill in bucket names, region, and your preferred model path.

Recommended early path:

1. Create an S3 bucket for processed corpus artifacts.
2. Upload `data/public/search_index.json`.
3. Package and deploy the Lambda in `backend/aws/lambda_basic_rag`.
4. Put API Gateway in front of Lambda.
5. Configure CORS for `https://clarkruttinger.info` and local preview during development.

For production privacy, do not make the corpus bucket public.
