variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, prod)"
}

variable "region" {
  type        = string
  description = "AWS Region"
}

variable "kinesis_stream_arn" {
  type        = string
  description = "Source Kinesis Stream ARN"
}

variable "s3_bucket_arn" {
  type        = string
  description = "Destination S3 Bucket ARN"
}

variable "s3_bucket_name" {
  type        = string
  description = "Destination S3 Bucket Name"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN for decryption/encryption operations"
}
