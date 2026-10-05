# envs/ — per-environment systems

Each `envs/<env>/` is a **self-contained** system deployed by its own `deploy.sh`
(teardown by `teardown.sh`). Three layers, applied in order:

| Layer | Dir | Tool | Values |
|---|---|---|---|
| 0 · infra | `00-infra/00-network … 07-waf` | OpenTofu (`../../../../modules/*`) | per-root `main.tf` |
| 1 · add-ons | `01-addons/*` | helmfile | hardcoded plain `values.yaml` |
| 2 · platform | `02-platform/*` | helmfile | hardcoded plain `values.yaml` |

Helm values are **hardcoded plain YAML** — no `.gotmpl`, no `tofu output` wiring
(every value is deterministic per env). Raw K8s manifests (NodePool, ClusterIssuer,
ClusterSecretStore, NetworkPolicies) ship as helm releases via the shared
`../charts/app` raw-manifest chart. See `../docs/DEPLOY.md` for the full run guide and
`../docs/VERSION-COMPATIBILITY.md` for chart↔K8s support.

**Which add-ons an env runs is expressed by which folders exist in it** — there is no
enable flag. `dev` ships the small set; `prod` ships everything.

## Layer 1 · add-ons catalog

| # | Folder | What | AWS IAM (00-infra/03-addon-iam) | dev | prod |
|---|---|---|---|:--:|:--:|
| 00 | karpenter | node autoscaler + NodePool/EC2NodeClass | Karpenter (02-karpenter-infra) | ✅ | ✅ |
| 01 | metrics-server | HPA / `kubectl top` | — | ✅ | ✅ |
| 02 | aws-load-balancer-controller | ALB/NLB from Ingress/Service | LBC | ✅ | ✅ |
| 03 | external-dns | Ingress hosts → Route 53 | external-dns | — | ✅ |
| 04 | cert-manager | TLS certs (HTTP-01 by default) | cert-manager (DNS-01 only) | ✅ | ✅ |
| 05 | external-secrets | pull from Secrets Manager | ESO | ✅ | ✅ |
| 06 | kyverno | policy engine | — | — | ✅ |
| 07 | network-policy | baseline NetworkPolicies (needs `enable_network_policy` in 01-eks) | — | — | ✅ |
| 08 | keda | event-driven autoscale | KEDA | — | ✅ |
| 09 | dns-scale | CoreDNS autoscaler + NodeLocal DNSCache | — | — | ✅ |

## Layer 2 · platform catalog

| # | Folder | What | Depends | dev | prod |
|---|---|---|---|:--:|:--:|
| 00 | argocd | GitOps (app-of-apps, ApplicationSets) | — | ✅ | ✅ |
| 01 | observability | kube-prometheus-stack (Grafana/Prometheus/Alertmanager) | AMP (05-observability-aws) optional | ✅ | ✅ |
| 02 | velero | cluster + volume backup to S3 | 06-backup-aws | — | ✅ |
| 03 | argo-rollouts | progressive delivery (canary/blue-green) | — | — | ✅ |
| 04 | kubecost | cost visibility per namespace/workload | kubecost IAM | — | ✅ |
| 05 | service-mesh | Kuma — mTLS, traffic management (east-west) | — | — | ✅ |
| 06 | falco | runtime security (syscall detection) | — | — | ✅ |
| 07 | observability-aws | ADOT (OTLP → AMP + X-Ray) · Fluent Bit (→ CloudWatch Logs) | 05-observability-aws (`enable_amp`) | ✅ | — |

## Add a new system
`cp -r envs/dev envs/staging`, edit each `00-infra/*/main.tf` (env, cluster_name, CIDR,
toggles), search-replace `eks-dev` → `eks-staging` in the `01-addons/`/`02-platform/`
values, then `cd envs/staging && ./deploy.sh`. State is isolated (S3 key is
`<env>`-prefixed) and global names are `<env>`-prefixed, so systems never collide.
