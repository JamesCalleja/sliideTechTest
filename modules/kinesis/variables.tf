variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, prod)"
}

variable "kms_key_arn" {
  type        = string
  description = "KMS Key ARN for encryption at rest"
}

variable "min_shards" {
  type        = number
  description = "Minimum number of Kinesis shards"
  default     = 50
}

variable "max_shards" {
  type        = number
  description = "Maximum number of Kinesis shards"
  default     = 600
}

variable "retention_hours" {
  type        = number
  description = "Kinesis stream data retention period in hours"
  default     = 24
}

variable "scale_out_cooldown" {
  type        = number
  description = "Cooldown period in seconds before scaling out"
  default     = 60
}

variable "scale_in_cooldown" {
  type        = number
  description = "Cooldown period in seconds before scaling in"
  default     = 300
}
