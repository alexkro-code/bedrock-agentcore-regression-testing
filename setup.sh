#!/usr/bin/env bash
set -euo pipefail

# Interactive setup for Bedrock AgentCore Regression Testing Pipeline
# Generates infra/terraform.tfvars from user inputs

TFVARS_FILE="infra/terraform.tfvars"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Bedrock AgentCore Regression Testing Pipeline — Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --- Prerequisites check ---
for cmd in aws terraform docker; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not in PATH."
    echo "See README.md Prerequisites section for installation links."
    exit 1
  fi
done

# --- Step 1: AWS Account ---
echo "Step 1/5: AWS Account"
echo "─────────────────────"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
  echo "ERROR: Unable to retrieve AWS account ID."
  echo "Ensure AWS CLI is configured: aws configure"
  exit 1
}
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
echo "  Account:  $ACCOUNT_ID"
echo "  Identity: $CALLER_ARN"
echo ""
read -rp "Deploy to this account? [Y/n]: " CONFIRM_ACCOUNT
CONFIRM_ACCOUNT="${CONFIRM_ACCOUNT:-Y}"
if [[ ! "$CONFIRM_ACCOUNT" =~ ^[Yy] ]]; then
  echo "Aborted. Configure a different AWS profile and re-run."
  exit 0
fi
echo ""

# --- Step 2: Region ---
echo "Step 2/5: Deployment Region"
echo "───────────────────────────"
echo "  Amazon Bedrock AgentCore requires a supported region."
echo "  Supported regions: us-east-1, us-west-2, eu-west-1, ap-northeast-1"
echo ""
read -rp "Region [us-east-1]: " AWS_REGION
AWS_REGION="${AWS_REGION:-us-east-1}"
echo "  Selected: $AWS_REGION"
echo ""

# --- Step 3: VPC Configuration ---
echo "Step 3/5: VPC Configuration"
echo "────────────────────────────"
echo "  AgentCore Runtimes can optionally run inside a VPC for network isolation."
echo ""
echo "  1) No VPC (public internet access, simplest setup)"
echo "  2) Create a new VPC"
echo "  3) Use an existing VPC"
echo ""
read -rp "Choose [1/2/3] (default: 1): " VPC_CHOICE
VPC_CHOICE="${VPC_CHOICE:-1}"

VPC_ENABLED="false"
CREATE_VPC="false"
VPC_ID=""
VPC_CIDR=""
SUBNET_IDS=""

case "$VPC_CHOICE" in
  2)
    VPC_ENABLED="true"
    CREATE_VPC="true"
    echo ""
    echo "  New VPC CIDR block (private address space for pipeline resources):"
    echo "  Common choices: 10.0.0.0/16, 172.16.0.0/16, 192.168.0.0/16"
    echo ""
    read -rp "  CIDR [10.0.0.0/16]: " VPC_CIDR
    VPC_CIDR="${VPC_CIDR:-10.0.0.0/16}"
    echo "  Will create VPC with CIDR: $VPC_CIDR"
    ;;
  3)
    VPC_ENABLED="true"
    CREATE_VPC="false"
    echo ""
    echo "  Fetching VPCs in $AWS_REGION..."
    echo ""

    VPCS_JSON=$(aws ec2 describe-vpcs --region "$AWS_REGION" \
      --query 'Vpcs[*].{Id:VpcId,Cidr:CidrBlock,Name:Tags[?Key==`Name`].Value|[0],Default:IsDefault}' \
      --output json 2>/dev/null) || {
      echo "  ERROR: Could not list VPCs. Check IAM permissions (ec2:DescribeVpcs)."
      exit 1
    }

    VPC_COUNT=$(echo "$VPCS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
    if [[ "$VPC_COUNT" -eq 0 ]]; then
      echo "  No VPCs found in $AWS_REGION. Choose option 2 to create one."
      exit 1
    fi

    echo "  Available VPCs:"
    echo "  ─────────────────────────────────────────────────────────────"
    printf "  %-4s %-24s %-18s %-30s\n" "#" "VPC ID" "CIDR" "Name"
    echo "  ─────────────────────────────────────────────────────────────"

    # Display VPC list
    echo "$VPCS_JSON" | python3 -c "
import sys, json
vpcs = json.load(sys.stdin)
for i, v in enumerate(vpcs, 1):
    name = v.get('Name') or ('(default)' if v.get('Default') else '(unnamed)')
    print(f\"  {i:<4}{v['Id']:<24}{v['Cidr']:<18}{name}\")
"
    echo ""
    read -rp "  Select VPC number: " VPC_NUM
    VPC_ID=$(echo "$VPCS_JSON" | python3 -c "
import sys, json
vpcs = json.load(sys.stdin)
idx = int('${VPC_NUM}') - 1
if 0 <= idx < len(vpcs):
    print(vpcs[idx]['Id'])
else:
    print('INVALID')
")
    if [[ "$VPC_ID" == "INVALID" || -z "$VPC_ID" ]]; then
      echo "  Invalid selection."
      exit 1
    fi
    echo "  Selected: $VPC_ID"

    # Fetch subnets for the selected VPC
    echo ""
    echo "  Fetching private subnets in $VPC_ID..."
    SUBNETS_JSON=$(aws ec2 describe-subnets --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'Subnets[?MapPublicIpOnLaunch==`false`].{Id:SubnetId,Az:AvailabilityZone,Cidr:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' \
      --output json 2>/dev/null)

    SUBNET_COUNT=$(echo "$SUBNETS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
    if [[ "$SUBNET_COUNT" -eq 0 ]]; then
      echo "  WARNING: No private subnets found. Using all subnets instead."
      SUBNETS_JSON=$(aws ec2 describe-subnets --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[*].{Id:SubnetId,Az:AvailabilityZone,Cidr:CidrBlock,Name:Tags[?Key==`Name`].Value|[0]}' \
        --output json 2>/dev/null)
    fi

    SUBNET_IDS=$(echo "$SUBNETS_JSON" | python3 -c "
import sys, json
subnets = json.load(sys.stdin)
ids = [s['Id'] for s in subnets[:3]]
print(','.join(ids))
")
    echo "  Using subnets: $SUBNET_IDS"
    ;;
  *)
    echo "  No VPC — pipeline runs without VPC isolation."
    ;;
esac
echo ""

# --- Step 4: Resource Tag ---
echo "Step 4/5: Mandatory Resource Tag"
echo "─────────────────────────────────"
echo "  All deployed resources will be tagged for cost tracking and governance."
echo ""
read -rp "  Tag key [CostCenter]: " TAG_KEY
TAG_KEY="${TAG_KEY:-CostCenter}"
read -rp "  Tag value [bedrock-regression-testing]: " TAG_VALUE
TAG_VALUE="${TAG_VALUE:-bedrock-regression-testing}"
echo "  All resources will be tagged: $TAG_KEY = $TAG_VALUE"
echo ""

# --- Step 5: Pipeline Configuration ---
echo "Step 5/5: Pipeline Settings"
echo "────────────────────────────"
echo ""
read -rp "  Production Runtime ARN (required): " PRODUCTION_RUNTIME_ARN
if [[ -z "$PRODUCTION_RUNTIME_ARN" ]]; then
  echo "  ERROR: Production Runtime ARN is required."
  exit 1
fi

read -rp "  Runtime IAM Role ARN (required): " RUNTIME_ROLE_ARN
if [[ -z "$RUNTIME_ROLE_ARN" ]]; then
  echo "  ERROR: Runtime Role ARN is required."
  exit 1
fi

read -rp "  Approval email address (required): " APPROVAL_EMAIL
if [[ -z "$APPROVAL_EMAIL" ]]; then
  echo "  ERROR: Approval email is required."
  exit 1
fi

read -rp "  Project name prefix [agent-regression]: " PROJECT_NAME
PROJECT_NAME="${PROJECT_NAME:-agent-regression}"
echo ""

# --- Generate terraform.tfvars ---
echo "Generating $TFVARS_FILE..."
echo ""

cat > "$TFVARS_FILE" <<EOF
# Generated by setup.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Re-run ./setup.sh to regenerate, or edit manually.

aws_region               = "$AWS_REGION"
project_name             = "$PROJECT_NAME"
baseline_model           = "anthropic.claude-sonnet-4-5"
candidate_model          = "anthropic.claude-sonnet-4-6"
judge_model              = "anthropic.claude-opus-4-6"
production_runtime_arn   = "$PRODUCTION_RUNTIME_ARN"
production_endpoint_name = "production"
runtime_role_arn         = "$RUNTIME_ROLE_ARN"
approval_email           = "$APPROVAL_EMAIL"
e2e_threshold            = 0.85
per_agent_floor          = 0.80
max_regression_delta     = 0.10
runs_per_config          = 3
log_retention_days       = 365
reserved_concurrency     = 5

# VPC Configuration
vpc_enabled = $VPC_ENABLED
create_vpc  = $CREATE_VPC
EOF

if [[ "$CREATE_VPC" == "true" ]]; then
  cat >> "$TFVARS_FILE" <<EOF
vpc_cidr    = "$VPC_CIDR"
EOF
fi

if [[ "$VPC_ENABLED" == "true" && "$CREATE_VPC" == "false" ]]; then
  cat >> "$TFVARS_FILE" <<EOF
existing_vpc_id     = "$VPC_ID"
existing_subnet_ids = [$(echo "$SUBNET_IDS" | sed 's/,/", "/g; s/^/"/; s/$/"/' )]
EOF
fi

cat >> "$TFVARS_FILE" <<EOF

# Resource tags (applied to all resources)
tags = {
  Project   = "bedrock-agentcore-regression-testing"
  ManagedBy = "terraform"
  $TAG_KEY  = "$TAG_VALUE"
}
EOF

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Setup Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Configuration written to: $TFVARS_FILE"
echo ""
echo "  Next steps:"
echo "    1. Review $TFVARS_FILE"
echo "    2. cd infra && terraform init && terraform apply"
echo "    3. cd ../app && bash build_and_push.sh"
echo "    4. Upload datasets and trigger (see README.md Step 4)"
echo ""
