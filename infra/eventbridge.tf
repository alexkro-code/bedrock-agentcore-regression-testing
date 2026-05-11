resource "aws_cloudwatch_event_rule" "config_upload" {
  name        = "${local.name_prefix}-trigger"
  description = "Triggers regression pipeline when config is uploaded to S3"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.pipeline.id] }
      object = { key = [{ prefix = "config/" }] }
      reason = ["PutObject"]
    }
  })
}

resource "aws_cloudwatch_event_target" "state_machine" {
  rule     = aws_cloudwatch_event_rule.config_upload.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.eventbridge.arn

  input_transformer {
    input_paths = {
      s3Key = "$.detail.object.key"
    }
    input_template = "{\"config_s3_key\": <s3Key>}"
  }
}
