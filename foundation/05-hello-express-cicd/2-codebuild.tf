# One standalone CodeBuild for hello-express: webhook on main (test → build → push d-<sha>) and
# on git tags (promote: retag d-<sha> → rc-1.1.1/1.1.1). Mode is decided in buildspec.yml by the
# trigger. ECR repo `hello-express` self-provisioned on first build. Reuses the 03-cicd connection.
resource "aws_iam_role" "codebuild" {
  name = "codebuild-hello-express"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "build-push"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "EcrAuth", Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      {
        Sid    = "EcrManageAndPush"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository", "ecr:DescribeRepositories",
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage",
        ]
        Resource = local.ecr_arn
      },
      {
        Sid      = "UseConnection"
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = local.conn_arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = local.logs_arn
      },
      {
        # GitLab PAT so the buildspec can commit the image tag into the gitops repo (push model).
        Sid      = "GitLabToken"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:${var.region}:${local.account}:secret:${var.gitlab_token_secret}-*"
      },
      # For SAST later: allow reading the Sonar token secret (uncomment when you add it).
      # { Sid = "SonarToken", Effect = "Allow", Action = "secretsmanager:GetSecretValue",
      #   Resource = "arn:aws:secretsmanager:${var.region}:${local.account}:secret:sonar/*" },
    ]
  })
}

resource "aws_codebuild_project" "build" {
  name         = "hello-express-build"
  service_role = aws_iam_role.codebuild.arn

  source {
    type      = "GITLAB"
    location  = "https://gitlab.com/${var.app_repo_id}.git"
    buildspec = "buildspec.yml"
  }
  artifacts { type = "NO_ARTIFACTS" }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/standard:7.0" # Ubuntu 22.04 — has Node + Docker
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true # DinD for docker build

    environment_variable {
      name  = "GITLAB_USER" # deploy-token username — buildspec commits the image tag into the gitops repo
      value = "${var.gitlab_token_secret}:username"
      type  = "SECRETS_MANAGER"
    }
    environment_variable {
      name  = "GITLAB_TOKEN"
      value = "${var.gitlab_token_secret}:password"
      type  = "SECRETS_MANAGER"
    }

    # SAST (Sonar) — set these later, then the buildspec runs the scan (skipped while unset):
    # environment_variable { name = "SONAR_HOST_URL", value = "https://sonar.example" }
    # environment_variable { name = "SONAR_TOKEN", value = "sonar/token", type = "SECRETS_MANAGER" }
  }
}

# Trigger on push to main (build) and on git tags rc-*/semver (promote).
resource "aws_codebuild_webhook" "build" {
  project_name = aws_codebuild_project.build.name

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

output "codebuild_role_arn" {
  value = aws_iam_role.codebuild.arn
}
