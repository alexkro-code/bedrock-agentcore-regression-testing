# VPC resources — created only when vpc_enabled = true

locals {
  vpc_id     = var.vpc_enabled ? (var.create_vpc ? aws_vpc.pipeline[0].id : var.existing_vpc_id) : ""
  subnet_ids = var.vpc_enabled ? (var.create_vpc ? aws_subnet.private[*].id : var.existing_subnet_ids) : []
}

# --- New VPC (when create_vpc = true) ---

resource "aws_vpc" "pipeline" {
  count = var.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Lock down the VPC's default security group so it permits no traffic
# (CKV2_AWS_12). Declaring the resource with no ingress/egress rules causes
# Terraform to revoke every rule AWS creates by default.
resource "aws_default_security_group" "pipeline" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.pipeline[0].id

  tags = {
    Name = "${local.name_prefix}-default-sg-restricted"
  }
}

# --- VPC flow logs (CKV2_AWS_11) ---

resource "aws_cloudwatch_log_group" "vpc_flow" {
  count = var.create_vpc ? 1 : 0

  name              = "/aws/vpc/${local.name_prefix}-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.pipeline.arn
}

data "aws_iam_policy_document" "vpc_flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_flow" {
  count = var.create_vpc ? 1 : 0

  name               = "${local.name_prefix}-vpc-flow-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_assume.json
}

resource "aws_iam_role_policy" "vpc_flow" {
  count = var.create_vpc ? 1 : 0

  name = "flow-log-delivery"
  role = aws_iam_role.vpc_flow[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.vpc_flow[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "pipeline" {
  count = var.create_vpc ? 1 : 0

  vpc_id          = aws_vpc.pipeline[0].id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow[0].arn
}

resource "aws_subnet" "private" {
  count = var.create_vpc ? 2 : 0

  vpc_id            = aws_vpc.pipeline[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
  }
}

resource "aws_security_group" "lambda" {
  count = var.vpc_enabled ? 1 : 0

  name        = "${local.name_prefix}-lambda-sg"
  description = "Security group for pipeline Lambda functions"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound for AWS API calls"
  }

  tags = {
    Name = "${local.name_prefix}-lambda-sg"
  }
}

# VPC Endpoints for AWS services (avoids NAT Gateway costs)
resource "aws_vpc_endpoint" "s3" {
  count = var.create_vpc ? 1 : 0

  vpc_id       = aws_vpc.pipeline[0].id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  tags = {
    Name = "${local.name_prefix}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "bedrock" {
  count = var.create_vpc ? 1 : 0

  vpc_id              = aws_vpc.pipeline[0].id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.lambda[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-bedrock-endpoint"
  }
}

resource "aws_vpc_endpoint" "logs" {
  count = var.create_vpc ? 1 : 0

  vpc_id              = aws_vpc.pipeline[0].id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.lambda[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-logs-endpoint"
  }
}
