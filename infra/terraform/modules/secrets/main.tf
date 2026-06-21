# ── Secrets Manager — one secret per sensitive credential ─────────────────────
# Secrets are created empty; populate via CLI after apply:
#   aws secretsmanager put-secret-value --secret-id <arn> --secret-string "value"

resource "aws_secretsmanager_secret" "anthropic_api_key" {
  name                    = "${var.app_name}/anthropic-api-key"
  description             = "Anthropic API key for the SRE agent orchestrator and subagents"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "pagerduty_api_token" {
  name                    = "${var.app_name}/pagerduty-api-token"
  description             = "PagerDuty REST API token (read incidents + add notes)"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "pagerduty_webhook_secret" {
  name                    = "${var.app_name}/pagerduty-webhook-secret"
  description             = "PagerDuty V3 webhook signing secret for HMAC-SHA256 verification"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "grafana_token" {
  name                    = "${var.app_name}/grafana-service-account-token"
  description             = "Grafana service account token (viewer scope — Prometheus/Loki/Tempo)"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "github_token" {
  name                    = "${var.app_name}/github-token"
  description             = "GitHub fine-grained PAT (read-only repo scope for deploy correlation)"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "slack_bot_token" {
  name                    = "${var.app_name}/slack-bot-token"
  description             = "Slack bot token (chat:write scope for incident reports)"
  recovery_window_in_days = 7
}

# Langfuse credentials — generated on first Langfuse login, then stored here
resource "aws_secretsmanager_secret" "langfuse_public_key" {
  name                    = "${var.app_name}/langfuse-public-key"
  description             = "Langfuse project public key for OTEL exporter auth"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "langfuse_secret_key" {
  name                    = "${var.app_name}/langfuse-secret-key"
  description             = "Langfuse project secret key for OTEL exporter auth"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "langfuse_nextauth_secret" {
  name                    = "${var.app_name}/langfuse-nextauth-secret"
  description             = "Langfuse NEXTAUTH_SECRET — random string for session signing"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "langfuse_salt" {
  name                    = "${var.app_name}/langfuse-salt"
  description             = "Langfuse SALT — random string for password hashing"
  recovery_window_in_days = 7
}

# ── SSM Parameter Store — non-sensitive config ────────────────────────────────

resource "aws_ssm_parameter" "grafana_url" {
  name  = "/${var.app_name}/GRAFANA_URL"
  type  = "String"
  value = var.grafana_url
}

resource "aws_ssm_parameter" "pagerduty_user_email" {
  name  = "/${var.app_name}/PAGERDUTY_USER_EMAIL"
  type  = "String"
  value = var.pagerduty_user_email
}

resource "aws_ssm_parameter" "slack_incident_channel" {
  name  = "/${var.app_name}/SLACK_INCIDENT_CHANNEL"
  type  = "String"
  value = var.slack_incident_channel
}

resource "aws_ssm_parameter" "orchestrator_model" {
  name  = "/${var.app_name}/ORCHESTRATOR_MODEL"
  type  = "String"
  value = var.orchestrator_model
}

resource "aws_ssm_parameter" "subagent_model" {
  name  = "/${var.app_name}/SUBAGENT_MODEL"
  type  = "String"
  value = var.subagent_model
}

resource "aws_ssm_parameter" "scribe_model" {
  name  = "/${var.app_name}/SCRIBE_MODEL"
  type  = "String"
  value = var.scribe_model
}

resource "aws_ssm_parameter" "dry_run" {
  name  = "/${var.app_name}/DRY_RUN"
  type  = "String"
  value = tostring(var.dry_run)
}

resource "aws_ssm_parameter" "aws_region" {
  name  = "/${var.app_name}/AWS_REGION"
  type  = "String"
  value = var.aws_region
}
