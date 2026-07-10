output "cluster_endpoint" {
  description = "Endpoint for the EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group IDs attached to the EKS control plane"
  value       = module.eks.cluster_security_group_id
}

data "aws_region" "current" {}

output "region" {
  description = "AWS region in which resources are deployed"
  value       = data.aws_region.current.name
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

# The eks module (v19.21.0) exposes `eks_managed_node_groups` as a MAP of node
# groups, not flat lists. Loop over that map to pull each group's arn / id.
output "node_group_arns" {
  description = "ARNs of the EKS managed node groups"
  value       = [for ng in module.eks.eks_managed_node_groups : ng.node_group_arn]
}

output "node_group_ids" {
  description = "IDs of the EKS managed node groups"
  value       = [for ng in module.eks.eks_managed_node_groups : ng.node_group_id]
}

output "vpc_id" {
  description = "VPC ID where the EKS cluster is deployed"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}
