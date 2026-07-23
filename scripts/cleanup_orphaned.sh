#!/bin/bash
# ----------------------------------------------------------------------------
# cleanup_orphaned.sh
# Use this script if you ran 'teardown.sh' before destroying your Terragrunt
# resources. It directly cleans up all active POC resources using AWS CLI.
# Run this script in AWS CloudShell using administrative console credentials.
# ----------------------------------------------------------------------------
set +e

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
if [ ! -z "$alarms" ] && [ "$alarms" != "None" ] && [ "$alarms" != "null" ]; then
  echo "Deleting alarms: $alarms"
  aws cloudwatch delete-alarms --alarm-names $alarms
else
  echo "No CloudWatch alarms found."
fi

# 2. SNS Topics
echo "Cleaning up SNS Topics..."
topics=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'sliide-')].TopicArn" --output text)
for topic in $topics; do
  if [ "$topic" != "None" ] && [ ! -z "$topic" ]; then
    echo "Deleting SNS Topic: $topic"
    aws sns delete-topic --topic-arn "$topic"
  fi
done

# 3. Lambda Event Mappings and Functions
echo "Cleaning up Lambda consumer and triggers..."
mappings=$(aws lambda list-event-source-mappings --query "EventSourceMappings[?contains(FunctionArn, 'sliide-')].UUID" --output text)
for uuid in $mappings; do
  if [ "$uuid" != "None" ] && [ ! -z "$uuid" ]; then
    echo "Deleting Lambda event source mapping: $uuid"
    aws lambda delete-event-source-mapping --uuid "$uuid" 2>/dev/null || true
  fi
done

# Delete Lambda function by prefix
functions=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'sliide-')].FunctionName" --output text)
for func in $functions; do
  if [ "$func" != "None" ] && [ ! -z "$func" ]; then
    echo "Deleting Lambda function: $func"
    aws lambda delete-function --function-name "$func" 2>/dev/null || true
  fi
done

# 4. SQS Dead Letter Queue
echo "Cleaning up SQS queues..."
queues=$(aws sqs list-queues --queue-name-prefix "sliide-" --query "QueueUrls" --output text 2>/dev/null || echo "")
for queue in $queues; do
  if [ "$queue" != "None" ] && [ ! -z "$queue" ]; then
    echo "Deleting SQS queue: $queue"
    aws sqs delete-queue --queue-url "$queue" 2>/dev/null || true
  fi
done

# 5. Kinesis Firehose Delivery Stream
echo "Cleaning up Kinesis Firehose Delivery Streams..."
streams=$(aws firehose list-delivery-streams --query "DeliveryStreamNames[?starts_with(@, 'sliide-')]" --output text)
for stream in $streams; do
  if [ "$stream" != "None" ] && [ ! -z "$stream" ]; then
    echo "Deleting Firehose stream: $stream"
    aws firehose delete-delivery-stream --delivery-stream-name "$stream" 2>/dev/null || true
  fi
done

# 6. API Gateway REST API
echo "Cleaning up API Gateway REST APIs..."
apis=$(aws apigateway get-rest-apis --query "items[?starts_with(name, 'sliide-')].id" --output text)
for api_id in $apis; do
  if [ ! -z "$api_id" ] && [ "$api_id" != "None" ]; then
    echo "Deleting API Gateway: $api_id"
    aws apigateway delete-rest-api --rest-api-id "$api_id" 2>/dev/null || true
  fi
done

# 7. Glue Catalog Schema Database
echo "Cleaning up Glue Catalog Database..."
if aws glue get-database --name "sliide_events_db_${ENVIRONMENT}" >/dev/null 2>&1; then
  echo "Deleting Glue Database (cascading tables)..."
  aws glue delete-database --name "sliide_events_db_${ENVIRONMENT}"
else
  echo "Glue Database not found."
fi

# 8. Kinesis Stream & Auto-Scaling Target
echo "Cleaning up Kinesis Streams & Scaling Targets..."
# Deregister scaling targets if any
aws application-autoscaling deregister-scalable-target \
  --service-namespace kinesis \
  --scalable-dimension kinesis:stream:WriteProvisionedThroughput \
  --resource-id "stream/sliide-events-stream-${ENVIRONMENT}" 2>/dev/null || true

streams=$(aws kinesis list-streams --query "StreamNames[?starts_with(@, 'sliide-')]" --output text)
for stream in $streams; do
  if [ "$stream" != "None" ] && [ ! -z "$stream" ]; then
    echo "Deleting Kinesis stream: $stream"
    aws kinesis delete-stream --stream-name "$stream" 2>/dev/null || true
  fi
done

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

# 10. WAFv2 Web ACLs
echo "Cleaning up WAFv2 Web ACLs..."
web_acls=$(aws wafv2 list-web-acls --scope REGIONAL --query "WebACLs[?starts_with(Name, 'sliide-')]" --output json)
count=$(echo "$web_acls" | jq '. | length')
if [ "$count" -gt 0 ]; then
  for i in $(seq 0 $((count - 1))); do
    acl_name=$(echo "$web_acls" | jq -r ".[$i].Name")
    acl_id=$(echo "$web_acls" | jq -r ".[$i].Id")
    lock_token=$(echo "$web_acls" | jq -r ".[$i].LockToken")
    echo "Deleting WAFv2 Web ACL: $acl_name ($acl_id)"
    aws wafv2 delete-web-acl --name "$acl_name" --scope REGIONAL --id "$acl_id" --lock-token "$lock_token" 2>/dev/null || true
  done
else
  echo "No Sliide WAFv2 Web ACLs found."
fi

# 11. IAM Roles (using dynamic query to support suffixes)
echo "Cleaning up IAM Roles..."
roles=$(aws iam list-roles --query "Roles[?starts_with(RoleName, 'sliide-')].RoleName" --output text)
for role in $roles; do
  if [ "$role" != "None" ] && [ ! -z "$role" ]; then
    echo "Processing role: $role"
    # Detach managed policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[].PolicyArn" --output text)
    for policy in $attached_policies; do
      echo "  Detaching policy: $policy"
      aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null || true
    done
    # Delete inline policies
    inline_policies=$(aws iam list-role-policies --role-name "$role" --query "PolicyNames" --output text)
    for policy in $inline_policies; do
      echo "  Deleting inline policy: $policy"
      aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
    done
    # Delete role
    echo "  Deleting role: $role"
    aws iam delete-role --role-name "$role" 2>/dev/null || true
  fi
done

# 12. Custom IAM Policies (using dynamic query to support suffixes)
echo "Cleaning up Custom IAM Policies..."
policies=$(aws iam list-policies --scope Local --query "Policies[?starts_with(PolicyName, 'sliide-')].Arn" --output text)
for policy in $policies; do
  if [ "$policy" != "None" ] && [ ! -z "$policy" ]; then
    echo "Processing policy: $policy"
    # Delete non-default versions first
    versions=$(aws iam list-policy-versions --policy-arn "$policy" --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text)
    for ver in $versions; do
      echo "  Deleting non-default policy version: $ver"
      aws iam delete-policy-version --policy-arn "$policy" --version-id "$ver" 2>/dev/null || true
    done
    # Delete policy
    echo "  Deleting policy..."
    aws iam delete-policy --policy-arn "$policy" 2>/dev/null || true
  fi
done

# 13. KMS Keys (using starts_with prefix query for suffixes)
echo "Cleaning up KMS Aliases and Keys..."
aliases=$(aws kms list-aliases --query "Aliases[?starts_with(AliasName, 'alias/sliide-key-${ENVIRONMENT}')]" --output json)
count=$(echo "$aliases" | jq '. | length')
if [ "$count" -gt 0 ]; then
  for i in $(seq 0 $((count - 1))); do
    alias_name=$(echo "$aliases" | jq -r ".[$i].AliasName")
    key_id=$(echo "$aliases" | jq -r ".[$i].TargetKeyId")
    echo "Deleting KMS Alias: $alias_name"
    aws kms delete-alias --alias-name "$alias_name" 2>/dev/null || true
    echo "Scheduling KMS Key ($key_id) for deletion..."
    aws kms schedule-key-deletion --key-id "$key_id" --pending-window-in-days 7 2>/dev/null || true
  done
else
  echo "No Sliide KMS Key aliases found."
fi

# 14. VPC & Network Resources (cleanup dependencies in order)
echo "Cleaning up VPC Network resources..."
vpcs=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=sliide-vpc-${ENVIRONMENT}" --query "Vpcs[].VpcId" --output text)
for vpc_id in $vpcs; do
  if [ ! -z "$vpc_id" ] && [ "$vpc_id" != "None" ] && [ "$vpc_id" != "null" ]; then
    echo "Found VPC: $vpc_id"

    # Delete VPC Endpoints
    endpoints=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc_id" --query "VpcEndpoints[].VpcEndpointId" --output text)
    for ep in $endpoints; do
      echo "Deleting VPC Endpoint: $ep"
      aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$ep" 2>/dev/null || true
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
      aws ec2 delete-subnet --subnet-id "$subnet" 2>/dev/null || true
    done

    # Delete Route Tables (except main route table)
    rts=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query "RouteTables[?Associations[0].Main!= \`true\`].RouteTableId" --output text)
    for rt in $rts; do
      echo "Deleting Route Table: $rt"
      aws ec2 delete-route-table --route-table-id "$rt" 2>/dev/null || true
    done

    # Delete VPC
    echo "Deleting VPC..."
    aws ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null || true
    echo "VPC deleted successfully."
  fi
done

echo "------------------------------------------------------"
echo "ORPHANED RESOURCES CLEANUP COMPLETE!"
