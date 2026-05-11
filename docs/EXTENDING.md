# Extending the Pipeline

## Adding New Agent Roles

1. Add the agent to `app/supervisor.py` as a new `Agent` instance and tool.
2. Add a deterministic check in `functions/per_agent_evaluator/handler.py`:

```python
DETERMINISTIC_CHECKS["your_agent"] = {
    "your_metric": lambda ev, exp: your_check_logic(ev, exp)
}
```

3. Add a rubric in `functions/per_agent_evaluator/rubrics.py`.
4. Add per-agent test cases in `datasets/per-agent-cases.jsonl`.

## Modifying Evaluation Rubrics

Each role has a rubric in `rubrics.py` that the LLM judge uses when deterministic checks fail. Rubrics should:

- Define 2-3 scoring dimensions (each 0.0 to 1.0)
- Provide explicit anchors for each score level
- Request structured JSON output

## Changing the Agent Framework

The pipeline is framework-agnostic at the evaluation layer. To use a different framework:

1. Replace `app/supervisor.py` with your framework's entry point.
2. Ensure your framework emits OpenTelemetry spans with `agent.name` and `session.id` attributes.
3. Update `app/Dockerfile` to install your framework's dependencies.
4. The `opentelemetry-instrument` CMD wrapper routes spans to CloudWatch `aws/spans`.

Supported frameworks:
- Strands Agents SDK (default)
- Any framework that emits OTel spans with the required attributes

## Adding Custom Metrics

To add metrics beyond the built-in set:

1. Define the metric calculation in `functions/per_agent_evaluator/handler.py`.
2. Add threshold to `infra/variables.tf` and pass to Lambda environment.
3. Update `functions/report_generator/handler.py` to include in the report.

## Using a Different IaC Backend

The Terraform state is stored locally by default. For team use, configure an S3 backend:

```hcl
# Add to infra/main.tf
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "agent-regression/terraform.tfstate"
    region = "us-east-1"
  }
}
```

## Scheduling Recurring Runs

Add a cron-based EventBridge rule to run the pipeline on a schedule:

```hcl
# Add to infra/eventbridge.tf
resource "aws_cloudwatch_event_rule" "scheduled_run" {
  name                = "${local.name_prefix}-scheduled"
  schedule_expression = "rate(7 days)"
}
```

Then configure the target to upload the latest config to the `config/` prefix.
