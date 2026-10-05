# DRAFT / sketch — multi-tenant AWS-native observability (OBSERVABILITY.md §7, approach A).
# One AMP workspace + IAM per team ("tenant"); write isolation is hard (IAM), read isolation is
# by Grafana org (one shared Grafana). NOT wired into any env yet — kept for when we go multi-team.

variable "region" {
  default = "ap-southeast-1"
}

variable "cluster_name" {
  type = string
}

# One entry per team. Each team gets its own AMP workspace + write role (its collector) + read role
# (its own Grafana) — both scoped to that team's workspace → hard write AND read isolation in IAM.
variable "teams" {
  type = map(object({
    namespace         = string # the team's collector namespace (write)
    collector_sa      = string # the team's collector ServiceAccount (remote-writes to the team workspace)
    grafana_namespace = string # the team's Grafana namespace (read)
    grafana_sa        = string # the team's Grafana ServiceAccount (queries ONLY the team workspace)
  }))
  default = {}
  # example:
  # teams = {
  #   team-a = { namespace = "team-a", collector_sa = "adot-collector",
  #              grafana_namespace = "team-a", grafana_sa = "grafana" }
  #   team-b = { namespace = "team-b", collector_sa = "adot-collector",
  #              grafana_namespace = "team-b", grafana_sa = "grafana" }
  # }
}
