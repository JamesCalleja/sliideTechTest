#!/bin/bash
set -e

# Configuration
REGION="us-east-1"
USER_NAME="terragrunt-runner"
DYNAMODB_TABLE="sliide-tflocks"
ENVIRONMENT="dev"

echo "=== Sliide Infrastructure Bootstrapping ==="
echo "Retrieving AWS account info..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="sliide-tfstate-${ACCOUNT_ID}-${REGION}"

echo "AWS Account ID:  $ACCOUNT_ID"
echo "Target Region:   $REGION"
echo "S3 State Bucket: $BUCKET_NAME"
echo "DynamoDB Table:  $DYNAMODB_TABLE"
echo "IAM Runner User: $USER_NAME"
echo "----------------------------------------"

# 1. Create S3 Bucket for Terraform State
echo "Creating S3 bucket for Terraform State..."
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION"
else
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

# Block public access to the state bucket
echo "Blocking public access to S3 state bucket..."
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable bucket versioning
echo "Enabling S3 bucket versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Enable default encryption (SSE-S3 / AES256)
echo "Configuring default encryption for S3 state bucket..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

# 2. Create DynamoDB Table for State Locking
echo "Creating DynamoDB table for state locking..."
aws dynamodb create-table \
  --table-name "$DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

# 3. Create IAM User
echo "Creating IAM User ($USER_NAME)..."
aws iam create-user --user-name "$USER_NAME"

# 4. Create and Attach Scoped IAM Policy
echo "Creating granular IAM policy document..."
cat <<EOF > /tmp/sliide_poc_policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StateStorageAndLocks",
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    },
    {
      "Sid": "LocksDynamoDB",
      "Effect": "Allow",
      "Action": [
        "dynamodb:*"
      ],
      "Resource": [
        "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${DYNAMODB_TABLE}"
      ]
    },
    {
      "Sid": "KMSManagement",
      "Effect": "Allow",
      "Action": [
        "kms:CreateKey",
        "kms:DescribeKey",
        "kms:GetKeyPolicy",
        "kms:PutKeyPolicy",
        "kms:CreateAlias",
        "kms:DeleteAlias",
        "kms:UpdateAlias",
        "kms:ListAliases",
        "kms:ListKeys",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VPCNetworkManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:DescribeVpcs",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:DescribeSubnets",
        "ec2:ModifySubnetAttribute",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateVpcEndpoint",
        "ec2:DeleteVpcEndpoint",
        "ec2:DescribeVpcEndpoints",
        "ec2:ModifyVpcEndpoint",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeNetworkInterfaces",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:CreateTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3EventsBucket",
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::sliide-events-${ACCOUNT_ID}-${ENVIRONMENT}",
        "arn:aws:s3:::sliide-events-${ACCOUNT_ID}-${ENVIRONMENT}/*"
      ]
    },
    {
      "Sid": "KinesisStreams",
      "Effect": "Allow",
      "Action": [
        "kinesis:*"
      ],
      "Resource": [
        "arn:aws:kinesis:${REGION}:${ACCOUNT_ID}:stream/sliide-*"
      ]
    },
    {
      "Sid": "KinesisGlobalList",
      "Effect": "Allow",
      "Action": [
        "kinesis:ListStreams",
        "kinesis:ListShards"
      ],
      "Resource": "*"
    },
    {
      "Sid": "APIGateway",
      "Effect": "Allow",
      "Action": [
        "apigateway:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "KinesisFirehose",
      "Effect": "Allow",
      "Action": [
        "firehose:*"
      ],
      "Resource": [
        "arn:aws:firehose:${REGION}:${ACCOUNT_ID}:deliverystream/sliide-*"
      ]
    },
    {
      "Sid": "GlueCatalogSchema",
      "Effect": "Allow",
      "Action": [
        "glue:*"
      ],
      "Resource": [
        "arn:aws:glue:${REGION}:${ACCOUNT_ID}:catalog",
        "arn:aws:glue:${REGION}:${ACCOUNT_ID}:database/sliide_*",
        "arn:aws:glue:${REGION}:${ACCOUNT_ID}:table/sliide_*/*"
      ]
    },
    {
      "Sid": "SQSDLQ",
      "Effect": "Allow",
      "Action": [
        "sqs:*"
      ],
      "Resource": [
        "arn:aws:sqs:${REGION}:${ACCOUNT_ID}:sliide-*"
      ]
    },
    {
      "Sid": "LambdaFunctions",
      "Effect": "Allow",
      "Action": [
        "lambda:*"
      ],
      "Resource": [
        "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:sliide-*"
      ]
    },
    {
      "Sid": "LambdaEventMappings",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateEventSourceMapping",
        "lambda:DeleteEventSourceMapping",
        "lambda:GetEventSourceMapping",
        "lambda:ListEventSourceMappings"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AutoScaling",
      "Effect": "Allow",
      "Action": [
        "application-autoscaling:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchAlarms",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListMetrics",
        "cloudwatch:GetMetricData"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SNSTopics",
      "Effect": "Allow",
      "Action": [
        "sns:*"
      ],
      "Resource": [
        "arn:aws:sns:${REGION}:${ACCOUNT_ID}:sliide-*"
      ]
    },
    {
      "Sid": "IAMRoleManagement",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateRole",
        "iam:PassRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies"
      ],
      "Resource": [
        "arn:aws:iam::${ACCOUNT_ID}:role/sliide-*",
        "arn:aws:iam::${ACCOUNT_ID}:policy/sliide-*"
      ]
    }
  ]
}
EOF

# Create or Update IAM Policy
POLICY_NAME="sliide-poc-runner-policy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "Registering custom IAM policy in AWS Catalog..."
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  echo "Policy already exists. Creating a new default version..."
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document file:///tmp/sliide_poc_policy.json \
    --set-as-default
else
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document file:///tmp/sliide_poc_policy.json
fi

# Attach the policy
echo "Attaching policy to user $USER_NAME..."
aws iam attach-user-policy \
  --user-name "$USER_NAME" \
  --policy-arn "$POLICY_ARN"

# Create Access Keys
echo "Generating Access Keys for $USER_NAME..."
KEYS_JSON=$(aws iam create-access-key --user-name "$USER_NAME")

# Parse access keys using python3 (pre-installed in CloudShell)
ACCESS_KEY_ID=$(echo "$KEYS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
SECRET_ACCESS_KEY=$(echo "$KEYS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")

echo "----------------------------------------"
echo "BOOTSTRAP COMPLETE!"
echo "S3 Bucket:             $BUCKET_NAME"
echo "DynamoDB Lock Table:   $DYNAMODB_TABLE"
echo "IAM User:              $USER_NAME"
echo "IAM Granular Policy:   $POLICY_ARN"
echo "AWS_ACCESS_KEY_ID:     $ACCESS_KEY_ID"
echo "AWS_SECRET_ACCESS_KEY: $SECRET_ACCESS_KEY"
echo "AWS_DEFAULT_REGION:    $REGION"
echo "----------------------------------------"
echo "Run the following commands in your terminal to authenticate as the runner:"
echo ""
echo "export AWS_ACCESS_KEY_ID=\"$ACCESS_KEY_ID\""
echo "export AWS_SECRET_ACCESS_KEY=\"$SECRET_ACCESS_KEY\""
echo "export AWS_DEFAULT_REGION=\"$REGION\""
echo ""
echo "Please save these credentials immediately, as the Secret Access Key cannot be retrieved again."
