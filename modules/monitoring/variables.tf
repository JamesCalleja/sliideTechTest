variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, prod)"
}

variable "alert_email" {
  type        = string
  description = "Email address to receive alerts"
  default     = ""
}

variable "sqs_queue_name" {
  type        = string
  description = "Name of the SQS Dead Letter Queue to monitor"
}

variable "kinesis_stream_name" {
  type        = string
  description = "Name of the Kinesis Stream to monitor"
}

variable "lambda_function_name" {
  type        = string
  description = "Name of the Lambda consumer function to monitor"
}

variable "firehose_delivery_stream_name" {
  type        = string
  description = "Name of the Firehose Delivery Stream to monitor"
}
