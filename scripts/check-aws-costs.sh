#!/usr/bin/env bash
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-default}"
export AWS_REGION="${AWS_REGION:-us-east-2}"
export AWS_PAGER=""

START=$(date +%Y-%m-01)
END=$(date -d tomorrow +%Y-%m-%d)

echo "AWS profile: $AWS_PROFILE"
echo "AWS region:  $AWS_REGION"
echo "Period:      $START to $END"
echo

echo "Month-to-date total cost:"
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --query 'ResultsByTime[0].Total.UnblendedCost.[Amount,Unit]' \
  --output text

echo
echo "Month-to-date cost by service:"
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.UnblendedCost.Amount,Metrics.UnblendedCost.Unit]' \
  --output table
