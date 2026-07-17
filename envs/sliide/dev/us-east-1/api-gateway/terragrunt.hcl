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
  source = "../../../../../modules/api-gateway"
}

dependency "kms" {
  config_path = "../kms"
}

dependency "kinesis" {
  config_path = "../kinesis"
}

inputs = {
  environment         = include.environment.locals.environment
  region              = include.region.locals.region
  kinesis_stream_name = dependency.kinesis.outputs.stream_name
  kinesis_stream_arn  = dependency.kinesis.outputs.stream_arn
  kms_key_arn         = dependency.kms.outputs.key_arn
}
