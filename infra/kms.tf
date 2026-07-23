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

  # Access is delegated to account IAM policies (the AWS "trust account
  # identities" model), so the Lambda execution roles grant themselves key
  # usage via their own IAM policies (see iam.tf). Rather than the single
  # "kms:*" default statement, that delegation is split into an explicit
  # key-administration statement and a key-usage statement — both still scoped
  # to the account root principal, so no principal is locked out and no
  # cross-stack cyclic dependency is introduced, but the key policy no longer
  # grants the full "kms:*" action set. The service-principal statements below
  # grant CloudWatch Logs, SNS, and S3 server-access-logging only the specific
  # operations they perform on the key on your behalf.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Key administration — the management actions from the AWS default
        # "Allow access for Key Administrators" statement. Scope the principal
        # to a dedicated key-admin role for production.
        Sid       = "KeyAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
        ]
        Resource = "*"
      },
      {
        # Key usage — the cryptographic operations pipeline principals need.
        # Delegated to account IAM policies (the Lambda roles in iam.tf grant
        # themselves the subset they use); scope to specific role ARNs for
        # production.
        Sid       = "KeyUsage"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant",
        ]
        Resource = "*"
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
