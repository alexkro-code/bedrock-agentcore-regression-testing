import json
import os
import statistics

import boto3

_S3 = boto3.client("s3")

BUCKET = os.environ["BUCKET_NAME"]
E2E_THRESHOLD = float(os.environ.get("E2E_THRESHOLD", "0.85"))
PER_AGENT_FLOOR = float(os.environ.get("PER_AGENT_FLOOR", "0.80"))
MAX_REGRESSION_DELTA = float(os.environ.get("MAX_REGRESSION_DELTA", "0.10"))


def aggregate_scores(run_scores, threshold):
    n = len(run_scores)
    if n == 0:
        return {"mean": 0.0, "passed": False, "reason": "no_data"}
    mean = statistics.mean(run_scores)
    if n < 2:
        return {"mean": mean, "stddev": 0.0, "passed": mean >= threshold}
    stddev = statistics.stdev(run_scores)
    margin = 1.96 * (stddev / pow(n, 0.5))
    return {
        "mean": round(mean, 4),
        "stddev": round(stddev, 4),
        "ci_lower": round(mean - margin, 4),
        "ci_upper": round(mean + margin, 4),
        "n_runs": n,
        "passed": (mean - margin) >= threshold,
    }


def compute_per_agent_summary(per_agent_scores):
    by_role_variant = {}
    for entry in per_agent_scores:
        key = (entry["agent_role"], entry["variant"])
        by_role_variant.setdefault(key, []).append(entry["overall_score"])

    summary = {}
    roles = {entry["agent_role"] for entry in per_agent_scores}
    for role in roles:
        baseline_scores = by_role_variant.get((role, "baseline"), [])
        candidate_scores = by_role_variant.get((role, "candidate"), [])
        baseline_agg = aggregate_scores(baseline_scores, PER_AGENT_FLOOR)
        candidate_agg = aggregate_scores(candidate_scores, PER_AGENT_FLOOR)
        delta = round(candidate_agg["mean"] - baseline_agg["mean"], 4)
        summary[role] = {
            "baseline": baseline_agg,
            "candidate": candidate_agg,
            "delta": delta,
            "regression": abs(delta) > MAX_REGRESSION_DELTA and delta < 0,
            "verdict": "FAIL" if (abs(delta) > MAX_REGRESSION_DELTA and delta < 0) else "PASS",
        }
    return summary


def lambda_handler(event, context):
    run_id = event["run_id"]

    per_agent_scores = json.loads(
        _S3.get_object(Bucket=BUCKET, Key=event["scores_key"])["Body"].read()
    )

    per_agent_summary = compute_per_agent_summary(per_agent_scores)

    any_per_agent_fail = any(
        r["verdict"] == "FAIL" for r in per_agent_summary.values()
    )

    overall_verdict = "FAIL" if any_per_agent_fail else "PASS"

    report = {
        "run_id": run_id,
        "overall_verdict": overall_verdict,
        "per_agent_summary": per_agent_summary,
        "e2e_scores_key": event.get("e2e_scores_key"),
        "thresholds": {
            "e2e_correctness": E2E_THRESHOLD,
            "per_agent_floor": PER_AGENT_FLOOR,
            "max_regression_delta": MAX_REGRESSION_DELTA,
        },
    }

    report_key = f"results/{run_id}/report.json"
    _S3.put_object(
        Bucket=BUCKET,
        Key=report_key,
        Body=json.dumps(report, indent=2),
    )

    return {
        "run_id": run_id,
        "report_s3_url": f"s3://{BUCKET}/{report_key}",
        "overall_verdict": overall_verdict,
        "candidate_config": event.get("candidate_config", {}),
    }
