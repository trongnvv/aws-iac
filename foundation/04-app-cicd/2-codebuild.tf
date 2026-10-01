# Build stage of the pipeline: builds the server + client images (DinD) and pushes them to ECR.
# Source comes from the pipeline artifact (S3), so this role needs no GitLab access.
resource "aws_iam_role" "codebuild" {
  name = "codebuild-grpc-conn-debug"
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
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrManageAndPush"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository", # self-provision grpc-conn-debug/* on first push (no central IaC)
          "ecr:DescribeRepositories",
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
        ]
        Resource = local.grpc_arn
      },
      {
        Sid      = "PipelineArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = local.logs_arn
      },
    ]
  })
}

resource "aws_codebuild_project" "build" {
  name         = "grpc-conn-debug-build"
  service_role = aws_iam_role.codebuild.arn

  source { type = "CODEPIPELINE" } # buildspec.yml comes from the source artifact
  artifacts { type = "CODEPIPELINE" }

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true # DinD — builds Docker images
  }
}
