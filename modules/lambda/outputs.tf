output "lambda_function_arn" {
  value       = module.lambda_function.lambda_function_arn
  description = "Event Consumer Lambda function ARN"
}

output "lambda_function_name" {
  value       = module.lambda_function.lambda_function_name
  description = "Event Consumer Lambda function Name"
}

output "dlq_queue_url" {
  value       = aws_sqs_queue.kinesis_dlq.id
  description = "Kinesis processing DLQ URL"
}

output "dlq_queue_name" {
  value       = aws_sqs_queue.kinesis_dlq.name
  description = "Kinesis processing DLQ Name"
}
