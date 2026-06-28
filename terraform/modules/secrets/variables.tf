variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "openai_api_key" {
  description = "OpenAI API key for the genai-service. Defaults to 'demo' which disables AI features gracefully."
  type        = string
  default     = "demo"
  sensitive   = true
}
