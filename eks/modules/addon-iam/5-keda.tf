# KEDA operator role, granted via EKS Pod Identity to SA keda-operator.
# Read-only access to the metric sources KEDA scales on (CloudWatch, SQS).
resource "aws_iam_role" "keda" {
  name = "${var.cluster_name}-keda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "keda" {
  name = "metric-sources"
  role = aws_iam_role.keda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "keda" {
  cluster_name    = var.cluster_name
  namespace       = "keda"
  service_account = "keda-operator"
  role_arn        = aws_iam_role.keda.arn
}

output "keda_role_arn" {
  value = aws_iam_role.keda.arn
}
