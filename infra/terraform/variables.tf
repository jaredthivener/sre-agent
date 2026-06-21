variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (staging, production)"
  type        = string
  default     = "production"
}

variable "app_name" {
  description = "Application name — used as a prefix on all resources"
  type        = string
  default     = "sre-agent"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across (2 minimum for RDS + ElastiCache)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# ── ECS agent task ────────────────────────────────────────────────────────────

variable "agent_image" {
  description = "Full ECR image URI for the SRE agent (e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/sre-agent:latest)"
  type        = string
}

variable "agent_cpu" {
  description = "Fargate CPU units for the agent task (256/512/1024/2048/4096)"
  type        = number
  default     = 1024
}

variable "agent_memory" {
  description = "Fargate memory (MiB) for the agent task"
  type        = number
  default     = 2048
}

variable "agent_desired_count" {
  description = "Number of ECS tasks running (1 = correct for SQLite dedup; swap to DynamoDB for >1)"
  type        = number
  default     = 1
}

variable "investigation_timeout_seconds" {
  description = "Max seconds per incident investigation — drives SQS visibility timeout"
  type        = number
  default     = 360
}

variable "sqs_max_receive_count" {
  description = "Failed receive attempts before a message moves to the DLQ"
  type        = number
  default     = 3
}

# ── Model selection ───────────────────────────────────────────────────────────

variable "orchestrator_model" {
  description = "Claude model ID for the orchestrator (deep synthesis across all subagent findings)"
  type        = string
  default     = "claude-opus-4-8"
}

variable "subagent_model" {
  description = "Claude model ID for specialist subagents (metrics/logs/traces/k8s/aws/deploy)"
  type        = string
  default     = "claude-sonnet-4-6"
}

variable "scribe_model" {
  description = "Claude model ID for incident-scribe (template fill + post; Haiku is sufficient)"
  type        = string
  default     = "claude-haiku-4-5"
}

variable "dry_run" {
  description = "When true the agent logs its report instead of posting to PagerDuty/Slack"
  type        = bool
  default     = false
}

# ── External endpoints (non-sensitive; stored in SSM Parameter Store) ─────────

variable "grafana_url" {
  description = "Base URL of your Grafana instance"
  type        = string
}

variable "pagerduty_user_email" {
  description = "Email for PagerDuty API requests (service-account address)"
  type        = string
}

variable "slack_incident_channel" {
  description = "Slack channel for incident reports"
  type        = string
  default     = "#incidents"
}

# ── Langfuse ─────────────────────────────────────────────────────────────────

variable "langfuse_image" {
  description = "Langfuse Docker image"
  type        = string
  default     = "langfuse/langfuse:latest"
}

variable "langfuse_db_instance_class" {
  description = "RDS instance class for Langfuse Postgres"
  type        = string
  default     = "db.t3.micro"
}

variable "langfuse_redis_node_type" {
  description = "ElastiCache node type for Langfuse Redis"
  type        = string
  default     = "cache.t3.micro"
}

# ── Observability ─────────────────────────────────────────────────────────────

variable "cloudtrail_s3_bucket_name" {
  description = "S3 bucket name to receive CloudTrail logs (bucket is created; must be globally unique)"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 90
}

variable "dlq_alarm_threshold" {
  description = "DLQ message count that triggers a CloudWatch alarm"
  type        = number
  default     = 1
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications (empty = no notifications)"
  type        = string
  default     = ""
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    Project   = "sre-agent"
    ManagedBy = "terraform"
  }
}
