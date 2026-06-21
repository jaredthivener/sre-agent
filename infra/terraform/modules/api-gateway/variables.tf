variable "app_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "sqs_queue_url" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "api_gateway_role_arn" {
  type = string
}

variable "log_retention_days" {
  type = number
}

variable "webhook_secret_arn" {
  description = "Secrets Manager ARN for the PagerDuty webhook signing secret"
  type        = string
}

variable "lambda_subnet_ids" {
  type = list(string)
}

variable "lambda_sg_id" {
  type = string
}
