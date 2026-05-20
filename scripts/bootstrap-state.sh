#!/usr/bin/env bash
# bootstrap-state.sh — One-time setup for Terraform remote state backend.
# Creates the S3 bucket and DynamoDB table used by all environments.
# Safe to run multiple times (idempotent).
#
# Usage:
#   ./scripts/bootstrap-state.sh
#   ./scripts/bootstrap-state.sh --region eu-west-1
#
# After running, update backend.tf in each environment with the bucket name printed below.

set -euo pipefail

# --- Configuration ---
REGION="eu-central-1"
DYNAMO_TABLE="petclinic-terraform-locks"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--region <region>]"
      exit 1
      ;;
  esac
done

# Derive bucket name from account ID (unique per account)
echo "Fetching AWS account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region "${REGION}")
BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"

echo ""
echo "========================================"
echo "  Terraform State Bootstrap"
echo "  Region:  ${REGION}"
echo "  Account: ${ACCOUNT_ID}"
echo "  Bucket:  ${BUCKET_NAME}"
echo "  Table:   ${DYNAMO_TABLE}"
echo "========================================"
echo ""

# --- S3 Bucket ---
echo "Creating S3 bucket: ${BUCKET_NAME}"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null; then
  echo "  Bucket already exists — skipping creation."
else
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
  echo "  Bucket created."
fi

echo "  Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

echo "  Enabling server-side encryption (AES256)..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'

echo "  Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "  S3 bucket ready."
echo ""

# --- DynamoDB Table ---
echo "Creating DynamoDB table: ${DYNAMO_TABLE}"

TABLE_STATUS=$(aws dynamodb describe-table \
  --table-name "${DYNAMO_TABLE}" \
  --region "${REGION}" \
  --query 'Table.TableStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "${TABLE_STATUS}" == "ACTIVE" ]]; then
  echo "  Table already exists — skipping creation."
else
  aws dynamodb create-table \
    --table-name "${DYNAMO_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  echo "  Waiting for table to become active..."
  aws dynamodb wait table-exists \
    --table-name "${DYNAMO_TABLE}" \
    --region "${REGION}"
  echo "  Table ready."
fi

echo ""
echo "========================================"
echo "  Bootstrap complete!"
echo ""
echo "  Next steps:"
echo "  1. Update backend.tf in each environment:"
echo "     Replace ACCOUNT_ID with: ${ACCOUNT_ID}"
echo ""
echo "     terraform/environments/dev/backend.tf"
echo "     terraform/environments/prod/backend.tf"
echo ""
echo "  2. Run terraform init in each environment:"
echo "     cd terraform/environments/dev && terraform init"
echo "     cd terraform/environments/prod && terraform init"
echo "========================================"
