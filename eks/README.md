# EKS on AWS — layered IaC

A hands-on, production-shaped EKS build split into layers. `ap-southeast-1`,
OpenTofu for AWS resources, Helmfile for Kubernetes add-ons.

## Layers

| Layer | Tool | What |
|---|---|---|
| `bootstrap/` | OpenTofu | remote-state backend (S3 + DynamoDB lock) |
| `layer0-provisioning/` | OpenTofu | AWS resources: network, EKS, node group, Karpenter infra, add-on IAM, ECR, security, observability, backup, WAF, network firewall |
| `layer1-addons/` | Helmfile | core cluster add-ons (autoscaling, ingress, DNS, certs, secrets, policy) |
| `layer2-platform/` | Helmfile | platform & apps (GitOps, observability, backup, delivery, mesh, security) |

Subfolders are numbered by apply order (layer0 = dependency order; layer1/2 = priority).
Each layer has its own `README.md` with the full folder list and **small/medium/large
sizing guidance**.

## Deploy

One self-contained script per size (state → tfvars → layer0 → kubeconfig/env →
layer1 → layer2); infra env vars are derived from `tofu output`.

```bash
export ACME_EMAIL=you@example.com   # all sizes  (cert-manager)
export DOMAIN_FILTER=example.com    # medium/large (external-dns)
./scripts/deploy-small.sh           # or deploy-medium.sh / deploy-large.sh
```

Per-size folder lists + toggles: `DEPLOY.md` and the `layer*/README.md` sizing tables.

## North-South networking

Traffic in and out of the cluster, split across layers.

**Inbound edge**
```
Internet → [CloudFront → WAF/Shield] → [ALB/NLB (LBC)] → [API GW (Kong)] → Service
```
- ALB/NLB + DNS + TLS: `layer1/02-lb-controller` · `03-external-dns` · `04-cert-manager`
- WAF: `layer0/09-waf` (attach via the Ingress annotation `alb.ingress.kubernetes.io/wafv2-acl-arn`)
- API management: `layer2/05-api-gateway` (Kong)

**Outbound egress**
```
Service → [NetworkPolicy] → [Network Firewall / Istio egress] → [NAT (static EIP)] → partner/exchange
```
- Static egress IP for partner/exchange source-IP allowlisting: `layer0/00-network` output `nat_public_ips`
- Egress filtering: `layer1/07-network-policy`
- Centralized inspection: `layer0/10-network-firewall` (or Istio egress in `layer2/06-service-mesh`)

## Conventions

- IaC = OpenTofu (`tofu`, not `terraform`). AWS provider uses `profile = "default"`.
- Managed EKS add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI, Pod Identity) live in
  `01-eks` (AWS lifecycle). Everything else is Helm in layer1. One owner per component.
- Cost discipline: this is a lab. `tofu destroy` in reverse order when done.

## Managed add-ons vs Helm (who installs what)

| EKS managed add-on (layer0/01-eks, AWS lifecycle) | Must install via Helm (layer1/2) |
|---|---|
| vpc-cni · coredns · kube-proxy · ebs-csi · efs-csi · pod-identity-agent · adot · cloudwatch-observability | Karpenter · AWS LB Controller · external-dns · cert-manager · external-secrets · metrics-server · Kyverno · KEDA · ArgoCD · Istio · Velero · Kubecost · Falco |

Managed add-ons are plumbing AWS lifecycle-manages; the controllers that make the
cluster actually usable (autoscaling, ingress, DNS, certs, secrets, policy, GitOps)
are Helm-only. They complement each other — neither replaces the other.

## Teardown

`./scripts/teardown.sh` — reverse order, guards skip whatever wasn't applied.
It destroys the LB Controller (removing ALBs/ENIs) before the VPC, else the
destroy hangs on orphaned network interfaces.
