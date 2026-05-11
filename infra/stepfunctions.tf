resource "aws_sfn_state_machine" "pipeline" {
  name     = "${local.name_prefix}-pipeline"
  role_arn = aws_iam_role.step_functions.arn

  definition = templatefile("${path.module}/../statemachine/regression_pipeline.asl.json", {
    agent_factory_arn     = aws_lambda_function.functions["agent-factory"].arn
    test_runner_arn       = aws_lambda_function.functions["test-runner"].arn
    per_agent_eval_arn    = aws_lambda_function.functions["per-agent-evaluator"].arn
    e2e_eval_arn          = aws_lambda_function.functions["e2e-evaluator"].arn
    report_generator_arn  = aws_lambda_function.functions["report-generator"].arn
    promoter_arn          = aws_lambda_function.functions["promoter"].arn
    approval_topic_arn    = aws_sns_topic.approvals.arn
    bucket_name           = aws_s3_bucket.pipeline.id
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.state_machine.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  depends_on = [aws_cloudwatch_log_group.state_machine]
}
