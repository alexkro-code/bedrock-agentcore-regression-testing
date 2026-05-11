resource "aws_cloudwatch_log_group" "lambda" {
  for_each = toset([
    "agent-factory",
    "test-runner",
    "per-agent-evaluator",
    "e2e-evaluator",
    "report-generator",
    "promoter",
  ])

  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "state_machine" {
  name              = "/aws/states/${local.name_prefix}-pipeline"
  retention_in_days = var.log_retention_days
}
