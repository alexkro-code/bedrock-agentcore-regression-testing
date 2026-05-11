FROM public.ecr.aws/docker/library/python:3.13-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    "strands-agents>=1.0" \
    "bedrock-agentcore>=0.1" \
    "aws-opentelemetry-distro>=0.10" \
    "boto3>=1.42"

COPY supervisor.py .

CMD ["opentelemetry-instrument", "python", "supervisor.py"]
