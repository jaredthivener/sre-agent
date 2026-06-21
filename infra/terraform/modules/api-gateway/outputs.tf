output "invoke_url" {
  description = "Base URL for the API — append /webhook/pagerduty for the PagerDuty destination"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "api_id" {
  value = aws_apigatewayv2_api.webhook.id
}
