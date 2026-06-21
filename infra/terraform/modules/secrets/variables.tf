variable "app_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "grafana_url" {
  type = string
}

variable "pagerduty_user_email" {
  type = string
}

variable "slack_incident_channel" {
  type = string
}

variable "orchestrator_model" {
  type = string
}

variable "subagent_model" {
  type = string
}

variable "scribe_model" {
  type = string
}

variable "dry_run" {
  type = bool
}
