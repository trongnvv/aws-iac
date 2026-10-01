# GitLab connection (CodeConnections). Created in PENDING state; a human authorizes the
# OAuth handshake once in the console before any build can clone the source.
resource "aws_codeconnections_connection" "gitlab" {
  name          = "gitlab"
  provider_type = "GitLab"
}

# Register the connection as CodeBuild's credential for GitLab sources (account/region level).
resource "aws_codebuild_source_credential" "gitlab" {
  auth_type   = "CODECONNECTIONS"
  server_type = "GITLAB"
  token       = aws_codeconnections_connection.gitlab.arn
}

# Let the CodeBuild role clone through the connection (ECR/logs are in 2-codebuild-helm-chart.tf).
resource "aws_iam_role_policy" "use_connection" {
  name = "use-gitlab-connection"
  role = aws_iam_role.codebuild_helm_chart.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "codestar-connections:UseConnection",
        "codeconnections:UseConnection",
        "codeconnections:GetConnection",
        "codeconnections:GetConnectionToken",
      ]
      Resource = aws_codeconnections_connection.gitlab.arn
    }]
  })
}

# No privilegedMode: the pipeline only packages/pushes charts, it does not build Docker images.
resource "aws_codebuild_project" "helm_chart" {
  name         = "helm-chart-template-build"
  service_role = aws_iam_role.codebuild_helm_chart.arn

  source {
    type      = "GITLAB"
    location  = var.gitlab_repo_url
    buildspec = "buildspec.yml"
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = false
  }

  depends_on = [aws_codebuild_source_credential.gitlab]
}

# Trigger on push to main.
resource "aws_codebuild_webhook" "helm_chart" {
  project_name = aws_codebuild_project.helm_chart.name

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }
    filter {
      type    = "HEAD_REF"
      pattern = "^refs/heads/main$"
    }
  }
}

output "gitlab_connection_arn" {
  value = aws_codeconnections_connection.gitlab.arn
}
