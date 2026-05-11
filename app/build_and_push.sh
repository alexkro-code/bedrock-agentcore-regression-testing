#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO_NAME="${REPO_NAME:-agent-regression-agent-swarm}"
TAG="${IMAGE_TAG:-v1}"
IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${TAG}"

echo "Building and pushing to: ${IMAGE_URI}"

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin \
    "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

docker build --platform linux/arm64 -t "${REPO_NAME}:${TAG}" .
docker tag "${REPO_NAME}:${TAG}" "${IMAGE_URI}"
docker push "${IMAGE_URI}"

echo "Image pushed: ${IMAGE_URI}"
echo "Set this as image_uri in terraform.tfvars"
