variable "app_name" {
  type = string
}

variable "investigation_timeout_seconds" {
  type = number
}

variable "sqs_max_receive_count" {
  type = number
}

variable "dlq_alarm_threshold" {
  type = number
}

variable "alarm_sns_topic_arn" {
  type = string
}

variable "log_group_name" {
  description = "CloudWatch log group for SQS-related Lambda logs (passed from observability module)"
  type        = string
  default     = ""
}
