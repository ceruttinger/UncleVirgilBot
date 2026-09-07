#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-default}"
export AWS_REGION="${AWS_REGION:-us-east-2}"
export AWS_PAGER=""

echo "Logging into AWS SSO profile: $AWS_PROFILE"
aws sso login --profile "$AWS_PROFILE"

echo
echo "Verifying AWS identity..."
aws sts get-caller-identity --profile "$AWS_PROFILE"
