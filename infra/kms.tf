# Customer-managed KMS key for encrypting pipeline data at rest across S3, Lambda
# environment variables, CloudWatch Logs, ECR images, and the SNS approval topic.
# A single key keeps the demo simple while satisfying the "bring your own CMK"
# hardening guidance (CKV_AWS_158, CKV_AWS_173, CKV_AWS_136, CKV_AWS_26, and the
# matching semgrep *-unencrypted rules). Rotation is enabled so the key also
# satisfies CKV2_AWS_67 for the CMK-encrypted S3 bucket.

resource "aws_kms_key" "pipeline" {
  description             = "${local.name_prefix} pipeline encryption key (S3, Lambda env, Logs, ECR, SNS)"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  # Key policy delegates IAM-principal access to account IAM policies (the AWS
  # default root statement) and additionally grants the CloudWatch Logs and SNS
  # service principals the operations they perform on the key on your behalf.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # This is the AWS default key policy statement: it does NOT grant access
        # by itself — it delegates authorization for this key to IAM policies in
        # the account root. For production, scope this down to explicit key
        # administrators and users (dedicated kms:* admin principals + a separate
        # least-privilege usage statement) instead of delegating the full "kms:*"
        # action set to every IAM principal in the account.
        Sid       = "EnableRootAccount"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
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
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region}:${local.account_id}:log-group:*"
          }
        }
      },
      {
        Sid       = "AllowSNSService"
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
        ]
        Resource = "*"
      },
      {
        # Required for S3 server-access-log delivery into the CMK-encrypted
        # access-log bucket (per AWS docs: the logging service principal needs
        # GenerateDataKey + Decrypt on the destination bucket's KMS key).
        Sid       = "AllowS3ServerAccessLogging"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
      },
    ]
  })

  tags = {
    Name = "${local.name_prefix}-pipeline-key"
  }
}

resource "aws_kms_alias" "pipeline" {
  name          = "alias/${local.name_prefix}-pipeline"
  target_key_id = aws_kms_key.pipeline.key_id
}
