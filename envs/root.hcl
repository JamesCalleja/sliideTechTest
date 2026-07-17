locals {
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment_vars = read_terragrunt_config(find_in_parent_folders("environment.hcl"))
  proposition_vars = read_terragrunt_config(find_in_parent_folders("proposition.hcl"))

  # Define common variables to pass to all modules
  environment = local.environment_vars.locals.environment
  region      = local.region_vars.locals.region
  proposition = local.proposition_vars.locals.proposition
}

# Generate S3 Backend configuration for state storage and locking
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket         = "${local.region_vars.locals.bucket}"
    region         = "${local.region_vars.locals.region}"
    key            = "${local.proposition}/states/${local.environment}/${local.region}/${path_relative_to_include()}.tfstate"
    dynamodb_table = "sliide-tflocks"
  }
}
EOF
}

# Generate standard providers
generate "provider" {
  path      = "provider_generated.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.region}"
  default_tags {
    tags = {
      Environment = "${local.environment}"
      Proposition = "${local.proposition}"
      ManagedBy   = "Terragrunt"
    }
  }
}
EOF
}
