import json
import os

import boto3
from botocore.config import Config

_AGENTCORE_CTRL = boto3.client(
    "bedrock-agentcore-control",
    config=Config(retries={"max_attempts": 5, "mode": "adaptive"}),
)
_S3 = boto3.client("s3")

BUCKET = os.environ["BUCKET_NAME"]


def promote_candidate(runtime_id, endpoint_name, candidate_version, run_id):
    response = _AGENTCORE_CTRL.update_agent_runtime_endpoint(
        agentRuntimeId=runtime_id,
        name=endpoint_name,
        agentRuntimeVersion=candidate_version,
        description=f"Promoted by regression run {run_id}",
    )
    return {
        "status": "promoted",
        "runtime_id": runtime_id,
        "endpoint_arn": response["agentRuntimeEndpointArn"],
        "version": candidate_version,
    }


def lambda_handler(event, context):
    run_id = event["run_id"]
    candidate_config = event["candidate_config"]

    runtime_id = candidate_config["production_runtime_id"]
    endpoint_name = candidate_config["production_endpoint_name"]
    candidate_version = candidate_config["candidate_version"]

    result = promote_candidate(runtime_id, endpoint_name, candidate_version, run_id)

    output_key = f"results/{run_id}/promotion.json"
    _S3.put_object(
        Bucket=BUCKET,
        Key=output_key,
        Body=json.dumps(result),
    )
    return result
