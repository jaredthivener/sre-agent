resource "random_password" "db" {
  length  = 32
  special = false
}

resource "random_password" "nextauth_secret" {
  length  = 64
  special = false
}

resource "random_password" "salt" {
  length  = 32
  special = false
}

# Store generated credentials in Secrets Manager for Langfuse ECS task injection
resource "aws_secretsmanager_secret_version" "langfuse_nextauth" {
  secret_id     = "${var.app_name}/langfuse-nextauth-secret"
  secret_string = random_password.nextauth_secret.result
}

resource "aws_secretsmanager_secret_version" "langfuse_salt" {
  secret_id     = "${var.app_name}/langfuse-salt"
  secret_string = random_password.salt.result
}

# ── RDS Postgres via verified module ─────────────────────────────────────────

resource "aws_db_subnet_group" "langfuse" {
  name       = "${var.app_name}-langfuse"
  subnet_ids = var.private_subnet_ids
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2"

  identifier = "${var.app_name}-langfuse"

  engine               = "postgres"
  engine_version       = "16"
  family               = "postgres16"
  major_engine_version = "16"
  instance_class       = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name  = "langfuse"
  username = "langfuse"
  port     = 5432

  # Password managed separately; Secrets Manager rotation can be added later
  manage_master_user_password = false
  password                    = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.langfuse.name
  vpc_security_group_ids = [var.db_sg_id]

  multi_az               = false # set true for production HA
  deletion_protection    = true
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.app_name}-langfuse-final"

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  performance_insights_enabled = true
  monitoring_interval          = 60

  tags = { Name = "${var.app_name}-langfuse-db" }
}

# Store DB password in Secrets Manager for Langfuse task injection
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.app_name}/langfuse-db-password"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

# ── ElastiCache Redis via verified module ─────────────────────────────────────

module "elasticache" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "~> 1.0"

  cluster_id               = "${var.app_name}-langfuse"
  create_cluster           = true
  create_replication_group = false

  engine_version = "7.1"
  node_type      = var.redis_node_type
  num_cache_nodes = 1

  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.db_sg_id]

  tags = { Name = "${var.app_name}-langfuse-redis" }
}

# ── Langfuse ECS service ──────────────────────────────────────────────────────

resource "aws_ecs_cluster" "langfuse" {
  name = "${var.app_name}-langfuse"
  tags = { Name = "${var.app_name}-langfuse-cluster" }
}

resource "aws_ecs_task_definition" "langfuse" {
  family                   = "${var.app_name}-langfuse"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn

  container_definitions = jsonencode([{
    name      = "langfuse"
    image     = var.langfuse_image
    essential = true

    portMappings = [{ containerPort = 3000, protocol = "tcp" }]

    environment = [
      { name = "DATABASE_HOST", value = module.rds.db_instance_address },
      { name = "DATABASE_PORT", value = "5432" },
      { name = "DATABASE_NAME", value = "langfuse" },
      { name = "DATABASE_USERNAME", value = "langfuse" },
      { name = "REDIS_HOST", value = module.elasticache.cluster_cache_nodes[0].address },
      { name = "REDIS_PORT", value = "6379" },
      { name = "NEXTAUTH_URL", value = "http://langfuse.${var.app_name}.local:3000" },
      { name = "TELEMETRY_ENABLED", value = "false" },
    ]

    secrets = [
      { name = "DATABASE_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
      { name = "NEXTAUTH_SECRET", valueFrom = "${var.app_name}/langfuse-nextauth-secret" },
      { name = "SALT", valueFrom = "${var.app_name}/langfuse-salt" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "langfuse"
      }
    }
  }])
}

resource "aws_service_discovery_private_dns_namespace" "langfuse" {
  name = "${var.app_name}.local"
  vpc  = data.aws_vpc.current.id
}

resource "aws_service_discovery_service" "langfuse" {
  name = "langfuse"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.langfuse.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_service" "langfuse" {
  name            = "${var.app_name}-langfuse"
  cluster         = aws_ecs_cluster.langfuse.id
  task_definition = aws_ecs_task_definition.langfuse.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.langfuse_sg_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.langfuse.arn
  }
}

data "aws_vpc" "current" {
  filter {
    name   = "tag:Name"
    values = ["${var.app_name}-vpc"]
  }
}
