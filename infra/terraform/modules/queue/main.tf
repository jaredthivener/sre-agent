module "dlq" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 5.2"

  name                      = "${var.app_name}-investigations-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = { Name = "${var.app_name}-dlq" }
}

module "queue" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 5.2"

  name = "${var.app_name}-investigations"

  visibility_timeout_seconds = var.investigation_timeout_seconds
  message_retention_seconds  = 86400 # 24h — stale investigations dropped
  max_message_size           = 262144
  receive_wait_time_seconds  = 20 # long-polling

  redrive_policy = {
    deadLetterTargetArn = module.dlq.queue_arn
    maxReceiveCount     = var.sqs_max_receive_count
  }

  create_queue_policy = true
  queue_policy_statements = {
    apigw = {
      sid     = "AllowAPIGatewaySend"
      actions = ["sqs:SendMessage"]
      principals = [
        { type = "Service", identifiers = ["apigateway.amazonaws.com"] }
      ]
    }
  }

  tags = { Name = "${var.app_name}-investigations" }
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.app_name}-dlq-not-empty"
  alarm_description   = "Messages in the DLQ indicate a permanently failed investigation needing manual review"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = module.dlq.queue_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.dlq_alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions          = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
}

resource "aws_cloudwatch_metric_alarm" "queue_age" {
  alarm_name          = "${var.app_name}-investigation-queue-age"
  alarm_description   = "Incidents sitting in queue too long — ECS consumer may be unhealthy"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = module.queue.queue_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.investigation_timeout_seconds * 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
}
