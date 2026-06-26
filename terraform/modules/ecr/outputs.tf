output "repository_urls" {
  description = "Map of service name to ECR repository URL"
  value       = { for name, repo in aws_ecr_repository.main : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service name to ECR repository ARN"
  value       = { for name, repo in aws_ecr_repository.main : name => repo.arn }
}

output "registry_url" {
  description = "Base ECR registry URL (account.dkr.ecr.region.amazonaws.com) for docker login"
  value       = "${split("/", aws_ecr_repository.main[var.service_names[0]].repository_url)[0]}"
}
