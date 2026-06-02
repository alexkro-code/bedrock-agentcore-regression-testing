import json
import os
import time

import boto3
from botocore.config import Config

_AGENTCORE = boto3.client(
    "bedrock-agentcore",
    config=Config(retries={"max_attempts": 5, "mode": "adaptive"}),
)
_LOGS = boto3.client(
    "logs",
    config=Config(retries={"max_attempts": 5, "mode": "adaptive"}),
)
_S3 = boto3.client("s3")

BUCKET = os.environ["BUCKET_NAME"]


def invoke_swarm(runtime_arn, variant, test_case, run_id) -> tuple[str, str]:
    session_id = f"{run_id}-{test_case['task_id']}-{variant}"
    response = _AGENTCORE.invoke_agent_runtime(
        agentRuntimeArn=runtime_arn,
        runtimeSessionId=session_id,
        qualifier="DEFAULT",
        payload=json.dumps({"input": test_case["input"]}).encode("utf-8"),
    )
    chunks = []
    for line in response["response"].iter_lines(chunk_size=1024):
        if not line:
            continue
        decoded = line.decode("utf-8")
        if decoded.startswith("data: "):
            decoded = decoded[len("data: "):]
        chunks.append(decoded)
    return "".join(chunks), session_id


def fetch_session_spans(session_id, log_group="aws/spans", timeout_s=120):
    query_id = _LOGS.start_query(
        logGroupName=log_group,
        startTime=int(time.time()) - 3600,
        endTime=int(time.time()),
        queryString=(
            "fields @timestamp, @message "
            f"| filter attributes.`session.id` = '{session_id}' "
            "| sort @timestamp asc | limit 1000"
        ),
    )["queryId"]
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        r = _LOGS.get_query_results(queryId=query_id)
        if r["status"] == "Complete":
            return [
                json.loads(
                    next(f["value"] for f in row if f["field"] == "@message")
                )
                for row in r["results"]
            ]
        if r["status"] in {"Failed", "Cancelled", "Timeout"}:
            raise RuntimeError(f"Span query {query_id} status {r['status']}")
        time.sleep(2)  # nosemgrep: arbitrary-sleep -- intentional poll backoff between CloudWatch Logs Insights query-result checks
    raise RuntimeError(f"Span query for {session_id} timed out")


def extract_per_agent_traces(spans):
    agents = {}
    for span in spans:
        try:
            attrs = span.get("attributes", {})
            name = span.get("name", "")
            event = {"span_name": name}
            if attrs.get("gen_ai.operation.name") == "chat":
                event["type"] = "model_call"
                event["model_id"] = attrs.get("gen_ai.request.model", "")
                event["input_tokens"] = attrs.get("gen_ai.usage.input_tokens", 0)
                event["output_tokens"] = attrs.get("gen_ai.usage.output_tokens", 0)
            elif name.startswith("tool."):
                event["type"] = "tool_call"
                event["tool_name"] = attrs.get(
                    "tool.name", name.removeprefix("tool.")
                )
                event["parameters"] = attrs.get("tool.arguments", {})
            elif "knowledge_base.id" in attrs:
                event["type"] = "kb_lookup"
                event["knowledge_base_id"] = attrs["knowledge_base.id"]
                event["query"] = attrs.get("retrieval.query", "")
            elif name == "guardrail.intervene":
                event["type"] = "guardrail"
                event["action"] = attrs.get("guardrail.action", "unknown")
            else:
                event["type"] = "other"
            agents.setdefault(attrs.get("agent.name", "unknown"), []).append(event)
        except (KeyError, TypeError):
            continue
    return agents


def lambda_handler(event, context):
    run_id = event["run_id"]
    runtimes = event["runtimes"]
    config = event["config"]

    datasets_key = config["datasets"]["per_agent"]
    dataset_body = _S3.get_object(Bucket=BUCKET, Key=datasets_key.replace(
        f"s3://{BUCKET}/", ""))["Body"].read().decode()
    test_cases = [json.loads(line) for line in dataset_body.strip().split("\n")]

    results = []
    for case in test_cases:
        case_result = {"task_id": case["task_id"]}
        for variant, runtime_info in runtimes.items():
            output, session_id = invoke_swarm(
                runtime_info["arn"], variant, case, run_id
            )
            time.sleep(10)  # nosemgrep: arbitrary-sleep -- intentional wait for OTel spans to flush to CloudWatch before querying them
            spans = fetch_session_spans(session_id)
            per_agent = extract_per_agent_traces(spans)

            case_result[variant] = {
                "output": output,
                "session_id": session_id,
                "spans": spans,
                "per_agent_traces": per_agent,
            }
        results.append(case_result)

    output_key = f"results/{run_id}/traces.json"
    _S3.put_object(
        Bucket=BUCKET,
        Key=output_key,
        Body=json.dumps(results),
    )
    return {"run_id": run_id, "traces_key": output_key, "case_count": len(results)}
