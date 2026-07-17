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
  source = "../../../../../modules/vpc"
}

inputs = {
  environment          = include.environment.locals.environment
  region               = include.region.locals.region
  vpc_cidr             = include.region.locals.vpc_cidr
  private_subnet_cidrs = include.region.locals.private_subnet_cidrs
  availability_zones   = include.region.locals.availability_zones
}
