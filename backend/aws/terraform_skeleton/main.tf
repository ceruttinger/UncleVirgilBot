terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "corpus" {
  bucket_prefix = "${var.project_name}-corpus-"
}

resource "aws_s3_bucket_public_access_block" "corpus" {
  bucket                  = aws_s3_bucket.corpus.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "lambda_role" {
  name_prefix = "${var.project_name}-lambda-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.corpus.arn}/*"
      }
    ]
  })
}

# Package Lambda manually for now:
#   cd backend/aws/lambda_basic_rag
#   zip -r lambda_basic_rag.zip lambda_function.py
# Then point filename below at that zip.

resource "aws_lambda_function" "rag" {
  function_name = "${var.project_name}-rag"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  filename      = "../lambda_basic_rag/lambda_basic_rag.zip"
  timeout       = 30
  memory_size   = 512

  environment {
    variables = {
      CORPUS_BUCKET      = aws_s3_bucket.corpus.bucket
      SEARCH_INDEX_KEY   = "data/public/search_index.json"
      MODEL_PROVIDER     = "none"
      CORS_ALLOW_ORIGIN  = var.cors_allow_origin
    }
  }
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [var.cors_allow_origin, "http://localhost:4200", "http://127.0.0.1:4200"]
    allow_methods = ["OPTIONS", "POST"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.rag.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ask" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /ask"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rag.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

output "corpus_bucket" {
  value = aws_s3_bucket.corpus.bucket
}

output "ask_endpoint" {
  value = "${aws_apigatewayv2_api.http_api.api_endpoint}/ask"
}
