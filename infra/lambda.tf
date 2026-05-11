locals {
  functions = {
    "agent-factory" = {
      handler     = "handler.lambda_handler"
      source_dir  = "${path.module}/../functions/agent_factory"
      timeout     = 600
      memory_size = 256
    }
    "test-runner" = {
      handler     = "handler.lambda_handler"
      source_dir  = "${path.module}/../functions/test_runner"
      timeout     = 900
      memory_size = 512
    }
    "per-agent-evaluator" = {
      handler     = "handler.lambda_handler"
      source_dir  = "${path.module}/../functions/per_agent_evaluator"
      timeout     = 300
      memory_size = 256
    }
    "e2e-evaluator" = {
      handler     = "handler.lambda_handler"
      source_dir  = "${path.module}/../functions/e2e_evaluator"
      timeout     = 300
      memory_size = 256
    }
    "report-generator" = {
      handler     = "handler.lambda_handler"
      source_dir  = "${path.module}/../functions/report_generator"
      timeout     = 120
      memory_size = 256
    }
    "promoter" = {
      handler     = "handler.lambda_handler"
      source_dir  = "${path.module}/../functions/promoter"
      timeout     = 120
      memory_size = 256
    }
  }
}

data "archive_file" "functions" {
  for_each = local.functions

  type        = "zip"
  source_dir  = each.value.source_dir
  output_path = "${path.module}/.packages/${each.key}.zip"
}

resource "aws_lambda_function" "functions" {
  for_each = local.functions

  function_name = "${local.name_prefix}-${each.key}"
  role          = aws_iam_role.lambda[each.key].arn
  handler       = each.value.handler
  runtime       = "python3.13"
  timeout       = each.value.timeout
  memory_size   = each.value.memory_size

  filename         = data.archive_file.functions[each.key].output_path
  source_code_hash = data.archive_file.functions[each.key].output_base64sha256

  environment {
    variables = {
      BUCKET_NAME          = aws_s3_bucket.pipeline.id
      BASELINE_MODEL       = var.baseline_model
      CANDIDATE_MODEL      = var.candidate_model
      JUDGE_MODEL          = var.judge_model
      E2E_THRESHOLD        = tostring(var.e2e_threshold)
      PER_AGENT_FLOOR      = tostring(var.per_agent_floor)
      MAX_REGRESSION_DELTA = tostring(var.max_regression_delta)
      RUNS_PER_CONFIG      = tostring(var.runs_per_config)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}
