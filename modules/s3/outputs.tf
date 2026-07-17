output "bucket_arn" {
  value       = module.s3_bucket.s3_bucket_arn
  description = "S3 Bucket ARN"
}

output "bucket_name" {
  value       = module.s3_bucket.s3_bucket_id
  description = "S3 Bucket Name"
}
