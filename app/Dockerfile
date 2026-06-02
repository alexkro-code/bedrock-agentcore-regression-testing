# Pinning FROM to a sha256 digest requires resolving it from the live registry
# at build time; this demo intentionally tracks the 3.13-slim tag for
# readability. For reproducible production builds, pin to a digest:
#   docker pull public.ecr.aws/docker/library/python:3.13-slim
#   FROM public.ecr.aws/docker/library/python:3.13-slim@sha256:<hash>
# nosemgrep: dockerfile-source-not-pinned
FROM public.ecr.aws/docker/library/python:3.13-slim

WORKDIR /app

RUN pip install --no-cache-dir \
    "strands-agents>=1.0" \
    "bedrock-agentcore>=0.1" \
    "aws-opentelemetry-distro>=0.10" \
    "boto3>=1.42"

COPY supervisor.py .

# Run as an unprivileged user (CKV_DOCKER_3) rather than the default root.
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app
USER appuser

# The AgentCore Runtime contract serves on port 8080 with a /ping health route
# (CKV_DOCKER_2). urllib is stdlib, so no extra package is needed. Exec/JSON
# form is used so OS signals pass through and Docker does not wrap it in a shell
# (semgrep prefer-json-notation); the script's own sys.exit signals (un)healthy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8080/ping', timeout=4).status == 200 else 1)"]

CMD ["opentelemetry-instrument", "python", "supervisor.py"]
