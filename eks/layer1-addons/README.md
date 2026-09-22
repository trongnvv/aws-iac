# layer1-addons (Helmfile — core cluster add-ons)

The controllers that make the cluster usable — none of these are EKS managed
add-ons. Run after layer0 + `aws eks update-kubeconfig` + `source env.sh`.

| # | Folder | What | AWS IAM (layer0/04) |
|---|---|---|---|
| 00 | karpenter | node autoscaler + NodePool/EC2NodeClass | Karpenter (03) |
| 01 | metrics-server | HPA / `kubectl top` | — |
| 02 | aws-load-balancer-controller | ALB/NLB from Ingress/Service | LBC |
| 03 | external-dns | Ingress hosts → Route 53 | external-dns |
| 04 | cert-manager | TLS certs (HTTP-01 by default) | cert-manager (DNS-01 only) |
| 05 | external-secrets | pull from Secrets Manager | ESO |
| 06 | kyverno | policy engine | — |
| 07 | network-policy | baseline NetworkPolicies (needs `enable_network_policy` in 01) | — |
| 08 | keda | event-driven autoscale | KEDA |
| 09 | dns-scale | CoreDNS autoscaler + NodeLocal DNSCache | — |

Each folder: `helmfile apply`. Env-driven values live in `values/*.yaml.gotmpl`.

## Which to apply by system size

Helmfile folders have no enable flag — you apply or skip them per env.

| Size | Apply |
|---|---|
| Small (dev/lab) | 00 karpenter · 01 metrics-server · 02 LBC · 04 cert-manager · 05 external-secrets |
| Medium (staging) | + 03 external-dns · 06 kyverno · 08 keda |
| Large (prod/regulated) | + 07 network-policy · 09 dns-scale (everything) |

Guidance: small needs autoscaling, ingress, certs, secrets — the minimum to ship
an app. Medium adds DNS automation, policy, and event scaling. Large adds
pod-to-pod segmentation and DNS-at-scale. EFS CSI is a *managed add-on* — enable
it in layer0/01 (`enable_efs_csi`), not here.
