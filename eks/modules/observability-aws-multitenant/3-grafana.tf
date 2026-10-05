# One shared Grafana reads EVERY team workspace (read isolation is by Grafana org, not IAM).
# For hard read isolation, give each team its own Grafana/AMG workspace with a role scoped to one
# AMP workspace instead.
resource "aws_iam_role" "grafana_read" {
  count              = length(var.teams) > 0 ? 1 : 0
  name               = "${var.cluster_name}-grafana-read"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy" "grafana_read" {
  count = length(var.teams) > 0 ? 1 : 0
  name  = "amp-query"
  role  = aws_iam_role.grafana_read[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:QueryMetrics", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
      Resource = [for w in aws_prometheus_workspace.team : w.arn]
    }]
  })
}

resource "aws_eks_pod_identity_association" "grafana_read" {
  count           = length(var.teams) > 0 ? 1 : 0
  cluster_name    = var.cluster_name
  namespace       = var.grafana_namespace
  service_account = var.grafana_service_account
  role_arn        = aws_iam_role.grafana_read[0].arn
}

output "grafana_read_role_arn" {
  value = length(var.teams) > 0 ? aws_iam_role.grafana_read[0].arn : null
}
