resource "aws_sns_topic" "approvals" {
  name = "${local.name_prefix}-approvals"
}

resource "aws_sns_topic_subscription" "approval_email" {
  topic_arn = aws_sns_topic.approvals.arn
  protocol  = "email"
  endpoint  = var.approval_email
}

resource "aws_sns_topic_policy" "approvals" {
  arn = aws_sns_topic.approvals.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowStepFunctionsPublish"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.approvals.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_sfn_state_machine.pipeline.arn
        }
      }
    }]
  })
}
