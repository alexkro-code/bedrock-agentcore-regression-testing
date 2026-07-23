# Base image pinned to an immutable sha256 digest for reproducible builds and
# supply-chain safety; the 3.13-slim tag is retained for human readability. This
# is the multi-arch manifest-list digest, so it resolves on both amd64 and arm64.
# To refresh after a base-image update, re-resolve the digest:
#   docker pull public.ecr.aws/docker/library/python:3.13-slim
#   docker inspect --format='{{index .RepoDigests 0}}' public.ecr.aws/docker/library/python:3.13-slim
FROM public.ecr.aws/docker/library/python:3.13-slim@sha256:6771159cd4fa5d9bba1258caf0b82e6b73458c694d178ad97c5e925c2d0e1a91

WORKDIR /app

RUN pip install --no-cache-dir \
    "strands-agents==1.48.0" \
    "bedrock-agentcore==1.18.1" \
    "aws-opentelemetry-distro==0.18.0" \
    "boto3==1.43.54"

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
