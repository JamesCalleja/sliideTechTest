module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket        = "sliide-events-${data.aws_caller_identity.current.account_id}-${var.environment}"
  force_destroy = true

  # Encryption
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = var.kms_key_arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  # Block Public Access
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Lifecycle rules
  lifecycle_rule = [
    {
      id      = "archive-and-delete-after-6-months"
      enabled = true

      transition = [
        {
          days          = 90
          storage_class = "GLACIER_IR"
        }
      ]

      expiration = {
        days = 180
      }
    }
  ]

  # Policies
  attach_policy = true
  policy        = data.aws_iam_policy_document.s3_policy.json
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    sid     = "EnforceTLS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::sliide-events-${data.aws_caller_identity.current.account_id}-${var.environment}",
      "arn:aws:s3:::sliide-events-${data.aws_caller_identity.current.account_id}-${var.environment}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_caller_identity" "current" {}
