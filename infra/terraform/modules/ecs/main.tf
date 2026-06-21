resource "aws_ssm_parameter" "otel_config" {
  name  = "${var.ssm_config_prefix}/otel-collector-config"
  type  = "String"
  value = file("${path.module}/otel-collector-config.yaml")
}

# ── ECS cluster ───────────────────────────────────────────────────────────────
# Using raw resource: the ecs module v7 restructured its interface significantly
# and a single cluster resource doesn't benefit from the module wrapper.

resource "aws_ecs_cluster" "main" {
  name = var.app_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.app_name}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 100
    base              = 1
  }
}

# ── Task definition ───────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "agent" {
  family                   = var.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.agent_cpu
  memory                   = var.agent_memory
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "sre-agent"
      image     = var.agent_image
      essential = true

      environment = [
        { name = "SQS_QUEUE_URL", value = var.sqs_queue_url },
        { name = "SECRETS_MANAGER_PREFIX", value = var.secrets_manager_prefix },
        { name = "AWS_SECRETS_REGION", value = var.aws_secrets_region },
        { name = "SSM_CONFIG_PREFIX", value = var.ssm_config_prefix },
        { name = "AWS_REGION", value = var.aws_region },
        # OTEL metrics/traces → ADOT sidecar on localhost
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://localhost:4318" },
        { name = "OTEL_SERVICE_NAME", value = "sre-agent" },
        { name = "OTEL_RESOURCE_ATTRIBUTES", value = "deployment.environment=production" },
        # Langfuse traces sent directly (OTLP per-signal override)
        { name = "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", value = "${var.langfuse_otlp_endpoint}" },
      ]

      secrets = [
        { name = "LANGFUSE_PUBLIC_KEY", valueFrom = var.langfuse_public_key_arn },
        { name = "LANGFUSE_SECRET_KEY", valueFrom = var.langfuse_secret_key_arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "agent"
        }
      }

      portMappings           = []
      readonlyRootFilesystem = true
      user                   = "10001"
      privileged             = false

      linuxParameters = {
        capabilities = { drop = ["ALL"], add = [] }
      }
    },

    {
      name      = "adot-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
      essential = false
      command   = ["--config=/etc/otel/config.yaml"]

      environment = [
        { name = "AWS_REGION", value = var.aws_region },
      ]

      secrets = [{
        name      = "AOT_CONFIG_CONTENT"
        valueFrom = aws_ssm_parameter.otel_config.arn
      }]

      portMappings = [
        { containerPort = 4317, protocol = "tcp" },
        { containerPort = 4318, protocol = "tcp" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "adot"
        }
      }
    }
  ])

  tags = { Name = "${var.app_name}-task" }
}

# ── ECS service ───────────────────────────────────────────────────────────────

resource "aws_ecs_service" "agent" {
  name                               = var.app_name
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.agent.arn
  desired_count                      = var.agent_desired_count
  launch_type                        = "FARGATE"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Name = "${var.app_name}-service" }
}
