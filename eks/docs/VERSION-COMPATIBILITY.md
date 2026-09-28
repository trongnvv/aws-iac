# Chart ↔ Kubernetes version compatibility

Target: **EKS 1.36** (`modules/eks` default `cluster_version = "1.36"`).

Verdict from each chart's declared `kubeVersion` in `Chart.yaml`
(`helm show chart <repo/chart> --version <pinned>`). A chart with no `kubeVersion`
declares no gate; one with a `>=` minimum is satisfied by 1.36. **No chart pins an
upper bound**, so all pinned versions install on 1.36.

## Layer 1 · add-ons (`envs/<env>/01-addons`)

| Add-on | Chart version | Declared `kubeVersion` | 1.36 |
|---|---|---|---|
| Karpenter | `1.14.0` | none | ✅ |
| metrics-server | `3.14.0` | none | ✅ |
| aws-load-balancer-controller | `3.5.0` | none | ✅ |
| ExternalDNS | `1.22.0` | none | ✅ |
| cert-manager | `v1.21.1` | `>= 1.22.0-0` | ✅ |
| external-secrets | `2.11.0` | `>= 1.19.0-0` | ✅ |
| Kyverno | `3.9.1` | `>= 1.25.0-0` | ✅ |
| KEDA | `2.21.0` | `>= 1.23.0-0` | ✅ |
| node-local-dns | `2.9.2` | none | ✅ |

## Layer 2 · platform (`envs/<env>/02-platform`)

| Service | Chart version | Declared `kubeVersion` | 1.36 |
|---|---|---|---|
| Argo CD | `10.9.2` | `>= 1.25.0-0` | ✅ |
| kube-prometheus-stack | `91.7.0` | `>= 1.25.0-0` | ✅ |
| Velero | `12.2.0` | `>= 1.16.0-0` | ✅ |
| Argo Rollouts | `2.43.2` | none | ✅ |
| Kubecost | `2.9.7` | none | ✅ |
| Kong | `3.4.1` | none | ✅ |
| Kuma | `2.14.5` | none | ✅ |
| Falco | `9.2.0` | none | ✅ |

## Caveat — `kubeVersion` is a coarse gate

`kubeVersion` only blocks obviously-too-old clusters; it does **not** catch a chart
rendering a Kubernetes API that a newer minor has *removed*. For a minor bump the real
risk is removed/graduated APIs, and the tightest-coupled components are:

- **Karpenter** — depends on EKS AMIs + the EC2NodeClass/NodePool CRDs. `1.14.0` uses
  the stable `karpenter.sh/v1` + `karpenter.k8s.aws/v1` APIs (see `01-addons/00-karpenter/nodepool.yaml`); confirm the release notes list 1.36 as supported before a prod cut-over.
- **aws-load-balancer-controller** — coupled to EKS networking; no removed APIs expected at 1.36.

Before cutting a cluster to a new minor, check the **EKS release notes** for that
version's removed APIs, then re-run the `helm show chart ... | grep kubeVersion` sweep
after any chart bump.
