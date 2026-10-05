# DRAFT / sketch — multi-tenant AWS-native observability (OBSERVABILITY.md §7, approach A).
# One AMP workspace + IAM per team ("tenant"); write isolation is hard (IAM), read isolation is
# by Grafana org (one shared Grafana). NOT wired into any env yet — kept for when we go multi-team.

variable "region" {
  default = "ap-southeast-1"
}

variable "cluster_name" {
  type = string
}

# One entry per team. Each team gets its own AMP workspace + amp-write role, bound by Pod Identity
# to that team's metrics collector (ADOT or kube-prometheus-stack Prometheus) in its namespace.
variable "teams" {
  type = map(object({
    namespace    = string # the team's collector namespace
    collector_sa = string # the team's collector ServiceAccount (remote-writes to the team workspace)
  }))
  default = {}
  # example:
  # teams = {
  #   team-a = { namespace = "team-a", collector_sa = "adot-collector" }
  #   team-b = { namespace = "team-b", collector_sa = "adot-collector" }
  # }
}

# The shared Grafana's ServiceAccount — gets read (query) on every team workspace; per-team
# visibility is enforced at the Grafana ORG level (datasource per org), not by IAM.
variable "grafana_namespace" {
  default = "monitoring"
}

variable "grafana_service_account" {
  default = "kube-prometheus-stack-grafana"
}
