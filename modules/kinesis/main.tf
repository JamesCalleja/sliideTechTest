resource "aws_kinesis_stream" "events_stream" {
  name             = "sliide-events-stream-${var.environment}"
  retention_period = var.retention_hours

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  tags = {
    Name        = "sliide-events-stream-${var.environment}"
    Environment = var.environment
  }
}
