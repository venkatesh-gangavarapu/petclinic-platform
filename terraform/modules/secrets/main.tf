# Non-RDS application secrets. RDS credentials are owned by the RDS module
# (PETPLAT-23) and must not be duplicated here.

# ── OpenAI API Key ────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "openai_api_key" {
  name        = "${var.project}/${var.environment}/openai-api-key"
  description = "OpenAI API key for genai-service"

  tags = {
    Name      = "${var.project}-${var.environment}-openai-api-key"
    Component = "secrets"
  }
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key
}
