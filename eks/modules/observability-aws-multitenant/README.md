# modules/observability-aws-multitenant — DRAFT

Multi-tenant AWS-native metrics (see `docs/OBSERVABILITY.md` §7). **Draft — not wired into any env.**
One AMP **workspace per team** (tenant → workspace), with **hard write AND read isolation in IAM**:
each team's collector writes only to its workspace, and each team's Grafana reads only its workspace.

**Scope — AWS-only.** Per team in `var.teams` this creates: an AMP workspace, an `amp-write` role
(collector), a `grafana-read` role (that team's Grafana), and the Pod Identity bindings — all scoped
to that one workspace. It does **not** deploy Grafana/collectors or create dashboards/users; it only
provisions the AWS substrate + IAM they bind to.

## What it creates (per team)
| Resource | Scope |
|---|---|
| `aws_prometheus_workspace` `<cluster>-<team>` | the team's tenant |
| `amp-write` role + Pod Identity (collector SA) | `aps:RemoteWrite` → **only** this workspace |
| `grafana-read` role + Pod Identity (team Grafana SA) | `aps:Query*` → **only** this workspace |

## Isolation
| | Mechanism | Hard? |
|---|---|---|
| Write (team → its workspace) | per-team `amp-write` IAM role | ✅ hard |
| Read (team sees only its metrics) | per-team `grafana-read` IAM role (own Grafana) | ✅ hard |

→ Cost of hard read: **each team runs its own Grafana** (or AMG workspace). Heavier than one shared
Grafana. If you prefer a single Grafana, see the alternative below (read isolation becomes soft).

## How to wire (00-infra)
```hcl
module "observability_aws" {
  source       = "../../../../modules/observability-aws-multitenant"
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
  teams = {
    team-a = { namespace = "team-a", collector_sa = "adot-collector", grafana_namespace = "team-a", grafana_sa = "grafana" }
    team-b = { namespace = "team-b", collector_sa = "adot-collector", grafana_namespace = "team-b", grafana_sa = "grafana" }
  }
}
output "team_amp_remote_write"  { value = module.observability_aws.team_amp_remote_write }
output "team_amp_endpoints"     { value = module.observability_aws.team_amp_endpoints }
output "grafana_read_role_arns" { value = module.observability_aws.grafana_read_role_arns }
```

## 02-platform (what you deploy per team)
- **Collector** (ADOT / kube-prometheus-stack) in the team ns, remote-write to `team_amp_remote_write[<team>]`.
- **Grafana** in the team ns (SA = the `grafana_sa` you passed), one AMP datasource → `team_amp_endpoints[<team>]`
  (sigv4, via the team's `grafana-read` Pod Identity). The team only sees its own workspace.

## Alternative — one shared Grafana + org per team (soft read)
If you don't want N Grafanas: run one Grafana, give it a single role that can query all workspaces,
and split teams by **Grafana org** (datasource per org). Read isolation is then at the org layer
(Grafana config, not IAM) — softer, but one Grafana to run. That variant replaces the per-team
`grafana-read` here with a single all-workspace role; see `docs/OBSERVABILITY.md` §7.
