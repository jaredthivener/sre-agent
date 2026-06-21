# ── Lambda authorizer — HMAC-SHA256 validation ────────────────────────────────

module "authorizer_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.8"

  function_name = "${var.app_name}-webhook-authorizer"
  description   = "HMAC-SHA256 verification for PagerDuty V3 webhooks before SQS enqueue"
  handler       = "index.handler"
  runtime       = "python3.13"
  timeout       = 10

  source_path = "${path.module}/authorizer"

  vpc_subnet_ids         = var.lambda_subnet_ids
  vpc_security_group_ids = [var.lambda_sg_id]
  attach_network_policy  = true

  environment_variables = {
    WEBHOOK_SECRET_ARN = var.webhook_secret_arn
    AWS_REGION_NAME    = var.aws_region
  }

  attach_policy_json = true
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SecretsManagerRead"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.webhook_secret_arn]
    }]
  })

  cloudwatch_logs_retention_in_days = var.log_retention_days
  tags                              = { Name = "${var.app_name}-webhook-authorizer" }
}

# ── API Gateway v2 HTTP API ───────────────────────────────────────────────────
# Using raw resources: the SQS direct integration subtype and custom authorizer
# are non-standard enough that raw resources are cleaner than the module wrapper.

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.app_name}-webhook"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_api" "webhook" {
  name          = "${var.app_name}-webhook"
  protocol_type = "HTTP"
  description   = "PagerDuty webhook receiver — validates HMAC then enqueues to SQS"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhook.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_apigatewayv2_authorizer" "pagerduty_hmac" {
  api_id                            = aws_apigatewayv2_api.webhook.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = module.authorizer_lambda.lambda_function_invoke_arn
  identity_sources                  = ["$request.header.X-PagerDuty-Signature"]
  name                              = "pagerduty-hmac"
  authorizer_payload_format_version = "1.0"
  authorizer_result_ttl_in_seconds  = 0 # never cache — each HMAC is one-time use
  enable_simple_responses           = false
}

resource "aws_lambda_permission" "api_gateway_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = module.authorizer_lambda.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.webhook.execution_arn}/*/*"
}

# Direct SQS integration — API GW writes to SQS without a Lambda in the hot path
resource "aws_apigatewayv2_integration" "sqs" {
  api_id                = aws_apigatewayv2_api.webhook.id
  integration_type      = "AWS_PROXY"
  integration_subtype   = "SQS-SendMessage"
  credentials_arn       = var.api_gateway_role_arn
  payload_format_version = "1.0"

  request_parameters = {
    "QueueUrl"    = var.sqs_queue_url
    "MessageBody" = "$request.body"
  }
}

resource "aws_apigatewayv2_route" "webhook" {
  api_id             = aws_apigatewayv2_api.webhook.id
  route_key          = "POST /webhook/pagerduty"
  target             = "integrations/${aws_apigatewayv2_integration.sqs.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.pagerduty_hmac.id
}

# Health check — no auth, used by ALB / Route 53 health checks
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "GET /healthz"
  target    = "integrations/${aws_apigatewayv2_integration.mock_health.id}"
}

resource "aws_apigatewayv2_integration" "mock_health" {
  api_id             = aws_apigatewayv2_api.webhook.id
  integration_type   = "MOCK"
  payload_format_version = "1.0"
}
