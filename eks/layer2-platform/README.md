# layer2-platform (Helmfile — platform & apps)

Higher-level platform services on top of the core add-ons. Run after layer1.

| # | Folder | What | Depends |
|---|---|---|---|
| 00 | argocd | GitOps (app-of-apps, ApplicationSets) | — |
| 01 | observability | kube-prometheus-stack (Grafana/Prometheus/Alertmanager) | AMP (07) optional |
| 02 | velero | cluster + volume backup to S3 | backup-aws (08) |
| 03 | argo-rollouts | progressive delivery (canary/blue-green) | — |
| 04 | kubecost | cost visibility per namespace/workload | kubecost IAM (04) |
| 05 | api-gateway | Kong — API auth / rate-limit / quota | — |
| 06 | service-mesh | Kuma (Kong's OSS mesh) — mTLS, traffic management | — |
| 07 | falco | runtime security (syscall detection) | — |

Each folder: `helmfile apply`.

## Which to apply by system size

| Size | Apply |
|---|---|
| Small (dev/lab) | (optional) 00 argocd · 01 observability (light) |
| Medium (staging) | 00 argocd · 01 observability · 02 velero |
| Large (prod/regulated) | + 03 argo-rollouts · 04 kubecost · 05 api-gateway · 06 service-mesh · 07 falco |

Guidance: small can skip this layer entirely (or just Grafana for a dashboard).
Medium runs GitOps + observability + backup — the operational core. Large adds
progressive delivery, cost governance, API management, mesh mTLS, and runtime
security — the things a big, regulated system is audited on.
