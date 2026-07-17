resource "aws_sns_topic" "alerts" {
  name = "sliide-alerts-topic-${var.environment}"

  tags = {
    Name        = "sliide-alerts-topic-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# 1. SQS DLQ Messages Alarm (Poison Pill Alert)
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "sliide-dlq-messages-alert-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0 # Alert immediately if any message is in DLQ
  alarm_description   = "Alert when messages fail processing and enter the SQS DLQ"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    QueueName = var.sqs_queue_name
  }

  tags = {
    Environment = var.environment
  }
}

# 2. Kinesis Write Throttling Alarm
resource "aws_cloudwatch_metric_alarm" "kinesis_write_throttling" {
  alarm_name          = "sliide-kinesis-write-throttling-alert-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = 60
  statistic           = "Sum"
  threshold           = 5 # Alert if more than 5 throttled records in a minute
  alarm_description   = "Alert when Kinesis stream write throughput is exceeded and throttling occurs"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    StreamName = var.kinesis_stream_name
  }

  tags = {
    Environment = var.environment
  }
}

# 3. Lambda Consumer Iterator Age Alarm (Lag)
resource "aws_cloudwatch_metric_alarm" "lambda_iterator_age" {
  alarm_name          = "sliide-lambda-iterator-age-alert-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "IteratorAge"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Maximum"
  threshold           = 60000 # Alert if processing lag exceeds 60 seconds (60,000 ms)
  alarm_description   = "Alert when Lambda consumer is lagging behind the live Kinesis stream (IteratorAge > 60s)"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  tags = {
    Environment = var.environment
  }
}

# 4. Lambda Execution Error Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "sliide-lambda-errors-alert-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0 # Alert on any error
  alarm_description   = "Alert when Lambda consumer experiences execution errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  tags = {
    Environment = var.environment
  }
}

# 5. Kinesis Firehose S3 Delivery Success Alarm
resource "aws_cloudwatch_metric_alarm" "firehose_delivery_failure" {
  alarm_name          = "sliide-firehose-delivery-failure-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DeliveryToS3.Success"
  namespace           = "AWS/Firehose"
  period              = 60
  statistic           = "Average"
  threshold           = 100 # Alert if success rate is less than 100%
  alarm_description   = "Alert when Kinesis Firehose experiences failures writing to the S3 bucket"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DeliveryStreamName = var.firehose_delivery_stream_name
  }

  tags = {
    Environment = var.environment
  }
}
