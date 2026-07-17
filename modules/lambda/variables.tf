variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, prod)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where Lambda will be deployed"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for Lambda VPC integration"
}

variable "kinesis_stream_arn" {
  type        = string
  description = "Kinesis stream ARN to subscribe to"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN for SQS encryption and decryption"
}
