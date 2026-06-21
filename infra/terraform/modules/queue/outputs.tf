output "queue_url" {
  value = module.queue.queue_url
}

output "queue_arn" {
  value = module.queue.queue_arn
}

output "queue_name" {
  value = module.queue.queue_name
}

output "dlq_url" {
  value = module.dlq.queue_url
}

output "dlq_arn" {
  value = module.dlq.queue_arn
}
