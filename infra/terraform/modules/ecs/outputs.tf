output "cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.agent.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.agent.arn
}
