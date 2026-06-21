terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Remote state — replace bucket/key with your values before first apply.
  backend "s3" {
    bucket         = "REPLACE-terraform-state-bucket"
    key            = "sre-agent/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Environment = var.environment
    })
  }
}

data "aws_caller_identity" "current" {}

# ── Modules ───────────────────────────────────────────────────────────────────

module "networking" {
  source             = "./modules/networking"
  app_name           = var.app_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "observability" {
  source                    = "./modules/observability"
  app_name                  = var.app_name
  aws_region                = var.aws_region
  aws_account_id            = data.aws_caller_identity.current.account_id
  log_retention_days        = var.log_retention_days
  cloudtrail_s3_bucket_name = var.cloudtrail_s3_bucket_name
  alarm_sns_topic_arn       = var.alarm_sns_topic_arn
  dlq_alarm_threshold       = var.dlq_alarm_threshold
}

module "iam" {
  source         = "./modules/iam"
  app_name       = var.app_name
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id
  sqs_queue_arn  = module.queue.queue_arn
  dlq_arn        = module.queue.dlq_arn
}

module "secrets" {
  source                 = "./modules/secrets"
  app_name               = var.app_name
  grafana_url            = var.grafana_url
  pagerduty_user_email   = var.pagerduty_user_email
  slack_incident_channel = var.slack_incident_channel
  orchestrator_model     = var.orchestrator_model
  subagent_model         = var.subagent_model
  scribe_model           = var.scribe_model
  dry_run                = var.dry_run
  aws_region             = var.aws_region
}

module "queue" {
  source                        = "./modules/queue"
  app_name                      = var.app_name
  investigation_timeout_seconds = var.investigation_timeout_seconds
  sqs_max_receive_count         = var.sqs_max_receive_count
  dlq_alarm_threshold           = var.dlq_alarm_threshold
  alarm_sns_topic_arn           = var.alarm_sns_topic_arn
  log_group_name                = module.observability.agent_log_group_name
}

module "api_gateway" {
  source               = "./modules/api-gateway"
  app_name             = var.app_name
  aws_region           = var.aws_region
  aws_account_id       = data.aws_caller_identity.current.account_id
  sqs_queue_url        = module.queue.queue_url
  sqs_queue_arn        = module.queue.queue_arn
  api_gateway_role_arn = module.iam.api_gateway_role_arn
  log_retention_days   = var.log_retention_days
  webhook_secret_arn   = module.secrets.pagerduty_webhook_secret_arn
  lambda_subnet_ids    = module.networking.private_subnet_ids
  lambda_sg_id         = module.networking.lambda_sg_id
}

module "langfuse" {
  source             = "./modules/langfuse"
  app_name           = var.app_name
  aws_region         = var.aws_region
  langfuse_image     = var.langfuse_image
  db_instance_class  = var.langfuse_db_instance_class
  redis_node_type    = var.langfuse_redis_node_type
  private_subnet_ids = module.networking.private_subnet_ids
  langfuse_sg_id     = module.networking.langfuse_sg_id
  db_sg_id           = module.networking.db_sg_id
  execution_role_arn = module.iam.ecs_execution_role_arn
  task_role_arn      = module.iam.ecs_task_role_arn
  log_group_name     = module.observability.langfuse_log_group_name
  log_retention_days = var.log_retention_days
}

module "ecs" {
  source                  = "./modules/ecs"
  app_name                = var.app_name
  aws_region              = var.aws_region
  agent_image             = var.agent_image
  agent_cpu               = var.agent_cpu
  agent_memory            = var.agent_memory
  agent_desired_count     = var.agent_desired_count
  task_role_arn           = module.iam.ecs_task_role_arn
  execution_role_arn      = module.iam.ecs_execution_role_arn
  private_subnet_ids      = module.networking.private_subnet_ids
  ecs_sg_id               = module.networking.ecs_sg_id
  sqs_queue_url           = module.queue.queue_url
  secrets_manager_prefix  = var.app_name
  aws_secrets_region      = var.aws_region
  ssm_config_prefix       = "/${var.app_name}"
  log_group_name          = module.observability.agent_log_group_name
  langfuse_otlp_endpoint  = module.langfuse.otlp_endpoint
  langfuse_public_key_arn = module.langfuse.public_key_secret_arn
  langfuse_secret_key_arn = module.langfuse.secret_key_secret_arn
}
