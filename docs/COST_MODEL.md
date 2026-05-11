# Cost Model

## Per-Run Cost Breakdown

A regression run incurs three cost dimensions:

| Dimension | Components | Scaling Factor |
|-----------|-----------|----------------|
| Agent Inference | Both Runtimes x cases x runs_per_config | Linear with dataset size |
| Evaluation | LLM judge calls + Bedrock evaluation job | Reduced by deterministic-first |
| Pipeline | Lambda, Step Functions, S3, CloudWatch | Minimal (~$5/run) |

## Example: 10 E2E + 10 Per-Agent Cases, 3 Runs

| Component | Estimated Cost |
|-----------|---------------|
| Baseline inference (10 cases x 3 runs x 5 agents) | ~$12 |
| Candidate inference (10 cases x 3 runs x 5 agents) | ~$12 |
| Per-agent evaluation (deterministic: free, LLM judge: ~30% escalation) | ~$8 |
| E2E evaluation job (Opus judge, 10 cases) | ~$15 |
| Pipeline infrastructure | ~$5 |
| **Total** | **~$52** |

## Scaling to Production (200 E2E Cases)

| Component | Estimated Cost |
|-----------|---------------|
| Baseline + Candidate inference | ~$168 |
| Per-agent evaluation | ~$48 |
| E2E evaluation job | ~$60 |
| Pipeline infrastructure | ~$5 |
| **Total** | **~$281** |

## Cost Optimization Patterns

1. **Deterministic-first evaluation:** Skips 30-50% of LLM judge calls by catching failures with free lambda checks.
2. **Batch inference:** Use Bedrock batch for scheduled (non-urgent) runs at ~50% discount.
3. **Skip per-agent judging on E2E pass:** If all E2E metrics pass cleanly, skip LLM judge escalation.
4. **Smaller datasets for development:** Use 5-10 cases during pipeline development; scale up for production gates.

## Pricing References

- [Amazon Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
- [Amazon Bedrock AgentCore Pricing](https://aws.amazon.com/bedrock/agentcore/pricing/)
- [AWS Lambda Pricing](https://aws.amazon.com/lambda/pricing/)
- [AWS Step Functions Pricing](https://aws.amazon.com/step-functions/pricing/)
