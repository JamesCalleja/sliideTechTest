output "firehose_arn" {
  value       = aws_kinesis_firehose_delivery_stream.analytics_pipeline.arn
  description = "Kinesis Firehose ARN"
}

output "firehose_name" {
  value       = aws_kinesis_firehose_delivery_stream.analytics_pipeline.name
  description = "Kinesis Firehose Delivery Stream Name"
}

output "glue_database_name" {
  value       = aws_glue_catalog_database.sliide_db.name
  description = "AWS Glue Catalog Database Name"
}

output "glue_table_name" {
  value       = aws_glue_catalog_table.events_table.name
  description = "AWS Glue Catalog Table Name"
}
