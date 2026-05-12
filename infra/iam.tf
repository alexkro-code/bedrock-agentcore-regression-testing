data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  for_each = local.functions

  name               = "${local.name_prefix}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  for_each = local.functions

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  for_each = var.vpc_enabled ? local.functions : {}

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3" {
  for_each = local.functions

  name = "s3-access"
  role = aws_iam_role.lambda[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
      ]
      Resource = [
        aws_s3_bucket.pipeline.arn,
        "${aws_s3_bucket.pipeline.arn}/*",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "agent_factory" {
  name = "agentcore-create"
  role = aws_iam_role.lambda["agent-factory"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateAgentRuntime",
          "bedrock-agentcore:GetAgentRuntime",
          "bedrock-agentcore:DeleteAgentRuntime",
        ]
        Resource = "arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:agent-runtime/*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = var.runtime_role_arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "test_runner" {
  name = "agentcore-invoke"
  role = aws_iam_role.lambda["test-runner"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "bedrock-agentcore:InvokeAgentRuntime"
        Resource = "arn:aws:bedrock-agentcore:${local.region}:${local.account_id}:agent-runtime/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:StartQuery",
          "logs:GetQueryResults",
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:aws/spans:*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "per_agent_evaluator" {
  name = "agentcore-evaluate"
  role = aws_iam_role.lambda["per-agent-evaluator"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "bedrock-agentcore:Evaluate"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "e2e_evaluator" {
  name = "bedrock-evaluation"
  role = aws_iam_role.lambda["e2e-evaluator"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:CreateEvaluationJob",
          "bedrock:GetEvaluationJob",
        ]
        Resource = "arn:aws:bedrock:${local.region}:${local.account_id}:evaluation-job/*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.lambda["e2e-evaluator"].arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "promoter" {
  name = "agentcore-promote"
  role = aws_iam_role.lambda["promoter"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "bedrock-agentcore:UpdateAgentRuntimeEndpoint"
      Resource = var.production_runtime_arn
    }]
  })
}

# Step Functions execution role
data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "step_functions" {
  name               = "${local.name_prefix}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

resource "aws_iam_role_policy" "sfn_invoke_lambdas" {
  name = "invoke-lambdas"
  role = aws_iam_role.step_functions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = [for f in aws_lambda_function.functions : f.arn]
    }]
  })
}

resource "aws_iam_role_policy" "sfn_sns" {
  name = "sns-publish"
  role = aws_iam_role.step_functions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.approvals.arn
    }]
  })
}

resource "aws_iam_role_policy" "sfn_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.step_functions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogDelivery",
        "logs:GetLogDelivery",
        "logs:UpdateLogDelivery",
        "logs:DeleteLogDelivery",
        "logs:ListLogDeliveries",
        "logs:PutResourcePolicy",
        "logs:DescribeResourcePolicies",
        "logs:DescribeLogGroups",
      ]
      Resource = "*"
    }]
  })
}

# EventBridge role
data "aws_iam_policy_document" "eventbridge_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge" {
  name               = "${local.name_prefix}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume.json
}

resource "aws_iam_role_policy" "eventbridge_start_execution" {
  name = "start-state-machine"
  role = aws_iam_role.eventbridge.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.pipeline.arn
    }]
  })
}
