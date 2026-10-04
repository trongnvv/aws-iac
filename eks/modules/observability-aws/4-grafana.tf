# Grafana (kube-prometheus-stack) reads AMP, CloudWatch (metrics + Logs) and X-Ray
# through the AWS SDK default chain → Pod Identity. Read-only.
resource "aws_iam_role" "grafana" {
  count              = local.native_pipeline ? 1 : 0
  name               = "${var.cluster_name}-grafana-read"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy_attachment" "grafana" {
  for_each = local.native_pipeline ? toset([
    "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess",
    "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess",
    "arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess",
  ]) : toset([])
  role       = aws_iam_role.grafana[0].name
  policy_arn = each.value
}

resource "aws_eks_pod_identity_association" "grafana" {
  count           = local.native_pipeline ? 1 : 0
  cluster_name    = var.cluster_name
  namespace       = var.prometheus_namespace
  service_account = var.grafana_service_account
  role_arn        = aws_iam_role.grafana[0].arn
}
