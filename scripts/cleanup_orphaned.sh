#!/bin/bash
# ----------------------------------------------------------------------------
# cleanup_orphaned.sh
# Use this script if you ran 'teardown.sh' before destroying your Terragrunt
# resources. It directly cleans up all active POC resources using AWS CLI.
# Run this script in AWS CloudShell using administrative console credentials.
# ----------------------------------------------------------------------------
set -e

REGION="us-east-1"
ENVIRONMENT="dev"

echo "=== Sliide POC Orphaned Resources Recovery Cleanup ==="
echo "Retrieving AWS account info..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"
echo "Region:         $REGION"
echo "Environment:    $ENVIRONMENT"
echo "------------------------------------------------------"

# 1. CloudWatch Alarms
echo "Cleaning up CloudWatch Alarms..."
alarms=$(aws cloudwatch describe-alarms --query "MetricAlarms[?starts_with(AlarmName, 'sliide-')].AlarmName" --output text)
if [ ! -z "$alarms" ] && [ "$alarms" != "None" ]; then
  echo "Deleting alarms: $alarms"
  aws cloudwatch delete-alarms --alarm-names $alarms
else
  echo "No CloudWatch alarms found."
fi

# 2. SNS Topics
echo "Cleaning up SNS Topics..."
topics=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'sliide-')].TopicArn" --output text)
for topic in $topics; do
  echo "Deleting SNS Topic: $topic"
  aws sns delete-topic --topic-arn "$topic"
done

# 3. Lambda Event Mappings and Functions
echo "Cleaning up Lambda consumer and triggers..."
mappings=$(aws lambda list-event-source-mappings --query "EventSourceMappings[?contains(FunctionArn, 'sliide-')].UUID" --output text)
for uuid in $mappings; do
  echo "Deleting Lambda event source mapping: $uuid"
  aws lambda delete-event-source-mapping --uuid "$uuid" 2>/dev/null || true
done

if aws lambda get-function --function-name "sliide-event-consumer-${ENVIRONMENT}" >/dev/null 2>&1; then
  echo "Deleting Lambda function..."
  aws lambda delete-function --function-name "sliide-event-consumer-${ENVIRONMENT}"
else
  echo "Lambda function already deleted."
fi

# 4. SQS Dead Letter Queue
echo "Cleaning up SQS Dead Letter Queue..."
queue_url=$(aws sqs get-queue-url --queue-name "sliide-kinesis-dlq-${ENVIRONMENT}" --query QueueUrl --output text 2>/dev/null || echo "")
if [ ! -z "$queue_url" ] && [ "$queue_url" != "None" ]; then
  echo "Deleting SQS queue: $queue_url"
  aws sqs delete-queue --queue-url "$queue_url"
else
  echo "SQS queue not found."
fi

# 5. Kinesis Firehose Delivery Stream
echo "Cleaning up Kinesis Firehose Delivery Stream..."
if aws firehose describe-delivery-stream --delivery-stream-name "sliide-analytics-firehose-${ENVIRONMENT}" >/dev/null 2>&1; then
  echo "Deleting Firehose stream..."
  aws firehose delete-delivery-stream --delivery-stream-name "sliide-analytics-firehose-${ENVIRONMENT}"
else
  echo "Firehose stream already deleted."
fi

# 6. API Gateway REST API
echo "Cleaning up API Gateway REST API..."
api_id=$(aws apigateway get-rest-apis --query "items[?name=='sliide-events-api-${ENVIRONMENT}'].id" --output text)
if [ ! -z "$api_id" ] && [ "$api_id" != "None" ]; then
  echo "Deleting API Gateway: $api_id"
  aws apigateway delete-rest-api --rest-api-id "$api_id"
else
  echo "API Gateway REST API not found."
fi

# 7. Glue Catalog Schema Database
echo "Cleaning up Glue Catalog Database..."
if aws glue get-database --name "sliide_events_db_${ENVIRONMENT}" >/dev/null 2>&1; then
  echo "Deleting Glue Database (cascading tables)..."
  aws glue delete-database --name "sliide_events_db_${ENVIRONMENT}"
else
  echo "Glue Database not found."
fi

# 8. Kinesis Stream
echo "Cleaning up Kinesis Data Stream..."
if aws kinesis describe-stream --stream-name "sliide-events-stream-${ENVIRONMENT}" >/dev/null 2>&1; then
  echo "Deleting Kinesis stream..."
  aws kinesis delete-stream --stream-name "sliide-events-stream-${ENVIRONMENT}"
else
  echo "Kinesis stream already deleted."
fi

# 9. S3 Events Bucket (not state bucket)
bucket_name="sliide-events-${ACCOUNT_ID}-${ENVIRONMENT}"
echo "Checking S3 Events Bucket ($bucket_name)..."
if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
  echo "Emptying versioned S3 Events bucket..."
  python3 -c "import sys, boto3; s3 = boto3.resource('s3'); bucket = s3.Bucket(sys.argv[1]); bucket.object_versions.delete()" "$bucket_name"
  echo "Deleting S3 Events bucket..."
  aws s3api delete-bucket --bucket "$bucket_name" --region "$REGION"
  echo "S3 Events bucket deleted."
else
  echo "S3 Events bucket not found."
fi

# 10. IAM Roles
echo "Cleaning up IAM Roles..."
roles="sliide-apigw-kinesis-role-${ENVIRONMENT} sliide-firehose-role-${ENVIRONMENT} sliide-lambda-consumer-role-${ENVIRONMENT}"
for role in $roles; do
  if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    echo "Processing role: $role"
    # Detach managed policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[].PolicyArn" --output text)
    for policy in $attached_policies; do
      echo "  Detaching policy: $policy"
      aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
    done
    # Delete inline policies
    inline_policies=$(aws iam list-role-policies --role-name "$role" --query "PolicyNames" --output text)
    for policy in $inline_policies; do
      echo "  Deleting inline policy: $policy"
      aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
    done
    # Delete role
    echo "  Deleting role: $role"
    aws iam delete-role --role-name "$role"
  fi
done

# 11. KMS Keys
echo "Cleaning up KMS Aliases and Keys..."
key_id=$(aws kms list-aliases --query "Aliases[?AliasName=='alias/sliide-key-${ENVIRONMENT}'].TargetKeyId" --output text)
if [ ! -z "$key_id" ] && [ "$key_id" != "None" ]; then
  echo "Deleting alias..."
  aws kms delete-alias --alias-name "alias/sliide-key-${ENVIRONMENT}"
  echo "Scheduling KMS Key ($key_id) for deletion..."
  aws kms schedule-key-deletion --key-id "$key_id" --pending-window-in-days 7
else
  echo "KMS Key alias not found."
fi

# 12. VPC & Network Resources (cleanup dependencies in order)
echo "Cleaning up VPC Network resources..."
vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=sliide-vpc-${ENVIRONMENT}" --query "Vpcs[0].VpcId" --output text)
if [ ! -z "$vpc_id" ] && [ "$vpc_id" != "None" ] && [ "$vpc_id" != "null" ]; then
  echo "Found VPC: $vpc_id"

  # Delete VPC Endpoints
  endpoints=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc_id" --query "VpcEndpoints[].VpcEndpointId" --output text)
  for ep in $endpoints; do
    echo "Deleting VPC Endpoint: $ep"
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$ep"
  done
  
  # Sleep to let network interfaces detach completely
  echo "Waiting for ENIs to release (15 seconds)..."
  sleep 15
  
  # Delete Security Groups (except default)
  sgs=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
  for sg in $sgs; do
    echo "Deleting Security Group: $sg"
    aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
  done

  # Delete Subnets
  subnets=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query "Subnets[].SubnetId" --output text)
  for subnet in $subnets; do
    echo "Deleting Subnet: $subnet"
    aws ec2 delete-subnet --subnet-id "$subnet"
  done

  # Delete Route Tables (except main route table)
  rts=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query "RouteTables[?Associations[0].Main!= \`true\`].RouteTableId" --output text)
  for rt in $rts; do
    echo "Deleting Route Table: $rt"
    aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
  done

  # Delete VPC
  echo "Deleting VPC..."
  aws ec2 delete-vpc --vpc-id "$vpc_id"
  echo "VPC deleted successfully."
else
  echo "VPC 'sliide-vpc-dev' not found."
fi

echo "------------------------------------------------------"
echo "ORPHANED RESOURCES CLEANUP COMPLETE!"
