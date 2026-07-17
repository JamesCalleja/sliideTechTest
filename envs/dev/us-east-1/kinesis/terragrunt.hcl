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
  source = "../../../../modules/kinesis"
}

dependency "kms" {
  config_path = "../kms"
}

inputs = {
  environment = include.environment.locals.environment
  kms_key_arn = dependency.kms.outputs.key_arn
}
