import json
import os
import statistics

import boto3
from botocore.config import Config

from rubrics import ROLE_RUBRICS

_AGENTCORE = boto3.client(
    "bedrock-agentcore",
    config=Config(retries={"max_attempts": 5, "mode": "adaptive"}),
)
_S3 = boto3.client("s3")

BUCKET = os.environ["BUCKET_NAME"]
PER_AGENT_FLOOR = float(os.environ.get("PER_AGENT_FLOOR", "0.80"))

DETERMINISTIC_CHECKS = {
    "supervisor": {
        "routing_correctness": lambda ev, exp: set(
            exp.get("expected_agents", [])
        ).issubset({e.get("tool_name") for e in ev if e.get("type") == "tool_call"})
    },
    "data_retrieval": {
        "tool_call_accuracy": lambda ev, exp: any(
            e.get("tool_name") == exp.get("expected_tool_name")
            for e in ev
            if e.get("type") == "tool_call"
        )
    },
    "research": {
        "rag_faithfulness": lambda ev, exp: any(
            e.get("type") == "kb_lookup" for e in ev
        )
        and any(
            e.get("knowledge_base_id") == exp.get("expected_kb_id")
            for e in ev
            if e.get("type") == "kb_lookup"
        )
    },
    "analysis": {
        "synthesis_quality": lambda ev, exp: sum(
            e.get("output_tokens", 0) for e in ev if e.get("type") == "model_call"
        )
        >= exp.get("min_output_tokens", 200)
    },
    "compliance": {
        "policy_adherence": lambda ev, exp: exp.get("should_block", False)
        == any(e.get("type") == "guardrail" for e in ev)
    },
}


def evaluate_agent(agent_role, agent_events, expected, session_spans=None):
    results = {}
    for metric, check in DETERMINISTIC_CHECKS.get(agent_role, {}).items():
        try:
            passed = check(agent_events, expected)
            results[metric] = {
                "score": 1.0 if passed else 0.0,
                "method": "deterministic",
                "passed": passed,
            }
        except Exception as exc:
            results[metric] = {
                "score": 0.0,
                "method": "deterministic",
                "passed": False,
                "error": str(exc),
            }

    failed = [m for m, r in results.items() if not r["passed"]]
    if failed and session_spans:
        try:
            resp = _AGENTCORE.evaluate(
                evaluatorId="Builtin.Correctness",
                evaluationInput={"sessionSpans": session_spans},
                evaluationTarget={
                    "traceIds": [
                        s.get("traceId", "")
                        for s in session_spans
                        if s.get("attributes", {}).get("agent.name") == agent_role
                    ]
                },
                evaluationReferenceInputs=[
                    {
                        "expectedResponse": {
                            "text": expected.get("expected_output", "")
                        }
                    }
                ],
            )
            for m in failed:
                results[m]["llm_score"] = resp.get("value", 0.0)
                results[m]["llm_label"] = resp.get("label", "")
                results[m]["llm_explanation"] = resp.get("explanation", "")
        except Exception as exc:
            for m in failed:
                results[m]["llm_error"] = str(exc)

    scores = [r["score"] for r in results.values()]
    overall = statistics.mean(scores) if scores else 0.0
    return {
        "agent_role": agent_role,
        "metrics": results,
        "overall_score": overall,
        "passed": overall >= PER_AGENT_FLOOR,
    }


def lambda_handler(event, context):
    run_id = event["run_id"]
    traces_key = event["traces_key"]

    traces = json.loads(
        _S3.get_object(Bucket=BUCKET, Key=traces_key)["Body"].read()
    )

    config = event["config"]
    per_agent_dataset_key = config["datasets"]["per_agent"].replace(
        f"s3://{BUCKET}/", ""
    )
    dataset_body = _S3.get_object(Bucket=BUCKET, Key=per_agent_dataset_key)[
        "Body"
    ].read().decode()
    golden_cases = {
        json.loads(line)["agent_role"]: json.loads(line)
        for line in dataset_body.strip().split("\n")
    }

    all_results = []
    for case in traces:
        for variant in ("baseline", "candidate"):
            variant_data = case.get(variant, {})
            per_agent = variant_data.get("per_agent_traces", {})
            spans = variant_data.get("spans", [])
            for role, events in per_agent.items():
                expected = golden_cases.get(role, {})
                result = evaluate_agent(role, events, expected, spans)
                result["variant"] = variant
                result["task_id"] = case["task_id"]
                all_results.append(result)

    output_key = f"results/{run_id}/per-agent-scores.json"
    _S3.put_object(
        Bucket=BUCKET,
        Key=output_key,
        Body=json.dumps(all_results),
    )
    return {"run_id": run_id, "scores_key": output_key, "evaluations": len(all_results)}
