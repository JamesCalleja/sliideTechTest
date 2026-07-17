# SQS Queue for Dead Letters (Poison-pill payloads)
resource "aws_sqs_queue" "kinesis_dlq" {
  name                      = "sliide-kinesis-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = var.kms_key_arn

  tags = {
    Name        = "sliide-kinesis-dlq-${var.environment}"
    Environment = var.environment
  }
}

# Security Group for Lambda in VPC
resource "aws_security_group" "lambda_sg" {
  name        = "sliide-lambda-sg-${var.environment}"
  description = "Security Group for Lambda Event Consumer"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "sliide-lambda-sg-${var.environment}"
    Environment = var.environment
  }
}

# Lambda Function using AWS Curated Module
module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 6.0"

  function_name = "sliide-event-consumer-${var.environment}"
  description   = "Sliide event consumer lambda"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  memory_size   = 256

  source_path = "${path.module}/src"

  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.lambda_sg.id]
  attach_network_policy  = true

  # Custom IAM policy document to allow Kinesis and DLQ access
  attach_policy_json_strings = true
  policy_json_strings = [
    jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "kinesis:DescribeStream",
            "kinesis:DescribeStreamSummary",
            "kinesis:GetRecords",
            "kinesis:GetShardIterator",
            "kinesis:ListShards",
            "kinesis:ListStreams"
          ]
          Resource = [var.kinesis_stream_arn]
        },
        {
          Effect   = "Allow"
          Action   = ["sqs:SendMessage"]
          Resource = [aws_sqs_queue.kinesis_dlq.arn]
        },
        {
          Effect   = "Allow"
          Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
          Resource = [var.kms_key_arn]
        }
      ]
    })
  ]

  # Trigger integration: subscribe to Kinesis stream
  event_source_mapping = {
    kinesis = {
      event_source_arn  = var.kinesis_stream_arn
      starting_position = "LATEST"
      batch_size        = 100

      destination_config_on_failure = {
        destination_arn = aws_sqs_queue.kinesis_dlq.arn
      }

      maximum_retry_attempts         = 3
      bisect_batch_on_function_error = true
    }
  }

  environment_variables = {
    ENV = var.environment
  }

  tags = {
    Environment = var.environment
  }
}
