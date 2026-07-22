#!/bin/bash
set -e

# Configuration
REGION="us-east-1"
USER_NAME="terragrunt-runner"
DYNAMODB_TABLE="sliide-tflocks"
POLICY_NAME="sliide-poc-runner-policy"

echo "=== Sliide Infrastructure Teardown ==="
echo "Retrieving AWS account info..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="sliide-tfstate-${ACCOUNT_ID}-${REGION}"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "AWS Account ID:  $ACCOUNT_ID"
echo "Target Region:   $REGION"
echo "S3 State Bucket: $BUCKET_NAME"
echo "DynamoDB Table:  $DYNAMODB_TABLE"
echo "IAM Runner User: $USER_NAME"
echo "IAM Policy:      $POLICY_ARN"
echo "----------------------------------------"

# 1. Empty and Delete S3 State Bucket
echo "Checking S3 state bucket..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Emptying S3 bucket (deleting all object versions and delete markers)..."
  python3 -c "import sys, boto3; s3 = boto3.resource('s3'); bucket = s3.Bucket(sys.argv[1]); bucket.object_versions.delete()" "$BUCKET_NAME"
  
  echo "Deleting S3 bucket..."
  aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$REGION"
  echo "S3 Bucket deleted successfully."
else
  echo "S3 bucket does not exist. Skipping."
fi

# 2. Delete DynamoDB table for State Locking
echo "Checking DynamoDB table..."
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "Deleting DynamoDB table..."
  aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" --region "$REGION"
  echo "Waiting for DynamoDB table to be deleted..."
  aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE" --region "$REGION"
  echo "DynamoDB table deleted successfully."
else
  echo "DynamoDB table does not exist. Skipping."
fi

# 3. Clean up IAM User (Access Keys and Policy Associations)
echo "Checking IAM user..."
if aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1; then
  # Detach policy from user
  echo "Detaching policy from IAM user..."
  aws iam detach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true

  # Delete access keys associated with user
  echo "Checking for access keys..."
  KEYS=$(aws iam list-access-keys --user-name "$USER_NAME" --query "AccessKeyMetadata[].AccessKeyId" --output text)
  for key in $KEYS; do
    echo "Deleting access key: $key"
    aws iam delete-access-key --user-name "$USER_NAME" --access-key-id "$key"
  done

  # Delete user
  echo "Deleting IAM user..."
  aws iam delete-user --user-name "$USER_NAME"
  echo "IAM user deleted successfully."
else
  echo "IAM user does not exist. Skipping."
fi

# 4. Delete Custom IAM Policy
echo "Checking IAM policy..."
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  # Delete non-default policy versions first
  echo "Checking for non-default policy versions..."
  VERSIONS=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text)
  for version in $VERSIONS; do
    echo "Deleting policy version: $version"
    aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$version"
  done

  echo "Deleting IAM policy..."
  aws iam delete-policy --policy-arn "$POLICY_ARN"
  echo "IAM policy deleted successfully."
else
  echo "IAM policy does not exist. Skipping."
fi

# 5. Clean up local Terragrunt cache directories
echo "Checking for local .terragrunt-cache directories to delete..."
# Search and delete only if we are in the repository root or subfolders
if [ -d "envs" ] || [ -d "modules" ] || [ -d "../envs" ]; then
  echo "Deleting .terragrunt-cache directories..."
  find . -type d -name ".terragrunt-cache" -prune -exec rm -rf {} + 2>/dev/null || true
  echo "Local cache directories deleted."
else
  echo "Not in repository directory structure. Skipping cache deletion."
fi

echo "----------------------------------------"
echo "TEARDOWN COMPLETE!"
echo "All bootstrapped resources have been removed."
