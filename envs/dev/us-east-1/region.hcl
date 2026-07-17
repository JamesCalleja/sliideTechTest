locals {
  region = "us-east-1"
  bucket = "sliide-tfstate-${get_aws_account_id()}-us-east-1"

  # Networking configurations
  vpc_cidr             = "10.100.0.0/16"
  private_subnet_cidrs = ["10.100.1.0/24", "10.100.2.0/24", "10.100.3.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
