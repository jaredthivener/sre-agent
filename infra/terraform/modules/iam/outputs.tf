output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "ecs_execution_role_arn" {
  value = aws_iam_role.ecs_execution.arn
}

output "lambda_authorizer_role_arn" {
  value = aws_iam_role.lambda_authorizer.arn
}

output "api_gateway_role_arn" {
  value = aws_iam_role.api_gateway.arn
}
