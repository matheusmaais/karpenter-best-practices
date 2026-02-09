output "karpenter_role_arn" {
  description = "ARN of the Karpenter controller IAM role"
  value       = module.karpenter.iam_role_arn
}

output "karpenter_node_role_arn" {
  description = "ARN of the Karpenter node IAM role"
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_queue_name" {
  description = "Name of the SQS queue for spot interruption handling"
  value       = module.karpenter.queue_name
}

output "nodepool_name" {
  description = "Name of the created NodePool"
  value       = "default"
}
