# Per-team read: each team runs its own Grafana, whose role can query ONLY that team's AMP
# workspace → hard read isolation in IAM (no shared Grafana, no reliance on Grafana orgs).
resource "aws_iam_role" "grafana_read" {
  for_each           = var.teams
  name               = "${var.cluster_name}-${each.key}-grafana-read"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy" "grafana_read" {
  for_each = var.teams
  name     = "amp-query"
  role     = aws_iam_role.grafana_read[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:QueryMetrics", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
      Resource = aws_prometheus_workspace.team[each.key].arn # ONLY this team's workspace
    }]
  })
}

resource "aws_eks_pod_identity_association" "grafana_read" {
  for_each        = var.teams
  cluster_name    = var.cluster_name
  namespace       = each.value.grafana_namespace
  service_account = each.value.grafana_sa
  role_arn        = aws_iam_role.grafana_read[each.key].arn
}

output "grafana_read_role_arns" {
  value = { for t, r in aws_iam_role.grafana_read : t => r.arn }
}
