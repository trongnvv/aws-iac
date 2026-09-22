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
sizing guidance**. `ENV-MAP.md` is the consolidated per-env toggle reference.

## Apply order

```
# 1. Remote state (once)
cd bootstrap/00-tf-backend && tofu init && tofu apply

# 2. Layer 0 — tofu, folders 00 → 10 in order (each has its own state;
#    later folders read earlier ones via remote_state). Skip/enable paid
#    folders per env — see layer0-provisioning/README.md + ENV-MAP.md.
cd layer0-provisioning/00-network && tofu init && tofu apply    # ... through 10

# 3. Wire kubeconfig + export layer0 outputs for Helmfile
aws eks update-kubeconfig --name <cluster> --region ap-southeast-1
cp env.sh.example env.sh && $EDITOR env.sh && source env.sh

# 4. Layer 1 then Layer 2 — helmfile per folder, in number order.
#    Which folders to apply per size: see each layer's README.md.
cd layer1-addons/00-karpenter && helmfile apply                 # ... through 09
cd layer2-platform/00-argocd  && helmfile apply                 # ... through 07
```

Per-layer folder lists, dependencies and **small/medium/large** guidance live in
each layer's `README.md`; per-env `enable_*` toggles in `ENV-MAP.md`. Copy-paste
deploy/teardown scripts (per size) in `DEPLOY.md`.

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

Reverse order: `layer1` (helmfile destroy) → `layer0` `04 → 00`.
Watch for orphaned ALBs/ENIs from the LB Controller — delete Kubernetes
Ingress/Service before destroying the VPC or it will block deletion.
