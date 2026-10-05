variable "region" {
  default = "ap-southeast-1"
}

variable "env" {
  default = "dev"
}

# The whole AWS-native pipeline (test-plans/03 Part A): AMP workspace + ADOT (metrics + X-Ray) +
# kube-prometheus-stack Prometheus remote-write + Fluent Bit → CloudWatch Logs + Grafana reading
# AMP/CloudWatch/X-Ray. One switch (the layer2 07-observability-aws helmfile deploys all of it, so
# splitting the IAM would leave pods without Pod Identity). AMP bills per sample → default off.
variable "enable_amp" {
  default = false
}

# namespace + service account of the metrics collector (layer2 chart) that
# remote-writes to AMP. Must match the Helm release.
variable "collector_namespace" {
  default = "opentelemetry"
}

variable "collector_service_account" {
  default = "adot-collector"
}

# Wired from the eks module output by the env root.
variable "cluster_name" {
  type = string
}

# Service accounts below must match the Helm releases (kube-prometheus-stack in
# `monitoring`, aws-for-fluent-bit in `logging`).
variable "prometheus_namespace" {
  default = "monitoring"
}

variable "prometheus_service_account" {
  default = "kube-prometheus-stack-prometheus"
}

variable "grafana_service_account" {
  default = "kube-prometheus-stack-grafana"
}

variable "fluent_bit_namespace" {
  default = "logging"
}

variable "fluent_bit_service_account" {
  default = "aws-for-fluent-bit"
}

# ── Alerting (test-plans/03 §A7) ─────────────────────────────────────────────
# AMP rule groups + managed Alert Manager → SNS → optional AWS Chatbot. Replaces Grafana OnCall.
# Requires enable_amp. Essentially free (SNS cents), so safe to turn on per-env.
variable "enable_alerting" {
  default = false
}

# Per-team routing. Each key = a `team` label value → its own SNS topic; Alert Manager routes alerts
# carrying `team=<key>` there. slack_channel_id (optional) wires Chatbot to that topic. Alerts with no
# matching team go to the always-created `default` topic.
variable "alert_teams" {
  type = map(object({
    slack_channel_id = optional(string)
  }))
  default = {}
}

# Slack workspace (team) id authorized once in the AWS Chatbot console (Chatbot can't authorize a
# workspace via API). Empty = SNS-only, no Chatbot. See test-plans/03 §A7 for the manual step.
variable "alert_slack_workspace_id" {
  default = ""
}

# AMP rule-group namespaces: name → YAML content (bare `groups:` schema, like a PrometheusRule body).
# The env reads its rules/*.yaml with file() and passes them here, so rules stay authored as plain YAML.
variable "alert_rule_groups" {
  type    = map(string)
  default = {}
}
