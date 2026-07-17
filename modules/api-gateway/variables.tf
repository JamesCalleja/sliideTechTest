variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, prod)"
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "kinesis_stream_name" {
  type        = string
  description = "Kinesis Stream Name to write to"
}

variable "kinesis_stream_arn" {
  type        = string
  description = "Kinesis Stream ARN"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN for stream encryption access"
}
