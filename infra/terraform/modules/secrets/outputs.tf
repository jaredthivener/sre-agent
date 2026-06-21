output "anthropic_api_key_arn" {
  value = aws_secretsmanager_secret.anthropic_api_key.arn
}

output "pagerduty_webhook_secret_arn" {
  value = aws_secretsmanager_secret.pagerduty_webhook_secret.arn
}

output "langfuse_public_key_arn" {
  value = aws_secretsmanager_secret.langfuse_public_key.arn
}

output "langfuse_secret_key_arn" {
  value = aws_secretsmanager_secret.langfuse_secret_key.arn
}

output "langfuse_nextauth_secret_arn" {
  value = aws_secretsmanager_secret.langfuse_nextauth_secret.arn
}

output "langfuse_salt_arn" {
  value = aws_secretsmanager_secret.langfuse_salt.arn
}
