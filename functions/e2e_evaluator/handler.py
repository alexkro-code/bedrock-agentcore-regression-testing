import json
import os
import time

import boto3
from botocore.config import Config

_BEDROCK = boto3.client(
    "bedrock",
    config=Config(retries={"max_attempts": 5, "mode": "adaptive"}),
)
_S3 = boto3.client("s3")

BUCKET = os.environ["BUCKET_NAME"]
JUDGE_MODEL = os.environ.get("JUDGE_MODEL", "anthropic.claude-opus-4-6")
CANDIDATE_MODEL = os.environ.get("CANDIDATE_MODEL", "anthropic.claude-sonnet-4-6")


def run_e2e_evaluation(run_id, dataset_s3_uri, output_s3_uri, role_arn, judge_model):
    return _BEDROCK.create_evaluation_job(
        jobName=f"agent-regression-{run_id}",
        roleArn=role_arn,
        applicationType="ModelEvaluation",
        evaluationConfig={
            "automated": {
                "datasetMetricConfigs": [
                    {
                        "taskType": "Custom",
                        "dataset": {
                            "name": "agent-e2e",
                            "datasetLocation": {"s3Uri": dataset_s3_uri},
                        },
                        "metricNames": [
                            "Builtin.Correctness",
                            "Builtin.Completeness",
                            "Builtin.Faithfulness",
                            "Builtin.Helpfulness",
                        ],
                    }
                ],
                "evaluatorModelConfig": {
                    "bedrockEvaluatorModels": [
                        {"modelIdentifier": judge_model}
                    ]
                },
            }
        },
        inferenceConfig={
            "models": [
                {"bedrockModel": {"modelIdentifier": CANDIDATE_MODEL}}
            ]
        },
        outputDataConfig={"s3Uri": output_s3_uri},
    )


def wait_for_job(job_arn, timeout_s=3600):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        resp = _BEDROCK.get_evaluation_job(jobIdentifier=job_arn)
        status = resp.get("status", "")
        if status == "Completed":
            return resp
        if status in {"Failed", "Stopped"}:
            raise RuntimeError(
                f"Evaluation job {job_arn} ended with status: {status}"
            )
        time.sleep(30)  # nosemgrep: arbitrary-sleep -- intentional poll interval while waiting for the Bedrock evaluation job to finish
    raise RuntimeError(f"Evaluation job {job_arn} timed out after {timeout_s}s")


def lambda_handler(event, context):
    run_id = event["run_id"]
    config = event["config"]

    dataset_uri = config["datasets"]["e2e"]
    output_uri = f"s3://{BUCKET}/results/{run_id}/e2e-evaluation/"
    role_arn = config.get("evaluation_role_arn", context.invoked_function_arn.rsplit(":", 1)[0])

    response = run_e2e_evaluation(
        run_id=run_id,
        dataset_s3_uri=dataset_uri,
        output_s3_uri=output_uri,
        role_arn=role_arn,
        judge_model=config.get("judge_model", JUDGE_MODEL),
    )

    job_arn = response["jobArn"]
    result = wait_for_job(job_arn)

    output_key = f"results/{run_id}/e2e-scores.json"
    _S3.put_object(
        Bucket=BUCKET,
        Key=output_key,
        Body=json.dumps({"job_arn": job_arn, "status": "Completed", "output_uri": output_uri}),
    )
    return {"run_id": run_id, "e2e_scores_key": output_key, "job_arn": job_arn}
