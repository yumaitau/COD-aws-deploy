locals {
  sbom_cli_files = {
    "cod-sbom-darwin-arm64"       = "application/octet-stream"
    "cod-sbom-darwin-amd64"       = "application/octet-stream"
    "cod-sbom-windows-amd64.exe"  = "application/octet-stream"
  }
  sbom_cli_dir = var.sbom_cli_artifact_dir != "" ? var.sbom_cli_artifact_dir : "${path.module}/sbom-cli"
  sbom_cli_objects = {
    for name, type in local.sbom_cli_files : name => type
    if fileexists("${local.sbom_cli_dir}/${name}")
  }
  sbom_cli_environment = [
    { name = "SBOM_CLI_S3_BUCKET", value = aws_s3_bucket.sbom_cli.id },
    { name = "SBOM_CLI_DOWNLOAD_BASE", value = "https://${aws_s3_bucket.sbom_cli.bucket}.s3.${var.aws_region}.amazonaws.com" },
  ]
}

# Signed COD SBOM CLI binaries. The Marketplace image deletes public/downloads,
# so the app fetches them from this bucket (IAM GetObject after the next image,
# HTTP GET on /sbom-cli/* for images that only know SBOM_CLI_DOWNLOAD_BASE).
resource "aws_s3_bucket" "sbom_cli" {
  #checkov:skip=CKV_AWS_18:Artifact bucket; access logs are optional for buyer-hosted binaries
  #checkov:skip=CKV_AWS_144:Single-region marketplace stack; CRR is a buyer DR choice
  #checkov:skip=CKV_AWS_145:SSE-S3 is enough for public signed CLI binaries
  bucket        = "${local.name}-${data.aws_caller_identity.current.account_id}-sbom-cli"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "sbom_cli" {
  #checkov:skip=CKV_AWS_53:HTTP GET on /sbom-cli/* is required for Marketplace images that only fetch SBOM_CLI_DOWNLOAD_BASE
  #checkov:skip=CKV_AWS_54:HTTP GET on /sbom-cli/* is required for Marketplace images that only fetch SBOM_CLI_DOWNLOAD_BASE
  #checkov:skip=CKV_AWS_55:HTTP GET on /sbom-cli/* is required for Marketplace images that only fetch SBOM_CLI_DOWNLOAD_BASE
  #checkov:skip=CKV_AWS_56:HTTP GET on /sbom-cli/* is required for Marketplace images that only fetch SBOM_CLI_DOWNLOAD_BASE
  bucket                  = aws_s3_bucket.sbom_cli.id
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_versioning" "sbom_cli" {
  bucket = aws_s3_bucket.sbom_cli.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sbom_cli" {
  bucket = aws_s3_bucket.sbom_cli.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "sbom_cli" {
  bucket = aws_s3_bucket.sbom_cli.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sbom_cli" {
  bucket = aws_s3_bucket.sbom_cli.id
  rule {
    id     = "abort-incomplete"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "sbom_cli" {
  bucket = aws_s3_bucket.sbom_cli.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.sbom_cli.arn,
          "${aws_s3_bucket.sbom_cli.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "SbomCliPublicGet"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.sbom_cli.arn}/sbom-cli/*"
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.sbom_cli]
}

resource "aws_s3_object" "sbom_cli" {
  for_each     = local.sbom_cli_objects
  bucket       = aws_s3_bucket.sbom_cli.id
  key          = "sbom-cli/${each.key}"
  source       = "${local.sbom_cli_dir}/${each.key}"
  etag         = filemd5("${local.sbom_cli_dir}/${each.key}")
  content_type = each.value
}

resource "aws_iam_role_policy" "task_sbom_cli" {
  name = "${local.name}-sbom-cli"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SbomCliGet"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.sbom_cli.arn, "${aws_s3_bucket.sbom_cli.arn}/sbom-cli/*"]
    }]
  })
}
