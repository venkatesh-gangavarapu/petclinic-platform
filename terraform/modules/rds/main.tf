locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ── Master Password ───────────────────────────────────────────────────────────
# Excludes characters that break JDBC URLs or shell quoting (@, /, ", ', `, \).

resource "random_password" "db_master" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ── Secrets Manager — RDS Credentials ────────────────────────────────────────

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project}/${var.environment}/rds-credentials"
  description = "RDS master credentials for ${local.name_prefix}-mysql"

  tags = {
    Name      = "${local.name_prefix}-rds-credentials"
    Component = "database"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_master.result
  })
}

# ── DB Subnet Group ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Subnet group for ${local.name_prefix} RDS instance"
  subnet_ids  = var.subnet_ids

  tags = {
    Name      = "${local.name_prefix}-db-subnet-group"
    Component = "database"
  }
}

# ── Parameter Group ───────────────────────────────────────────────────────────

resource "aws_db_parameter_group" "main" {
  name        = "${local.name_prefix}-mysql8"
  family      = "mysql8.0"
  description = "Parameter group for ${local.name_prefix} - utf8mb4 character set"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name      = "${local.name_prefix}-mysql8"
    Component = "database"
  }
}

# ── RDS Instance ──────────────────────────────────────────────────────────────

resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-mysql"

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot
  deletion_protection     = var.deletion_protection
  apply_immediately       = var.apply_immediately

  tags = {
    Name      = "${local.name_prefix}-mysql"
    Component = "database"
  }

  depends_on = [aws_secretsmanager_secret_version.db_credentials]
}
