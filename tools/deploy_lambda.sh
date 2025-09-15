#!/usr/bin/env bash
set -euo pipefail

# Idempotent AWS Lambda deploy using AWS CLI (no containers)
# Requires: aws cli, valid AWS credentials, region configured or AWS_REGION set.

FUNCTION_NAME=${FUNCTION_NAME:-dual-nightscout-simple}
AWS_REGION=${AWS_REGION:-us-east-1}
RUNTIME=${RUNTIME:-python3.12}
ARCH=${ARCH:-x86_64}
ROLE_NAME=${ROLE_NAME:-${FUNCTION_NAME}-role}
ZIP_PATH=${ZIP_PATH:-build/lambda.zip}
HANDLER=${HANDLER:-handler.lambda_handler}

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)

if [[ ! -f "$ROOT_DIR/$ZIP_PATH" ]]; then
  echo "[deploy] Package not found at $ZIP_PATH. Run tools/package_lambda.sh first." >&2
  exit 1
fi

echo "[deploy] Using FUNCTION_NAME=$FUNCTION_NAME, REGION=$AWS_REGION, RUNTIME=$RUNTIME, ARCH=$ARCH"

role_arn() {
  aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text --region "$AWS_REGION" 2>/dev/null || true
}

ROLE_ARN=$(role_arn)
if [[ -z "$ROLE_ARN" ]]; then
  echo "[deploy] Creating IAM role $ROLE_NAME ..."
  TRUST=$(cat <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON
)
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST" --region "$AWS_REGION" >/dev/null
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole --region "$AWS_REGION" >/dev/null
  echo "[deploy] Waiting for role to be usable..."
  for i in {1..15}; do
    ROLE_ARN=$(role_arn)
    if [[ -n "$ROLE_ARN" ]]; then break; fi
    sleep 2
  done
fi

fn_exists() {
  aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1
}

if fn_exists; then
  echo "[deploy] Updating function code..."
  aws lambda update-function-code --function-name "$FUNCTION_NAME" --zip-file "fileb://$ROOT_DIR/$ZIP_PATH" --region "$AWS_REGION" >/dev/null
  # Ensure configuration matches desired runtime/arch/handler
  aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --handler "$HANDLER" \
    --architectures "$ARCH" \
    --role "$ROLE_ARN" \
    --region "$AWS_REGION" >/dev/null
else
  echo "[deploy] Creating function..."
  aws lambda create-function \
    --function-name "$FUNCTION_NAME" \
    --runtime "$RUNTIME" \
    --architectures "$ARCH" \
    --role "$ROLE_ARN" \
    --handler "$HANDLER" \
    --timeout 30 \
    --memory-size 512 \
    --zip-file "fileb://$ROOT_DIR/$ZIP_PATH" \
    --region "$AWS_REGION" >/dev/null
fi

# Create Function URL if missing
has_url() {
  aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1
}

if ! has_url; then
  echo "[deploy] Creating public Function URL (no auth)..."
  aws lambda create-function-url-config \
    --function-name "$FUNCTION_NAME" \
    --auth-type NONE \
    --region "$AWS_REGION" >/dev/null
  aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --action lambda:InvokeFunctionUrl \
    --principal "*" \
    --statement-id public-invoke \
    --function-url-auth-type NONE \
    --region "$AWS_REGION" >/dev/null
fi

URL=$(aws lambda get-function-url-config --function-name "$FUNCTION_NAME" --query 'FunctionUrl' --output text --region "$AWS_REGION")
echo "[deploy] Done. Function URL: $URL"
