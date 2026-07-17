include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "environment" {
  path   = find_in_parent_folders("environment.hcl")
  expose = true
}

include "region" {
  path   = find_in_parent_folders("region.hcl")
  expose = true
}

terraform {
  source = "../../../../../modules/monitoring"
}

dependency "kinesis" {
  config_path = "../kinesis"
}

dependency "lambda" {
  config_path = "../lambda"
}

dependency "firehose" {
  config_path = "../firehose"
}

inputs = {
  environment                   = include.environment.locals.environment
  alert_email                   = "devops-alerts@sliide.com" # Placeholder alert email
  kinesis_stream_name           = dependency.kinesis.outputs.stream_name
  lambda_function_name          = dependency.lambda.outputs.lambda_function_name
  sqs_queue_name                = dependency.lambda.outputs.dlq_queue_name
  firehose_delivery_stream_name = dependency.firehose.outputs.firehose_name
}
