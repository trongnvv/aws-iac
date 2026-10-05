# Alerting, AWS-native (test-plans/03 §A7) — replaces Grafana OnCall.
#   AMP rule groups (what fires) → AMP managed Alert Manager (routes by `team` label)
#   → per-team SNS topic → optional AWS Chatbot (Slack).
# On-call/escalation (Incident Manager / PagerDuty) is out of scope: subscribe it to the same SNS.
# All gated by enable_alerting (requires enable_amp). A `default` topic is always created so alerts
# with no matching `team` label still land somewhere.
locals {
  alerting   = var.enable_amp && var.enable_alerting
  topic_keys = local.alerting ? concat(["default"], keys(var.alert_teams)) : []
  # teams that also want Slack delivery (need a channel id + an authorized workspace)
  chatbot_teams = (local.alerting && var.alert_slack_workspace_id != "") ? {
    for t, c in var.alert_teams : t => c.slack_channel_id if try(c.slack_channel_id, null) != null
  } : {}
}

data "aws_caller_identity" "current" {}

# ── SNS: one topic per team (+ default) ──────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  for_each = toset(local.topic_keys)
  name     = "${var.cluster_name}-alerts-${each.key}"
}

# Let AMP's managed Alert Manager publish (sns_configs runs under the AMP service identity).
resource "aws_sns_topic_policy" "alerts" {
  for_each = aws_sns_topic.alerts
  arn      = each.value.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAMPPublish"
      Effect    = "Allow"
      Principal = { Service = "aps.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = each.value.arn
      Condition = {
        ArnEquals    = { "aws:SourceArn" = aws_prometheus_workspace.this[0].arn }
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

# ── AMP rule groups — authored as YAML files in the env, shipped here via file() ──────────────
# One AMP rule-group namespace per entry in var.alert_rule_groups (name → YAML content, bare
# `groups:` schema like a PrometheusRule body). The env owns the files, so rules stay plain YAML.
# Alerts route per-team only if the series carry a `team` label (add via remote-write relabeling);
# otherwise they fall through to the `default` topic.
resource "aws_prometheus_rule_group_namespace" "this" {
  for_each     = local.alerting ? var.alert_rule_groups : {}
  name         = each.key
  workspace_id = aws_prometheus_workspace.this[0].id
  data         = each.value
}

# ── AMP managed Alert Manager — route tree by `team` label → per-team SNS ─────
resource "aws_prometheus_alert_manager_definition" "this" {
  count        = local.alerting ? 1 : 0
  workspace_id = aws_prometheus_workspace.this[0].id
  # AMP wants `alertmanager_config` as a YAML *string* (the Alertmanager config), not a nested map
  # → inner yamlencode renders the config to a string, outer wraps it under the key.
  definition = yamlencode({
    alertmanager_config = yamlencode({
      route = {
        receiver = "sns-default"
        group_by = ["alertname", "team"]
        routes = [for t in keys(var.alert_teams) : {
          matchers = [format("team=%q", t)]
          receiver = "sns-${t}"
        }]
      }
      receivers = [for k in local.topic_keys : {
        name = "sns-${k}"
        sns_configs = [{
          topic_arn = aws_sns_topic.alerts[k].arn
          sigv4     = { region = var.region }
        }]
      }]
    })
  })
}

# ── AWS Chatbot (Slack) — optional delivery leg ──────────────────────────────
# Prereqs (manual, one-time): authorize the Slack workspace in the AWS Chatbot console and pass its
# workspace id as alert_slack_workspace_id; put each team's Slack channel id in alert_teams. Chatbot's
# API lives in us-east-1 — wire a us-east-1 provider alias in the env root if these fail on apply.
resource "aws_iam_role" "chatbot" {
  count = length(local.chatbot_teams) > 0 ? 1 : 0
  name  = "${var.cluster_name}-chatbot"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "chatbot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "chatbot" {
  count      = length(local.chatbot_teams) > 0 ? 1 : 0
  role       = aws_iam_role.chatbot[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_chatbot_slack_channel_configuration" "team" {
  for_each           = local.chatbot_teams
  configuration_name = "${var.cluster_name}-${each.key}"
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_channel_id   = each.value
  slack_team_id      = var.alert_slack_workspace_id
  sns_topic_arns     = [aws_sns_topic.alerts[each.key].arn]
}

output "alert_sns_topic_arns" {
  value = { for k, t in aws_sns_topic.alerts : k => t.arn }
}
