# Pod Identity (no static keys): EKS hands these IAM roles to the ArgoCD pods via their
# ServiceAccounts, so they can reach ECR with short-lived creds.
# Prereq: the eks-pod-identity-agent addon must be enabled on the cluster.

data "aws_iam_policy_document" "pod_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# --- ArgoCD repo-server: pull the helm/app OCI chart from ECR --------------------------
resource "aws_iam_role" "argocd_ecr" {
  name               = "eks-dev-argocd-ecr-read"
  assume_role_policy = data.aws_iam_policy_document.pod_trust.json
}

resource "aws_iam_role_policy" "argocd_ecr" {
  name = "ecr-read"
  role = aws_iam_role.argocd_ecr.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "Auth", Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      {
        Sid      = "PullChart"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability", "ecr:DescribeImages"]
        Resource = local.helm_arn
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "argocd_repo_server" {
  cluster_name    = var.cluster_name
  namespace       = var.argocd_namespace
  service_account = "argocd-repo-server"
  role_arn        = aws_iam_role.argocd_ecr.arn
}

# --- Image Updater: poll ECR for new grpc-conn-debug tags ------------------------------
resource "aws_iam_role" "image_updater_ecr" {
  name               = "eks-dev-image-updater-ecr-read"
  assume_role_policy = data.aws_iam_policy_document.pod_trust.json
}

resource "aws_iam_role_policy" "image_updater_ecr" {
  name = "ecr-read"
  role = aws_iam_role.image_updater_ecr.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "Auth", Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      {
        Sid      = "ListTags"
        Effect   = "Allow"
        Action   = ["ecr:DescribeImages", "ecr:ListImages", "ecr:BatchGetImage"]
        Resource = local.grpc_arn
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "image_updater" {
  cluster_name    = var.cluster_name
  namespace       = var.argocd_namespace
  service_account = "argocd-image-updater"
  role_arn        = aws_iam_role.image_updater_ecr.arn
}

output "pipeline_name" {
  value = aws_codepipeline.app.name
}
output "argocd_ecr_role_arn" {
  value = aws_iam_role.argocd_ecr.arn
}
output "image_updater_ecr_role_arn" {
  value = aws_iam_role.image_updater_ecr.arn
}
