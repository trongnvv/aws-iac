# Managed Prometheus workspace — the collector remote-writes here instead of
# self-hosting Prometheus long-term storage. All gated by enable_amp.
resource "aws_prometheus_workspace" "this" {
  count = var.enable_amp ? 1 : 0
  alias = "${var.cluster_name}-amp"
}

# Trust policy shared by every Pod Identity role in this module.
locals {
  pod_identity_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role" "amp_write" {
  count              = var.enable_amp ? 1 : 0
  name               = "${var.cluster_name}-amp-write"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy" "amp_write" {
  count = var.enable_amp ? 1 : 0
  name  = "remote-write"
  role  = aws_iam_role.amp_write[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:RemoteWrite"]
      Resource = aws_prometheus_workspace.this[0].arn
    }]
  })
}

resource "aws_eks_pod_identity_association" "amp_write" {
  count           = var.enable_amp ? 1 : 0
  cluster_name    = var.cluster_name
  namespace       = var.collector_namespace
  service_account = var.collector_service_account
  role_arn        = aws_iam_role.amp_write[0].arn
}

# ADOT also ships traces to X-Ray (awsxray exporter).
resource "aws_iam_role_policy_attachment" "amp_write_xray" {
  count      = var.enable_amp ? 1 : 0
  role       = aws_iam_role.amp_write[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

# kube-prometheus-stack Prometheus remote-writes infra metrics with the same role.
resource "aws_eks_pod_identity_association" "prometheus" {
  count           = var.enable_amp ? 1 : 0
  cluster_name    = var.cluster_name
  namespace       = var.prometheus_namespace
  service_account = var.prometheus_service_account
  role_arn        = aws_iam_role.amp_write[0].arn
}

output "amp_workspace_arn" {
  value = var.enable_amp ? aws_prometheus_workspace.this[0].arn : null
}

output "amp_remote_write_url" {
  value = var.enable_amp ? "${aws_prometheus_workspace.this[0].prometheus_endpoint}api/v1/remote_write" : null
}

# Workspace root (no api/v1/...) — the Grafana datasource URL.
output "amp_endpoint" {
  value = var.enable_amp ? aws_prometheus_workspace.this[0].prometheus_endpoint : null
}
