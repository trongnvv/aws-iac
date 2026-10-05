# modules/observability-aws-multitenant — DRAFT

Multi-tenant AWS-native metrics (see `docs/OBSERVABILITY.md` §7, approach A). **Draft — not wired
into any env.** Swaps the single-workspace `observability-aws` module for **one AMP workspace per
team**: tenant → workspace. Keep this until we actually go multi-team.

**Scope — this module is AWS-only.** It creates, per team in `var.teams`: an AMP workspace, an
`amp-write` IAM role scoped to that workspace, and the Pod Identity binding — **that's it** (plus one
shared `grafana-read` role that can query *all* workspaces). It does **not** create Grafana orgs,
datasources, users, or any read isolation — those are Grafana config, outside Terraform, sketched
below only. So on its own this module gives **hard write isolation and NO read isolation**; read
isolation only exists once you build the Grafana org-per-team setup separately.

## What it creates (per team in `var.teams`)
- `aws_prometheus_workspace` `<cluster>-<team>` — the team's tenant.
- `aws_iam_role` `<cluster>-<team>-amp-write` + Pod Identity on the team's collector SA →
  `aps:RemoteWrite` **only to that workspace** = hard write isolation.
- One shared `aws_iam_role` `<cluster>-grafana-read` (query on **all** team workspaces), bound to
  the Grafana SA. Read isolation is at the **Grafana org** level (datasource per org), not IAM.

## How to wire (00-infra)
```hcl
module "observability_aws" {
  source       = "../../../../modules/observability-aws-multitenant"
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
  teams = {
    team-a = { namespace = "team-a", collector_sa = "adot-collector" }
    team-b = { namespace = "team-b", collector_sa = "adot-collector" }
  }
}
output "team_amp_remote_write" { value = module.observability_aws.team_amp_remote_write }
output "team_amp_endpoints"    { value = module.observability_aws.team_amp_endpoints }
```

## Per-team collector (02-platform)
Each team runs its own collector (ADOT / kube-prometheus-stack) in its namespace, remote-writing to
**its** workspace (`team_amp_remote_write[<team>]`). Pod Identity gives it only that workspace →
team-a cannot write team-b's metrics.

## Grafana: org per team (sketch)
One shared Grafana, one **org per team**, each org a datasource → that team's AMP endpoint (sigv4,
via the `grafana-read` Pod Identity). Users are mapped to their org + role → they only see their
tenant. Orgs/datasources need provisioning (Grafana API / sidecar) — the kube-prometheus-stack
`grafana` values can seed datasources with `orgId`:

```yaml
# grafana values (sketch) — one datasource per team, pinned to that team's org
additionalDataSources:
  - name: AMP team-a
    type: prometheus
    orgId: 2                       # org for team-a (orgs pre-created via Grafana API/provisioning)
    url: <team_amp_endpoints["team-a"]>
    jsonData: { httpMethod: POST, sigV4Auth: true, sigV4AuthType: default, sigV4Region: ap-southeast-1 }
  - name: AMP team-b
    type: prometheus
    orgId: 3
    url: <team_amp_endpoints["team-b"]>
    jsonData: { httpMethod: POST, sigV4Auth: true, sigV4AuthType: default, sigV4Region: ap-southeast-1 }
```

## Isolation summary
| | Mechanism | Hard? |
|---|---|---|
| Write (team → its workspace) | per-team `amp-write` IAM role (Pod Identity) | ✅ hard |
| Read (team sees only its metrics) | Grafana **org** + per-org datasource | ⚠️ soft (org-level) |

For hard read isolation too: one Grafana/AMG workspace per team, each with a role scoped to a
single AMP workspace (heavier — N Grafanas).
