# External Secrets Operator role, granted via EKS Pod Identity.
resource "aws_iam_role" "eso" {
  name = "${var.cluster_name}-external-secrets"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# Least privilege: read-only, scoped to the configured secret path.
resource "aws_iam_role_policy" "eso" {
  name = "read-secrets"
  role = aws_iam_role.eso.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.eso_secret_path}"
      },
      {
        # ECRAuthorizationToken generator mints the token for ArgoCD's OCI chart pull.
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        # The minted token carries THIS role's identity, so the actual pull (ArgoCD using the
        # token) is authorized as eso — it needs the chart-pull perms on helm/*, not just auth.
        Sid      = "EcrPullHelmCharts"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = "arn:aws:ecr:${var.region}:${data.aws_caller_identity.current.account_id}:repository/helm/*"
      },
    ]
  })
}

# namespace + service_account must match the Helm release (layer1/05).
resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso.arn
}

output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}
