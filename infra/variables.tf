variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "agent-regression"
}

variable "baseline_model" {
  description = "Model ID for the baseline agent runtime"
  type        = string
  default     = "anthropic.claude-sonnet-4-5"
}

variable "candidate_model" {
  description = "Model ID for the candidate agent runtime"
  type        = string
  default     = "anthropic.claude-sonnet-4-6"
}

variable "judge_model" {
  description = "Model ID for the LLM judge in evaluation"
  type        = string
  default     = "anthropic.claude-opus-4-6"
}

variable "production_runtime_arn" {
  description = "ARN of the production AgentCore Runtime to upgrade"
  type        = string
}

variable "production_endpoint_name" {
  description = "Name of the production endpoint on the Runtime"
  type        = string
  default     = "production"
}

variable "image_uri" {
  description = "ECR image URI for the agent container (set after build_and_push.sh)"
  type        = string
  default     = ""
}

variable "runtime_role_arn" {
  description = "IAM role ARN for AgentCore Runtime execution"
  type        = string
}

variable "approval_email" {
  description = "Email address for SNS approval notifications"
  type        = string
}

variable "e2e_threshold" {
  description = "Minimum end-to-end correctness score for promotion"
  type        = number
  default     = 0.85
}

variable "per_agent_floor" {
  description = "Minimum per-agent score for promotion"
  type        = number
  default     = 0.80
}

variable "max_regression_delta" {
  description = "Maximum tolerated regression between baseline and candidate"
  type        = number
  default     = 0.10
}

variable "runs_per_config" {
  description = "Number of repetitions per test case for statistical confidence"
  type        = number
  default     = 3
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 30
}

variable "vpc_enabled" {
  description = "Whether to deploy Lambda functions inside a VPC"
  type        = bool
  default     = false
}

variable "create_vpc" {
  description = "Create a new VPC (true) or use an existing one (false). Only applies when vpc_enabled = true"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC. Only applies when create_vpc = true"
  type        = string
  default     = "10.0.0.0/16"
}

variable "existing_vpc_id" {
  description = "ID of an existing VPC. Only applies when vpc_enabled = true and create_vpc = false"
  type        = string
  default     = ""
}

variable "existing_subnet_ids" {
  description = "Subnet IDs in the existing VPC. Only applies when vpc_enabled = true and create_vpc = false"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "bedrock-agentcore-regression-testing"
    ManagedBy = "terraform"
  }
}
