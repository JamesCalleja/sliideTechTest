output "stream_arn" {
  value       = aws_kinesis_stream.events_stream.arn
  description = "Kinesis Stream ARN"
}

output "stream_name" {
  value       = aws_kinesis_stream.events_stream.name
  description = "Kinesis Stream Name"
}
