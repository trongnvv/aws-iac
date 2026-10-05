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

# One AMP workspace per team ("tenant"). AMP has no per-workspace fee → N workspaces cost ≈ 1.
resource "aws_prometheus_workspace" "team" {
  for_each = var.teams
  alias    = "${var.cluster_name}-${each.key}"
}

# Per-team write role: aps:RemoteWrite ONLY to that team's workspace → hard write isolation.
resource "aws_iam_role" "amp_write" {
  for_each           = var.teams
  name               = "${var.cluster_name}-${each.key}-amp-write"
  assume_role_policy = local.pod_identity_trust
}

resource "aws_iam_role_policy" "amp_write" {
  for_each = var.teams
  name     = "remote-write"
  role     = aws_iam_role.amp_write[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:RemoteWrite"]
      Resource = aws_prometheus_workspace.team[each.key].arn
    }]
  })
}

# Bind the role to the team's collector SA — that collector can only write to its own workspace.
resource "aws_eks_pod_identity_association" "amp_write" {
  for_each        = var.teams
  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.collector_sa
  role_arn        = aws_iam_role.amp_write[each.key].arn
}

output "team_amp_endpoints" {
  description = "team -> AMP query endpoint (Grafana datasource URL, per org)"
  value       = { for t, w in aws_prometheus_workspace.team : t => w.prometheus_endpoint }
}

output "team_amp_remote_write" {
  description = "team -> AMP remote_write URL (the team collector's exporter target)"
  value       = { for t, w in aws_prometheus_workspace.team : t => "${w.prometheus_endpoint}api/v1/remote_write" }
}
