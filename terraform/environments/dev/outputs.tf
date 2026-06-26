output "aws_region" {
  description = "AWS region in use"
  value       = var.aws_region
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.subnet_ids
}

output "eks_cluster_sg_id" {
  description = "EKS cluster security group ID"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "EKS node security group ID"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = module.vpc.alb_sg_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "EKS OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "node_role_arn" {
  description = "IAM role ARN for EKS worker nodes"
  value       = module.eks.node_role_arn
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster"
  value       = module.eks.kubeconfig_command
}

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = module.ecr.repository_urls
}

output "ecr_registry_url" {
  description = "Base ECR registry URL for docker login"
  value       = module.ecr.registry_url
}

output "cluster_node_sg_id" {
  description = "EKS-managed node security group ID (auto-created, attached to all managed node instances)"
  value       = module.eks.cluster_node_security_group_id
}

output "db_endpoint" {
  description = "RDS MySQL endpoint"
  value       = module.rds.db_endpoint
}

output "db_port" {
  description = "RDS MySQL port"
  value       = module.rds.db_port
}

output "jdbc_url" {
  description = "JDBC connection URL for Spring Boot services"
  value       = module.rds.jdbc_url
}

output "credentials_secret_arn" {
  description = "Secrets Manager ARN for RDS credentials (used by External Secrets Operator)"
  value       = module.rds.credentials_secret_arn
}
