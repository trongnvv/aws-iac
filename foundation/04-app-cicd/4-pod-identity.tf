# Pod Identity (no static keys): EKS hands this IAM role to the Image Updater pod via its
# ServiceAccount, so it can poll ECR for new tags with short-lived creds.
# Prereq: the eks-pod-identity-agent addon must be enabled on the cluster.
#
# NOTE: ArgoCD repo-server needs NO Pod Identity here — it pulls the helm/app OCI chart using the
# repo-ecr-helm secret that External Secrets Operator mints (ESO holds the ECR permission; see
# eks modules/addon-iam/3-eso.tf). Only Image Updater keeps a Pod Identity (tag polling).

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

# Image Updater: poll ECR for new grpc-conn-debug tags.
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
output "image_updater_ecr_role_arn" {
  value = aws_iam_role.image_updater_ecr.arn
}
