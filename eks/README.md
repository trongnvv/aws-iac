# EKS on AWS — layered IaC

A hands-on, production-shaped EKS build split into layers. `ap-southeast-1`,
OpenTofu for AWS resources, Helmfile for Kubernetes add-ons.

## Start here

| I want to… | Read |
|---|---|
| **No AWS credentials yet** | `docs/hands-on/AWS-CREDENTIALS.md` — get keys / SSO for the `default` profile |
| Push a local image to ECR | `docs/hands-on/PUSH-IMAGE-TO-ECR.md` |
| **First time — set up shared prereqs** | `../foundation/README.md` — S3 state backend + Route 53 zone (run once) |
| **Deploy it** | **`docs/DEPLOY.md`** → `cd envs/<env> && ./deploy.sh` (dev/prod) |
| Do it by hand, small steps (learn/debug) | `docs/hands-on/WALKTHROUGH-dev.md` |
| See the architecture per size | `docs/ARCHITECTURE.md` (Mermaid diagrams: small / medium / large) |
| **Understand EKS deeply** (create mechanics, AWS ecosystem, runtime) | `docs/MODULES.md` |
| **Networking** (north-south, ALB vs NLB, egress, endpoints) | `docs/NETWORKING.md` |
| **Something's broken** (symptom → fix) | `docs/TROUBLESHOOTING.md` |
| Post-cluster test ideas (ingress/gRPC, observability, CI/CD) | `docs/TEST-PLAN.md` |
| How images reach dev→stg→prod (pull vs push vs Kargo, open decision) | `docs/IMAGE-PROMOTION.md` |
| Understand the structure | Structure section below · `modules/README.md` · `envs/README.md` (per-env layer catalog) |
| Chart ↔ K8s version support | `docs/VERSION-COMPATIBILITY.md` |
| Set env vars for a manual run | `env.sh.example` |
| Compare observability options | `docs/OBSERVABILITY.md` (Datadog / Grafana LGTM / Elastic / AWS native + the platform's approach) |
| See known gaps / hardening backlog | `docs/REVIEW.md` *(not needed to deploy)* |
| Get the big picture | keep reading this file |

New here? Read this file top-to-bottom once, then follow `docs/DEPLOY.md`.

## Structure (modules + self-contained per-env stacks)

| Part | Tool | What |
|---|---|---|
| `../foundation/` | OpenTofu | shared prereqs (run once): S3 state backend + Route 53 zone + ACM cert + **shared ECR** |
| `modules/` | OpenTofu | **reusable building blocks**: network · eks · karpenter-infra · addon-iam · security-baseline · observability-aws · backup-aws · waf |
| `charts/app/` | Helm | raw-manifest renderer — ships arbitrary K8s manifests (NodePool, ClusterIssuer, …) as helm releases |
| `envs/<env>/00-infra/<NN>-*/` | OpenTofu | **thin per-env roots** that call the modules; own S3 state (key `<env>/layer0/<layer>`), env-specific values inline |
| `envs/<env>/01-addons/<NN>-*/` | Helmfile | core cluster add-ons (autoscaling, ingress, DNS, certs, secrets, policy) — hardcoded plain `values.yaml` |
| `envs/<env>/02-platform/<NN>-*/` | Helmfile | platform & apps (GitOps, observability, backup, delivery, mesh, security) — hardcoded plain `values.yaml` |
| `envs/<env>/deploy.sh` · `teardown.sh` | bash | this env's orchestrators |

Each env is a **self-contained three-layer stack**: `00-infra` (Terraform roots
`00-network` … `07-waf`, each wiring one module + its S3 backend + upstream
`terraform_remote_state`), then `01-addons` and `02-platform` (helmfile). Layer0 =
dependency order; layer1/2 = priority. Helm values are **hardcoded plain YAML** — no
`.gotmpl`, no `tofu output` wiring (every value is deterministic per env). **Sizing is
per env**: `dev` ships the small set (fewer folders), `prod` ships everything; the
knobs are the module inputs in each root's `main.tf`. Catalog: `envs/README.md`.

## Deploy

**Multi-env — one codebase, many systems.** Each env under `envs/<env>/` has its own
state (S3 key prefix), toggles, and add-on set, so a second system never collides.
Prereq once: `(cd ../foundation && ./apply.sh)` — S3 state backend + DNS zone.

```bash
cd envs/dev  && ./deploy.sh   # small preset (nothing paid)
cd envs/prod && ./deploy.sh   # large preset (full security, private API, egress firewall)
```

Add a new system: `cp -r envs/dev envs/<name>`, edit each `00-infra/*/main.tf` (env
name, `cluster_name`, CIDR, `enable_*` toggles), search-replace `eks-dev` → `eks-<name>`
in the `01-addons`/`02-platform` values (add/remove folders to change the add-on set),
then `cd envs/<name> && ./deploy.sh`. Details + cost per preset: `docs/DEPLOY.md`.

## Networking (north-south, egress, intra-VPC)

```
Inbound:  Internet → [CloudFront → WAF] → [ALB (L7) / NLB (L4), LBC] → Service
Outbound: Service → [NetworkPolicy] → [Network Firewall / Kuma egress] → [NAT (static EIP)] → partner
```
- Inbound: `01-addons/02-aws-load-balancer-controller` (ALB *and* NLB; also serves Gateway API via GatewayClass `alb`) · `01-addons/03-external-dns` · `01-addons/04-cert-manager` · WAF `00-infra/07-waf`.
- Outbound: static egress IP = `00-infra/00-network` output `nat_public_ips` · filtering `01-addons/07-network-policy` · inspection `enable_network_firewall` / Kuma egress.

**ALB vs NLB, egress options, VPC endpoints, subnet tiers — full design guide:
[`docs/NETWORKING.md`](docs/NETWORKING.md).**

## Conventions

- IaC = OpenTofu (`tofu`, not `terraform`). AWS provider uses `profile = "default"`.
- Managed EKS add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI, Pod Identity) live in
  `00-infra/01-eks` (AWS lifecycle). Everything else is Helm in `01-addons`/`02-platform`.
  One owner per component.
- Cost discipline: this is a lab. `tofu destroy` in reverse order when done.

## Managed add-ons vs Helm (who installs what)

**EKS managed add-ons** — in `00-infra/01-eks`, AWS-managed lifecycle:
- vpc-cni
- coredns
- kube-proxy
- ebs-csi
- efs-csi
- pod-identity-agent
- adot
- cloudwatch-observability

**Installed via Helm** — `01-addons` / `02-platform`:
- Karpenter
- AWS Load Balancer Controller
- external-dns
- cert-manager
- external-secrets
- metrics-server
- Kyverno
- KEDA
- ArgoCD
- Kuma
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
- **Metrics backend:** self-host `kube-prometheus-stack` (`02-platform/01-observability`)
  **or** AMP+AMG (`00-infra/05-observability-aws`) — not both. If using AMP, point
  Prometheus `remoteWrite` at it.
- **North-south:** the ALB (LBC) is the single entry — from `Ingress` (class `alb`) **or**
  Gateway API (GatewayClass `alb`, feature gate `ALBGatewayAPI`); both provision an ALB, no
  in-cluster proxy. Kuma (`02-platform/05-service-mesh`) is east-west only (mesh mTLS) and
  never overlaps here.
- **Runtime security:** Falco (`02-platform/06-falco`) **or** GuardDuty runtime
  monitoring — not both.
- **Storage:** EBS CSI is a managed add-on (`enable_ebs_csi`, on by default) + a `gp3`
  default StorageClass (`01-addons/00-storageclass`, a helmfile release via charts/app).
  Don't also enable the standalone metrics-server managed add-on (installed via Helm).

## Teardown

`cd envs/<env> && ./teardown.sh` — reverse order, guards skip whatever wasn't applied.
It removes the Helm-managed LBs (ALBs/ENIs) before the VPC, else the destroy hangs on
orphaned network interfaces.
