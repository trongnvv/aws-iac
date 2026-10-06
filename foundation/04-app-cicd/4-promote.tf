# Promote: on a git tag (rc-* or semver), retag the d-<sha> image to the release tag — same
# digest, no rebuild (aws ecr put-image on the existing manifest). Standalone CodeBuild with a
# GitLab source (reuses the account-level CodeConnections credential registered by 03-cicd),
# triggered by a webhook on tag pushes.

# Let the CodeBuild role clone through the connection (ECR put/get are already in 2-codebuild.tf).
resource "aws_iam_role_policy" "use_connection" {
  name = "use-gitlab-connection"
  role = aws_iam_role.codebuild.id
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
      Resource = local.conn_arn
    }]
  })
}

resource "aws_codebuild_project" "promote" {
  name         = "grpc-conn-debug-promote"
  service_role = aws_iam_role.codebuild.arn

  source {
    type      = "GITLAB"
    location  = "https://gitlab.com/${var.app_repo_id}.git"
    buildspec = "buildspec.yml" # same file as the build; it detects promote mode from the tag trigger
  }
  artifacts { type = "NO_ARTIFACTS" }

  environment {
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    compute_type = "BUILD_GENERAL1_SMALL"
    # no privilegedMode: promote only retags (put-image), it does not build images

    environment_variable {
      name  = "GITLAB_USER" # deploy-token username — buildspec commits the promoted tag (stg/prod)
      value = "${var.gitlab_token_secret}:username"
      type  = "SECRETS_MANAGER"
    }
    environment_variable {
      name  = "GITLAB_TOKEN"
      value = "${var.gitlab_token_secret}:password"
      type  = "SECRETS_MANAGER"
    }
  }
}

# Trigger on git tags: rc-* (staging) and plain semver (prod).
resource "aws_codebuild_webhook" "promote" {
  project_name = aws_codebuild_project.promote.name

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }
    filter {
      type    = "HEAD_REF"
      pattern = "^refs/tags/(rc-.*|[0-9].*)$"
    }
  }
}
