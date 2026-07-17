module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.1"

  description             = "KMS Key for Sliide events pipeline"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  aliases                 = ["sliide-key-${var.environment}"]

  key_owners = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]

  key_statements = [
    {
      sid    = "Allow Key Usage for CloudWatch/Kinesis/Firehose"
      effect = "Allow"
      principals = [{
        type        = "Service"
        identifiers = [
          "kinesis.amazonaws.com",
          "delivery.logs.amazonaws.com",
          "firehose.amazonaws.com",
          "lambda.amazonaws.com"
        ]
      }]
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
    }
  ]

  tags = {
    Environment = var.environment
  }
}

data "aws_caller_identity" "current" {}
