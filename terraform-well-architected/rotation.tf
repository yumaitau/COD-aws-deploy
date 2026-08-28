data "archive_file" "rotate" {
  type        = "zip"
  source_file = "${path.module}/rotate.py"
  output_path = "${path.module}/rotate.zip"
}

resource "aws_sqs_queue" "rotate_dlq" {
  name                      = "${local.name}-rotate-dlq"
  kms_master_key_id         = aws_kms_key.this.id
  message_retention_seconds = 1209600
}

resource "aws_cloudwatch_log_group" "rotate" {
  name              = "/aws/lambda/${local.name}-rotate"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.this.arn
}

resource "aws_iam_role" "rotate" {
  name = "${local.name}-rotate"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rotate_xray" {
  role       = aws_iam_role.rotate.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "rotate" {
  name = "${local.name}-rotate"
  role = aws_iam_role.rotate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
        ]
        Resource = [aws_secretsmanager_secret.runtime.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["rds:ModifyDBInstance"]
        Resource = [aws_db_instance.this.arn]
      },
      {
        Effect = "Allow"
        Action = ["ecs:UpdateService"]
        Resource = [
          "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/${aws_ecs_service.app.name}",
          "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${aws_ecs_cluster.this.name}/${aws_ecs_service.worker.name}",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = [aws_kms_key.this.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.rotate_dlq.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = ["${aws_cloudwatch_log_group.rotate.arn}:*"]
      },
    ]
  })
}

resource "aws_lambda_function" "rotate" {
  #checkov:skip=CKV_AWS_117:Rotation talks to Secrets Manager, RDS, and ECS public APIs, not the VPC data plane
  #checkov:skip=CKV_AWS_272:Marketplace starter does not require Lambda code signing
  filename                       = data.archive_file.rotate.output_path
  source_code_hash               = data.archive_file.rotate.output_base64sha256
  function_name                  = "${local.name}-rotate"
  role                           = aws_iam_role.rotate.arn
  handler                        = "rotate.handler"
  runtime                        = "python3.12"
  timeout                        = 60
  memory_size                    = 256
  reserved_concurrent_executions = 2
  kms_key_arn                    = aws_kms_key.this.arn

  environment {
    variables = {
      DB_INSTANCE_ID = aws_db_instance.this.identifier
      ECS_CLUSTER    = aws_ecs_cluster.this.name
      ECS_SERVICES   = "${aws_ecs_service.app.name},${aws_ecs_service.worker.name}"
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.rotate_dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.rotate]
}

resource "aws_lambda_permission" "rotate" {
  statement_id   = "AllowSecretsManager"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.rotate.function_name
  principal      = "secretsmanager.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
  source_arn     = aws_secretsmanager_secret.runtime.arn
}

resource "aws_secretsmanager_secret_rotation" "runtime" {
  secret_id           = aws_secretsmanager_secret.runtime.id
  rotation_lambda_arn = aws_lambda_function.rotate.arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [aws_lambda_permission.rotate, aws_secretsmanager_secret_version.runtime]
}
