import json
import os
import time

import boto3
from botocore.config import Config

_AGENTCORE_CTRL = boto3.client(
    "bedrock-agentcore-control",
    config=Config(retries={"max_attempts": 5, "mode": "adaptive"}),
)
_S3 = boto3.client("s3")

BUCKET = os.environ["BUCKET_NAME"]


def _wait_ready(runtime_id: str, timeout_s: int = 300) -> None:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        status = _AGENTCORE_CTRL.get_agent_runtime(
            agentRuntimeId=runtime_id
        ).get("status", "")
        if status == "READY":
            return
        if status in {"CREATE_FAILED", "UPDATE_FAILED"}:
            raise RuntimeError(f"Runtime {runtime_id} failed: {status}")
        time.sleep(5)
    raise RuntimeError(f"Runtime {runtime_id} not READY in {timeout_s}s")


def build_runtime_variants(
    run_id: str,
    image_uri: str,
    role_arn: str,
    baseline_model: str,
    candidate_model: str,
    mixed_candidate: dict | None = None,
) -> dict:
    variants = {
        "baseline": (baseline_model, None),
        "candidate": (candidate_model, mixed_candidate),
    }
    created = {}
    for variant, (model_id, mixed) in variants.items():
        env = {"MODEL_ID": model_id}
        if mixed:
            env.update(mixed)
        response = _AGENTCORE_CTRL.create_agent_runtime(
            agentRuntimeName=f"agent-swarm-{run_id}-{variant}",
            agentRuntimeArtifact={
                "containerConfiguration": {"containerUri": image_uri}
            },
            roleArn=role_arn,
            networkConfiguration={"networkMode": "PUBLIC"},
            environmentVariables=env,
            description=f"Regression {variant} Runtime for run {run_id}",
        )
        _wait_ready(response["agentRuntimeId"])
        created[variant] = {
            "arn": response["agentRuntimeArn"],
            "id": response["agentRuntimeId"],
            "version": response["agentRuntimeVersion"],
        }
    return created


def lambda_handler(event, context):
    config_key = event["config_s3_key"]
    config = json.loads(
        _S3.get_object(Bucket=BUCKET, Key=config_key)["Body"].read()
    )

    runtimes = build_runtime_variants(
        run_id=config["run_id"],
        image_uri=config["image_uri"],
        role_arn=config["runtime_role_arn"],
        baseline_model=config["baseline_model"],
        candidate_model=config["candidate_model"],
        mixed_candidate=config.get("mixed_candidate"),
    )

    result = {
        "run_id": config["run_id"],
        "config": config,
        "runtimes": runtimes,
    }
    _S3.put_object(
        Bucket=BUCKET,
        Key=f"results/{config['run_id']}/runtimes.json",
        Body=json.dumps(result),
    )
    return result
