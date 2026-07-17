resource "aws_kinesis_stream" "events_stream" {
  name             = "sliide-events-stream-${var.environment}"
  shard_count      = var.min_shards
  retention_period = var.retention_hours

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  server_side_encryption {
    encryption_type = "KMS"
    key_id          = var.kms_key_arn
  }

  tags = {
    Name        = "sliide-events-stream-${var.environment}"
    Environment = var.environment
  }
}

# Auto-scaling target for Kinesis
resource "aws_appautoscaling_target" "kinesis_target" {
  max_capacity       = var.max_shards
  min_capacity       = var.min_shards
  resource_id        = "stream/${aws_kinesis_stream.events_stream.name}"
  scalable_dimension = "kinesis:stream:WriteProvisionedThroughput"
  service_namespace  = "kinesis"
}

# Auto-scaling policy based on Write Throughput Utilization
resource "aws_appautoscaling_policy" "kinesis_scale_up" {
  name               = "scale-up-kinesis"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.kinesis_target.resource_id
  scalable_dimension = aws_appautoscaling_target.kinesis_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.kinesis_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "KinesisStreamWriteProvisionedThroughput"
    }
    target_value       = 70.0 # Scale out when write throughput utilization hits 70%
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}
