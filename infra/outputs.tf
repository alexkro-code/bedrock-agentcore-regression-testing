output "bucket_name" {
  description = "S3 bucket for datasets, traces, scores, and reports"
  value       = aws_s3_bucket.pipeline.id
}

output "state_machine_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for approval notifications"
  value       = aws_sns_topic.approvals.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the agent container image"
  value       = aws_ecr_repository.agent.repository_url
}

output "trigger_command" {
  description = "Command to trigger a regression run"
  value       = "aws s3 cp configs/sample-config.json s3://${aws_s3_bucket.pipeline.id}/config/regression-config.json"
}
