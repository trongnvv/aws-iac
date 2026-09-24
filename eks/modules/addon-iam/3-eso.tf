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
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.eso_secret_path}"
    }]
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
