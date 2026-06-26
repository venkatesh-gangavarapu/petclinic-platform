output "db_endpoint" {
  description = "RDS instance endpoint (hostname only, without port)"
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

output "db_name" {
  description = "Name of the initial database"
  value       = aws_db_instance.main.db_name
}

output "jdbc_url" {
  description = "JDBC connection URL for Spring Boot datasource configuration"
  value       = "jdbc:mysql://${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
}

output "credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret holding RDS credentials (used by External Secrets Operator)"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "credentials_secret_name" {
  description = "Name of the Secrets Manager secret holding RDS credentials"
  value       = aws_secretsmanager_secret.db_credentials.name
}
