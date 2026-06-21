data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "apigw_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

# ── ECS task role — what the running agent container can do ───────────────────

resource "aws_iam_role" "ecs_task" {
  name               = "${var.app_name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "ecs_task" {
  # Secrets Manager — read all secrets under the sre-agent/ prefix
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.app_name}/*",
    ]
  }

  # SSM Parameter Store — read non-sensitive config
  statement {
    sid    = "SSMParameterRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.app_name}/*",
    ]
  }

  # SQS — consume from main queue, move to DLQ is automatic (no explicit permission needed)
  statement {
    sid    = "SQSConsume"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [var.sqs_queue_arn, var.dlq_arn]
  }

  # CloudWatch Logs — write investigation logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/sre-agent/*:*",
    ]
  }

  # CloudWatch metrics — ADOT sidecar writes EMF metrics
  statement {
    sid    = "CloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricData",
      "cloudwatch:ListMetrics",
    ]
    resources = ["*"]
  }

  # X-Ray — ADOT sidecar sends traces
  statement {
    sid    = "XRayWrite"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
    ]
    resources = ["*"]
  }

  # Read-only AWS investigation permissions (mirrors deploy/iam-permissions-policy.json)
  statement {
    sid    = "AWSReadOnlyInvestigation"
    effect = "Allow"
    actions = [
      "cloudwatch:Describe*", "cloudwatch:Get*", "cloudwatch:List*",
      "logs:Describe*", "logs:Filter*", "logs:Get*", "logs:List*", "logs:StartQuery", "logs:GetQueryResults", "logs:StopQuery",
      "cloudtrail:LookupEvents", "cloudtrail:GetTrail", "cloudtrail:GetTrailStatus", "cloudtrail:DescribeTrails", "cloudtrail:ListTrails",
      "ecs:Describe*", "ecs:List*",
      "lambda:Get*", "lambda:List*",
      "apigateway:GET",
      "elasticloadbalancing:Describe*",
      "rds:Describe*", "rds:List*",
      "dynamodb:Describe*", "dynamodb:List*",
      "sqs:List*", "sqs:Get*",
      "sns:List*", "sns:Get*",
      "kinesis:Describe*", "kinesis:List*", "kinesis:Get*",
      "ec2:Describe*",
      "autoscaling:Describe*",
      "application-autoscaling:Describe*",
      "ssm:Describe*", "ssm:List*",
      "health:Describe*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  name   = "${var.app_name}-ecs-task-policy"
  role   = aws_iam_role.ecs_task.id
  policy = data.aws_iam_policy_document.ecs_task.json
}

# ── ECS execution role — what ECS control plane can do on the task's behalf ───

resource "aws_iam_role" "ecs_execution" {
  name               = "${var.app_name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_execution_extra" {
  statement {
    sid    = "SecretsManagerForTaskEnv"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.app_name}/*",
    ]
  }
}

resource "aws_iam_role_policy" "ecs_execution_extra" {
  name   = "${var.app_name}-ecs-execution-secrets"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution_extra.json
}

# ── Lambda authorizer role ────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_authorizer" {
  name               = "${var.app_name}-lambda-authorizer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_authorizer" {
  statement {
    sid    = "SecretsManagerWebhookSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.app_name}/pagerduty-webhook-secret*",
    ]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # VPC networking permissions for Lambda in VPC
  statement {
    sid    = "VPCAccess"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_authorizer" {
  name   = "${var.app_name}-lambda-authorizer-policy"
  role   = aws_iam_role.lambda_authorizer.id
  policy = data.aws_iam_policy_document.lambda_authorizer.json
}

# ── API Gateway role — SendMessage to SQS ────────────────────────────────────

resource "aws_iam_role" "api_gateway" {
  name               = "${var.app_name}-api-gateway"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

data "aws_iam_policy_document" "api_gateway" {
  statement {
    sid    = "SQSSendMessage"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
    ]
    resources = [var.sqs_queue_arn]
  }
}

resource "aws_iam_role_policy" "api_gateway" {
  name   = "${var.app_name}-api-gateway-policy"
  role   = aws_iam_role.api_gateway.id
  policy = data.aws_iam_policy_document.api_gateway.json
}
