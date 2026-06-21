output "api_gateway_endpoint" {
  description = "HTTPS endpoint to register as the PagerDuty V3 webhook destination"
  value       = "${module.api_gateway.invoke_url}/webhook/pagerduty"
}

output "sqs_queue_url" {
  description = "SQS queue URL (for local testing / manual message injection)"
  value       = module.queue.queue_url
}

output "sqs_dlq_url" {
  description = "Dead-letter queue URL — messages here require manual investigation"
  value       = module.queue.dlq_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name for the agent"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}

output "langfuse_url" {
  description = "Internal Langfuse dashboard URL (accessible from within the VPC)"
  value       = module.langfuse.dashboard_url
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket receiving CloudTrail management events"
  value       = module.observability.cloudtrail_bucket_name
}

output "agent_log_group" {
  description = "CloudWatch log group for the SRE agent container"
  value       = module.observability.agent_log_group_name
}
