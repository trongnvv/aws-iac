# EKS on AWS — layered IaC

A hands-on, production-shaped EKS build split into layers. `ap-southeast-1`,
OpenTofu for AWS resources, Helmfile for Kubernetes add-ons.

## Start here

| I want to… | Read |
|---|---|
| **No AWS credentials yet** | `docs/hands-on/AWS-CREDENTIALS.md` — get keys / SSO for the `default` profile |
| Push a local image to ECR | `docs/hands-on/PUSH-IMAGE-TO-ECR.md` |
| **First time — set up shared prereqs** | `../foundation/README.md` — S3 state backend + Route 53 zone (run once) |
| **Deploy it** | **`docs/DEPLOY.md`** → `scripts/deploy.sh <env>` (dev/prod) |
| Do it by hand, small steps (learn/debug) | `docs/hands-on/WALKTHROUGH-dev.md` |
| See the architecture per size | `docs/ARCHITECTURE.md` (Mermaid diagrams: small / medium / large) |
| **Understand EKS deeply** (create mechanics, AWS ecosystem, runtime) | `docs/MODULES.md` |
| **Networking** (north-south, ALB vs NLB, egress, endpoints) | `docs/NETWORKING.md` |
| **Something's broken** (symptom → fix) | `docs/TROUBLESHOOTING.md` |
| Understand the structure | Structure section below · `modules/README.md` · `layer1-addons/README.md` · `layer2-platform/README.md` |
| Set env vars for a manual run | `env.sh.example` |
| Compare observability options | `docs/OBSERVABILITY.md` (Datadog / Grafana LGTM / Elastic / AWS native + the platform's approach) |
| See known gaps / hardening backlog | `docs/REVIEW.md` *(not needed to deploy)* |
| Get the big picture | keep reading this file |

New here? Read this file top-to-bottom once, then follow `docs/DEPLOY.md`.

## Structure (modules + per-env roots)

| Part | Tool | What |
|---|---|---|
| `../foundation/` | OpenTofu | shared prereqs (run once): S3 state backend + Route 53 zone + ACM cert + **shared ECR** |
| `modules/` | OpenTofu | **reusable building blocks**: network · eks · karpenter-infra · addon-iam · security-baseline · observability-aws · backup-aws · waf |
| `envs/<env>/<NN-layer>/` | OpenTofu | **thin per-env roots** that call the modules; own S3 state (key `<env>/layer0/<layer>`), env-specific values inline |
| `layer1-addons/` | Helmfile | core cluster add-ons (autoscaling, ingress, DNS, certs, secrets, policy) |
| `layer2-platform/` | Helmfile | platform & apps (GitOps, observability, backup, delivery, mesh, security) |

Each env is a stack of per-layer roots — `envs/dev/00-network` … `08-waf` — each a
few lines wiring one module + its S3 backend + upstream `terraform_remote_state`.
Layer0 = dependency order; layer1/2 = priority. **Sizing is per env**: `dev` roots =
small preset, `prod` roots = large preset; the knobs are the module inputs set in
each root's `main.tf`.

## Deploy

**Multi-env — one codebase, many systems.** Each env under `envs/<env>/` has its own
state (S3 key prefix), toggles, and add-on lists, so a second system never collides.
Prereq once: `(cd ../foundation && ./apply.sh)` — S3 state backend + DNS zone.

```bash
./scripts/deploy.sh dev     # small preset (nothing paid)
./scripts/deploy.sh prod    # large preset (full security, private API, egress firewall)
```

Add a new system: `cp -r envs/dev envs/<name>`, edit the roots' `main.tf` (env name,
`cluster_name`, CIDR, `enable_*` toggles) + `config.env` (add-on lists), then
`./scripts/deploy.sh <name>`. Details + cost per preset: `docs/DEPLOY.md`.

## Networking (north-south, egress, intra-VPC)

```
Inbound:  Internet → [CloudFront → WAF] → [ALB (L7) / NLB (L4), LBC] → [API GW (Kong)] → Service
Outbound: Service → [NetworkPolicy] → [Network Firewall / Istio egress] → [NAT (static EIP)] → partner
```
- Inbound: `layer1/02-lb-controller` (ALB *and* NLB) · `03-external-dns` · `04-cert-manager` · WAF `layer0/08` · Kong `layer2/05`.
- Outbound: static egress IP = `00-network` output `nat_public_ips` · filtering `layer1/07` · inspection `enable_network_firewall` / Istio egress.

**ALB vs NLB, egress options, VPC endpoints, subnet tiers — full design guide:
[`docs/NETWORKING.md`](docs/NETWORKING.md).**

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

## Single-cluster notes (avoid overlaps)

Some add-ons overlap — pick one per cluster:
- **CoreDNS autoscaling** is native in the managed `coredns` add-on — do **not** also
  run `cluster-proportional-autoscaler` (they fight over replicas). `09-dns-scale` now
  ships only NodeLocal DNSCache.
- **Metrics backend:** self-host `kube-prometheus-stack` (layer2/01) **or** AMP+AMG
  (`06-observability-aws`) — not both. If using AMP, point Prometheus `remoteWrite` at it.
- **North-south API:** Kong (layer2/05) **or** Istio ingress (layer2/06) — Istio's
  value here is east-west mTLS; don't run both as the API gateway.
- **Runtime security:** Falco (layer2/07) **or** GuardDuty runtime monitoring — not both.
- **Storage:** EBS CSI is a managed add-on (`enable_ebs_csi`, on by default) + a `gp3`
  default StorageClass (`manifests/gp3-default-storageclass.yaml`, applied by deploy.sh).
  Don't also enable the standalone metrics-server managed add-on (installed via Helm).

## Teardown

`./scripts/teardown.sh` — reverse order, guards skip whatever wasn't applied.
It destroys the LB Controller (removing ALBs/ENIs) before the VPC, else the
destroy hangs on orphaned network interfaces.
