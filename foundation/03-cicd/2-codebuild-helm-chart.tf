locals {
  # ECR repos the Helm chart pipeline manages/pushes (self-provisioned at build time under helm/*)
  helm_repo_arn  = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/helm/*"
  build_logs_arn = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/helm-chart-template-build*"
}

# CodeBuild role for the Helm chart pipeline (gitlab trongnvv-platform/helm-chart-template).
# Lives in central IaC because it grants account-level permissions; the pipeline itself
# self-provisions its ECR repos under helm/* at build time (so no ECR repo is declared here).
resource "aws_iam_role" "codebuild_helm_chart" {
  name = "codebuild-helm-chart"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Least-privilege: create + push only under helm/*, and write only its own build log group.
resource "aws_iam_role_policy" "ecr_helm_push" {
  name = "ecr-helm-push"
  role = aws_iam_role.codebuild_helm_chart.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthToken" # account-level, cannot be resource-scoped
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrManageHelmRepos"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
        ]
        Resource = local.helm_repo_arn
      },
      {
        Sid    = "EcrPushHelmCharts"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage", # helm push HEADs the manifest to check existence (registry-v2 API)
        ]
        Resource = local.helm_repo_arn
      },
      {
        Sid    = "CodeBuildLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = local.build_logs_arn
      },
    ]
  })
}

output "codebuild_helm_chart_role_arn" {
  value = aws_iam_role.codebuild_helm_chart.arn
}
