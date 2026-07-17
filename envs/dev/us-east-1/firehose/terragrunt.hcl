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
  source = "../../../../modules/firehose"
}

dependency "kms" {
  config_path = "../kms"
}

dependency "kinesis" {
  config_path = "../kinesis"
}

dependency "s3" {
  config_path = "../s3"
}

inputs = {
  environment        = include.environment.locals.environment
  region             = include.region.locals.region
  kinesis_stream_arn = dependency.kinesis.outputs.stream_arn
  s3_bucket_arn      = dependency.s3.outputs.bucket_arn
  s3_bucket_name     = dependency.s3.outputs.bucket_name
  kms_key_arn        = dependency.kms.outputs.key_arn
}
