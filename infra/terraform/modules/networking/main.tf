# vpc module v6 removed the per-service endpoint boolean flags.
# Interface endpoints now live in the vpc-endpoints submodule (same source, //modules/vpc-endpoints).

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = var.app_name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = [for i in range(length(var.availability_zones)) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(length(var.availability_zones)) : cidrsubnet(var.vpc_cidr, 4, i + length(var.availability_zones))]

  enable_nat_gateway   = true
  single_nat_gateway   = false # one per AZ — survives an AZ failure during a live investigation
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Module = "networking" }
}

# ── Security groups ───────────────────────────────────────────────────────────

module "vpc_endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "${var.app_name}-vpc-endpoints"
  description = "Interface VPC endpoints — accept HTTPS from within the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [{
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidr
    description = "HTTPS from VPC"
  }]

  egress_rules = ["all-all"]
}

module "ecs_agent_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "${var.app_name}-ecs-agent"
  description = "SRE agent Fargate tasks — HTTPS egress to AWS APIs and Langfuse"
  vpc_id      = module.vpc.vpc_id

  egress_with_cidr_blocks = [{
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = "0.0.0.0/0"
    description = "HTTPS: AWS VPC endpoints + Anthropic API via NAT"
  }]
}

module "lambda_authorizer_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "${var.app_name}-lambda-authorizer"
  description = "Lambda HMAC authorizer — egress to Secrets Manager VPC endpoint only"
  vpc_id      = module.vpc.vpc_id

  egress_with_cidr_blocks = [{
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidr
    description = "HTTPS to Secrets Manager VPC endpoint"
  }]
}

module "langfuse_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "${var.app_name}-langfuse"
  description = "Langfuse ECS service — OTLP from agent, egress for Postgres/Redis/Anthropic"
  vpc_id      = module.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [{
    from_port                = 3000
    to_port                  = 3000
    protocol                 = "tcp"
    source_security_group_id = module.ecs_agent_sg.security_group_id
    description              = "OTLP HTTP from agent tasks"
  }]

  number_of_computed_ingress_with_source_security_group_id = 1

  egress_rules = ["all-all"]
}

module "db_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "${var.app_name}-db"
  description = "RDS Postgres and ElastiCache Redis for Langfuse"
  vpc_id      = module.vpc.vpc_id

  computed_ingress_with_source_security_group_id = [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      source_security_group_id = module.langfuse_sg.security_group_id
      description              = "Postgres from Langfuse tasks"
    },
    {
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      source_security_group_id = module.langfuse_sg.security_group_id
      description              = "Redis from Langfuse tasks"
    }
  ]

  number_of_computed_ingress_with_source_security_group_id = 2
}

# ── VPC interface endpoints (v6 pattern — separate submodule) ─────────────────

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.6"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "${var.app_name}-s3-endpoint" }
    }
    secretsmanager = {
      service             = "secretsmanager"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoints_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${var.app_name}-secretsmanager-endpoint" }
    }
    ssm = {
      service             = "ssm"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoints_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${var.app_name}-ssm-endpoint" }
    }
    sqs = {
      service             = "sqs"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoints_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${var.app_name}-sqs-endpoint" }
    }
    ecr_api = {
      service             = "ecr.api"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoints_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${var.app_name}-ecr-api-endpoint" }
    }
    ecr_dkr = {
      service             = "ecr.dkr"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoints_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${var.app_name}-ecr-dkr-endpoint" }
    }
    logs = {
      service             = "logs"
      service_type        = "Interface"
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoints_sg.security_group_id]
      private_dns_enabled = true
      tags                = { Name = "${var.app_name}-logs-endpoint" }
    }
  }
}
