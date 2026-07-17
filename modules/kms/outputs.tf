output "key_arn" {
  value       = module.kms.key_arn
  description = "KMS Key ARN"
}

output "key_id" {
  value       = module.kms.key_id
  description = "KMS Key ID"
}
