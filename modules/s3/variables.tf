variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, prod)"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN for S3 Bucket SSE-KMS"
}
