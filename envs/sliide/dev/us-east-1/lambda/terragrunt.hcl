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
  source = "../../../../../modules/lambda"
}

dependency "kms" {
  config_path = "../kms"
}

dependency "vpc" {
  config_path = "../vpc"
}

dependency "kinesis" {
  config_path = "../kinesis"
}

inputs = {
  environment        = include.environment.locals.environment
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids
  kinesis_stream_arn = dependency.kinesis.outputs.stream_arn
  kms_key_arn        = dependency.kms.outputs.key_arn
}
