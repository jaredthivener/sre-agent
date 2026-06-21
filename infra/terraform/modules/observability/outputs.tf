output "agent_log_group_name" {
  value = aws_cloudwatch_log_group.agent.name
}

output "langfuse_log_group_name" {
  value = aws_cloudwatch_log_group.langfuse.name
}

output "cloudtrail_bucket_name" {
  value = aws_s3_bucket.cloudtrail.bucket
}
