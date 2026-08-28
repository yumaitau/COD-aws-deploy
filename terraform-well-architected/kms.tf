data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_elb_service_account" "current" {}

resource "aws_kms_key" "this" {
  description             = "Compliance on Demand customer-managed key for RDS, Redis, Secrets, and logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIamUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
    ]
  })
  tags = { Name = "${local.name}-cmk" }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}-runtime"
  target_key_id = aws_kms_key.this.key_id
}
