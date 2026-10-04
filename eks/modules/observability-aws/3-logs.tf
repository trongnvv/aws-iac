# Fluent Bit (aws-for-fluent-bit) ships container stdout/stderr to CloudWatch Logs.
resource "aws_iam_role" "fluent_bit" {
  count              = local.native_pipeline ? 1 : 0
  name               = "${var.cluster_name}-fluent-bit"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy" "fluent_bit" {
  count = local.native_pipeline ? 1 : 0
  name  = "cloudwatch-logs-write"
  role  = aws_iam_role.fluent_bit[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:PutRetentionPolicy",
      ]
      Resource = "arn:aws:logs:${var.region}:*:log-group:/eks/${var.cluster_name}/*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "fluent_bit" {
  count           = local.native_pipeline ? 1 : 0
  cluster_name    = var.cluster_name
  namespace       = var.fluent_bit_namespace
  service_account = var.fluent_bit_service_account
  role_arn        = aws_iam_role.fluent_bit[0].arn
}
