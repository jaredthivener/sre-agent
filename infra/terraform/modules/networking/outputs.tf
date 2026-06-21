output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "ecs_sg_id" {
  value = module.ecs_agent_sg.security_group_id
}

output "lambda_sg_id" {
  value = module.lambda_authorizer_sg.security_group_id
}

output "langfuse_sg_id" {
  value = module.langfuse_sg.security_group_id
}

output "db_sg_id" {
  value = module.db_sg.security_group_id
}
