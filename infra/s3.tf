resource "aws_s3_bucket" "pipeline" {
  bucket_prefix = "${local.name_prefix}-"
  force_destroy = false

  # checkov:skip=CKV_AWS_144: Cross-region replication is out of scope for this
  # ephemeral, single-region demo pipeline (buckets hold transient run artifacts).
}

# nosemgrep: aws-s3-bucket-versioning-not-enabled -- false positive: versioning IS
# enabled below; the rule misreads the separate aws_s3_bucket_versioning resource.
resource "aws_s3_bucket_versioning" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.pipeline.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline" {
  bucket                  = aws_s3_bucket.pipeline.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expire transient run artifacts so the bucket does not grow unbounded
# (CKV2_AWS_61). Noncurrent versions are cleaned up shortly after they are
# superseded since they exist only for accidental-overwrite protection.
resource "aws_s3_bucket_lifecycle_configuration" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  rule {
    id     = "expire-run-artifacts"
    status = "Enabled"

    filter {
      prefix = "results/"
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_notification" "config_trigger" {
  bucket      = aws_s3_bucket.pipeline.id
  eventbridge = true
}

# --- Access logging ---
# Server access logs for the pipeline bucket (CKV_AWS_18). The log bucket is a
# self-contained target: SSE-S3 (S3 log delivery cannot write to a CMK-encrypted
# bucket), versioned, lifecycle-expired, and fully private.

resource "aws_s3_bucket" "access_logs" {
  bucket_prefix = "${local.name_prefix}-logs-"
  force_destroy = false

  # checkov:skip=CKV_AWS_144: Cross-region replication is out of scope for an
  # ephemeral demo; this bucket only holds short-lived access logs.
  # checkov:skip=CKV_AWS_18: This is itself the access-log target bucket;
  # enabling access logging on it would create a recursive logging loop.
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

# Allow the S3 log-delivery group to write access logs into the log bucket.
resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowS3ServerAccessLogs"
      Effect    = "Allow"
      Principal = { Service = "logging.s3.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.access_logs.arn}/*"
      Condition = {
        ArnLike      = { "aws:SourceArn" = aws_s3_bucket.pipeline.arn }
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_s3_bucket_logging" "pipeline" {
  bucket        = aws_s3_bucket.pipeline.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "s3-access/"
}
