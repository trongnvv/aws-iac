# EKS on AWS — layered IaC

A hands-on, production-shaped EKS build split into layers. `ap-southeast-1`,
OpenTofu for AWS resources, Helmfile for Kubernetes add-ons.

## Start here

| I want to… | Read |
|---|---|
| **First time — set up shared prereqs** | `../foundation/README.md` — S3 state backend + Route 53 zone (run once) |
| **Deploy it, step by step** | **`docs/DEPLOY.md`** → runs `scripts/deploy-{small,medium,large}.sh` |
| See the architecture per size | `docs/ARCHITECTURE.md` (Mermaid diagrams: small / medium / large) |
| Understand a layer / pick a size | `layer0-provisioning/README.md` · `layer1-addons/README.md` · `layer2-platform/README.md` |
| Set env vars for a manual run | `env.sh.example` |
| Compare observability options | `docs/OBSERVABILITY.md` (Datadog / Grafana LGTM / Elastic / AWS native + the platform's approach) |
| See known gaps / hardening backlog | `docs/REVIEW.md` *(not needed to deploy)* |
| Get the big picture | keep reading this file |

New here? Read this file top-to-bottom once, then follow `docs/DEPLOY.md`.

## Layers

| Layer | Tool | What |
|---|---|---|
| `../foundation/` | OpenTofu | shared prerequisites (run once): S3 state backend + Route 53 zone + ACM cert |
| `layer0-provisioning/` | OpenTofu | AWS resources: network (+egress firewall), EKS, Karpenter infra, add-on IAM, ECR, security, observability, backup, WAF |
| `layer1-addons/` | Helmfile | core cluster add-ons (autoscaling, ingress, DNS, certs, secrets, policy) |
| `layer2-platform/` | Helmfile | platform & apps (GitOps, observability, backup, delivery, mesh, security) |

Subfolders are numbered by apply order (layer0 = dependency order; layer1/2 = priority).
Each layer has its own `README.md` with the full folder list and **small/medium/large
sizing guidance**.

## Deploy

One self-contained script per size (tfvars → layer0 → kubeconfig/env → layer1 →
layer2); infra env vars are derived from `tofu output`.

Prereq (once): `(cd ../foundation && ./apply.sh)` — S3 state backend + DNS zone.

```bash
export ACME_EMAIL=you@example.com   # all sizes  (cert-manager)
export DOMAIN_FILTER=example.com    # medium/large (external-dns)
./scripts/deploy-small.sh           # or deploy-medium.sh / deploy-large.sh
```

Per-size folder lists + toggles: `docs/DEPLOY.md` and the `layer*/README.md` sizing tables.

## North-South networking

Traffic in and out of the cluster, split across layers.

**Inbound edge**
```
Internet → [CloudFront → WAF/Shield] → [ALB/NLB (LBC)] → [API GW (Kong)] → Service
```
- ALB/NLB + DNS + TLS: `layer1/02-lb-controller` · `03-external-dns` · `04-cert-manager`
- WAF: `layer0/08-waf` (attach via the Ingress annotation `alb.ingress.kubernetes.io/wafv2-acl-arn`)
- API management: `layer2/05-api-gateway` (Kong)

**Outbound egress**
```
Service → [NetworkPolicy] → [Network Firewall / Istio egress] → [NAT (static EIP)] → partner/exchange
```
- Static egress IP for partner/exchange source-IP allowlisting: `layer0/00-network` output `nat_public_ips`
- Egress filtering: `layer1/07-network-policy`
- Centralized inspection: `layer0/00-network` (`enable_network_firewall` — dedicated firewall subnets + app-egress redirect) or Istio egress in `layer2/06-service-mesh`

## Conventions

- IaC = OpenTofu (`tofu`, not `terraform`). AWS provider uses `profile = "default"`.
- Managed EKS add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI, Pod Identity) live in
  `01-eks` (AWS lifecycle). Everything else is Helm in layer1. One owner per component.
- Cost discipline: this is a lab. `tofu destroy` in reverse order when done.

## Managed add-ons vs Helm (who installs what)

**EKS managed add-ons** — in `layer0/01-eks`, AWS-managed lifecycle:
- vpc-cni
- coredns
- kube-proxy
- ebs-csi
- efs-csi
- pod-identity-agent
- adot
- cloudwatch-observability

**Installed via Helm** — layer1 / layer2:
- Karpenter
- AWS Load Balancer Controller
- external-dns
- cert-manager
- external-secrets
- metrics-server
- Kyverno
- KEDA
- ArgoCD
- Istio
- Velero
- Kubecost
- Falco

Managed add-ons are plumbing AWS lifecycle-manages; the controllers that make the
cluster actually usable (autoscaling, ingress, DNS, certs, secrets, policy, GitOps)
are Helm-only. They complement each other — neither replaces the other.

## Teardown

`./scripts/teardown.sh` — reverse order, guards skip whatever wasn't applied.
It destroys the LB Controller (removing ALBs/ENIs) before the VPC, else the
destroy hangs on orphaned network interfaces.
