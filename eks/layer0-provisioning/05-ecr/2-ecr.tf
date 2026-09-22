# Private image registry. Basic scan-on-push is free; enhanced (Inspector) is gated.
resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repo_names)
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_inspector2_enabler" "ecr" {
  count          = var.enable_enhanced_scan ? 1 : 0
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["ECR"]
}

data "aws_caller_identity" "current" {}

output "repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
