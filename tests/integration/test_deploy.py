"""
Post-deploy smoke test.

Run after `terraform apply` to verify infrastructure is operational.
Requires AWS credentials with read access to deployed resources.

Usage: pytest tests/integration/ -v --run-integration
"""
import json
import subprocess  # nosec B404 -- needed to read `terraform output`; invoked with a fixed arg list, no shell, no untrusted input

import pytest


def pytest_configure(config):
    config.addinivalue_line("markers", "integration: mark test as integration")


def run_tf_output(name):
    result = subprocess.run(  # nosec B603 B607 -- fixed 'terraform' arg list, no shell, no untrusted input; `name` is a hardcoded output key from this test
        ["terraform", "output", "-raw", name],
        capture_output=True,
        text=True,
        cwd="infra",
    )
    if result.returncode != 0:
        pytest.skip(f"Terraform output '{name}' not available: {result.stderr}")
    return result.stdout.strip()


@pytest.mark.integration
def test_bucket_exists():
    import boto3

    bucket_name = run_tf_output("bucket_name")
    s3 = boto3.client("s3")
    response = s3.head_bucket(Bucket=bucket_name)
    assert response["ResponseMetadata"]["HTTPStatusCode"] == 200


@pytest.mark.integration
def test_state_machine_exists():
    import boto3

    arn = run_tf_output("state_machine_arn")
    sfn = boto3.client("stepfunctions")
    response = sfn.describe_state_machine(stateMachineArn=arn)
    assert response["status"] == "ACTIVE"


@pytest.mark.integration
def test_sns_topic_exists():
    import boto3

    arn = run_tf_output("sns_topic_arn")
    sns = boto3.client("sns")
    response = sns.get_topic_attributes(TopicArn=arn)
    assert "Attributes" in response
