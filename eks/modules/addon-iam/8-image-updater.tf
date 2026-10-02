# Argo CD Image Updater — polls ECR for new image tags. Granted via EKS Pod Identity.
resource "aws_iam_role" "image_updater" {
  name = "${var.cluster_name}-image-updater"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# Read-only: list tags on any repo (Image Updater watches app images; metadata-only, low risk).
resource "aws_iam_role_policy" "image_updater" {
  name = "ecr-read"
  role = aws_iam_role.image_updater.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "Auth", Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" },
      {
        Sid      = "ListTags"
        Effect   = "Allow"
        Action   = ["ecr:DescribeImages", "ecr:ListImages", "ecr:BatchGetImage"]
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
    ]
  })
}

# ns + service_account must match the Helm release (02-platform/02-image-updater).
resource "aws_eks_pod_identity_association" "image_updater" {
  cluster_name    = var.cluster_name
  namespace       = "argocd"
  service_account = "argocd-image-updater"
  role_arn        = aws_iam_role.image_updater.arn
}

output "image_updater_role_arn" {
  value = aws_iam_role.image_updater.arn
}
