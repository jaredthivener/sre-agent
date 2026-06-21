output "otlp_endpoint" {
  description = "OTLP/HTTP endpoint the agent sends Langfuse traces to"
  value       = "http://langfuse.${var.app_name}.local:3000/api/public/otel"
}

output "dashboard_url" {
  description = "Langfuse dashboard (accessible within VPC via service discovery DNS)"
  value       = "http://langfuse.${var.app_name}.local:3000"
}

output "public_key_secret_arn" {
  description = "Secrets Manager ARN for the Langfuse project public key"
  value       = "${var.app_name}/langfuse-public-key"
}

output "secret_key_secret_arn" {
  description = "Secrets Manager ARN for the Langfuse project secret key"
  value       = "${var.app_name}/langfuse-secret-key"
}
