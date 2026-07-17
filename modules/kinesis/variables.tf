variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, prod)"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN for encryption at rest"
}

variable "retention_hours" {
  type        = number
  description = "Kinesis stream data retention period in hours"
  default     = 24
}
