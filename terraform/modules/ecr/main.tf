locals {
  # MUTABLE in dev (allows re-pushing same tag during development),
  # IMMUTABLE in prod (deployed tags cannot be overwritten).
  tag_mutability = var.environment == "prod" ? "IMMUTABLE" : "MUTABLE"
}

resource "aws_ecr_repository" "main" {
  for_each = toset(var.service_names)

  name                 = "${var.project}-${var.environment}/${each.value}"
  image_tag_mutability = local.tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = "${var.project}-${var.environment}/${each.value}"
    Component = "registry"
  }
}

resource "aws_ecr_lifecycle_policy" "main" {
  for_each   = aws_ecr_repository.main
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}
