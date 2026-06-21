variable "app_name" { type = string }
variable "aws_region" { type = string }
variable "aws_account_id" { type = string }
variable "log_retention_days" { type = number }
variable "cloudtrail_s3_bucket_name" { type = string }
variable "alarm_sns_topic_arn" { type = string }
variable "dlq_alarm_threshold" { type = number }
