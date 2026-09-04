# Shared data plane for split app/worker tasks. Compose used named volumes on
# one host. Fargate tasks have separate ephemeral disks, so assessor packs,
# security documents, and branding must live on EFS. In-app Postgres dumps
# go to a private S3 bucket (ALIGNR_BACKUP_DESTINATION=s3://…).

locals {
  storage_environment = [
    { name = "SECURITY_DOCUMENT_STORAGE_DIR", value = "/app/data/security-documents" },
    { name = "ASSESSOR_PACK_STORAGE_DIR", value = "/app/data/assessor-packs" },
    { name = "BRANDING_ASSET_STORAGE_DIR", value = "/app/data/branding-assets" },
    { name = "ALIGNR_BACKUP_DESTINATION", value = "s3://${aws_s3_bucket.backups.id}/nightly" },
    { name = "ALIGNR_HOST_SCANS_ENABLED", value = "true" },
  ]
  data_volume = {
    name = "app-data"
    efsVolumeConfiguration = {
      fileSystemId      = aws_efs_file_system.data.id
      transitEncryption = "ENABLED"
      authorizationConfig = {
        accessPointId = aws_efs_access_point.data.id
        iam           = "ENABLED"
      }
    }
  }
  data_mount = {
    sourceVolume  = "app-data"
    containerPath = "/app/data"
    readOnly      = false
  }
}

resource "aws_security_group" "efs" {
  name        = "${local.name}-efs"
  description = "NFS from COD tasks"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "App and worker to EFS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}

resource "aws_efs_file_system" "data" {
  #checkov:skip=CKV_AWS_184:SSE is enabled; CMK is optional on the lean stack
  encrypted       = true
  throughput_mode = "bursting"
  tags            = { Name = "${local.name}-data" }
}

resource "aws_efs_backup_policy" "data" {
  file_system_id = aws_efs_file_system.data.id
  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_efs_mount_target" "data" {
  count           = 2
  file_system_id  = aws_efs_file_system.data.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "data" {
  file_system_id = aws_efs_file_system.data.id
  posix_user {
    uid = 1001
    gid = 1001
  }
  root_directory {
    path = "/alignr"
    creation_info {
      owner_uid   = 1001
      owner_gid   = 1001
      permissions = "0755"
    }
  }
}

resource "aws_s3_bucket" "backups" {
  #checkov:skip=CKV_AWS_18:Backup bucket; buyer may attach access logs
  #checkov:skip=CKV_AWS_144:Single-region marketplace stack
  #checkov:skip=CKV_AWS_145:SSE-S3 is enough for encrypted Postgres dumps
  bucket        = "${local.name}-${data.aws_caller_identity.current.account_id}-backups"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.backups.arn,
        "${aws_s3_bucket.backups.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.backups]
}

resource "aws_iam_role_policy" "task_storage" {
  name = "${local.name}-storage"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EfsClient"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
        ]
        Resource = aws_efs_file_system.data.arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = aws_efs_access_point.data.arn
          }
        }
      },
      {
        Sid    = "BackupBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*",
        ]
      },
    ]
  })
}
