# Deploy

**Multi-env — one codebase, many systems.** Each environment lives under
`envs/<env>/` and is **fully self-contained**: its own Terraform state (S3 key
prefixed by `<env>`), its own add-on set, and its own deploy/teardown scripts. A
second system never collides with the first.

Each env is organised as **three layers**:

| Layer | Path | Tool | Contents |
|---|---|---|---|
| 0 · infra | `envs/<env>/00-infra/00-network … 07-waf` | OpenTofu | VPC, EKS, Karpenter infra, add-on IAM, security, observability, backup, WAF |
| 1 · add-ons | `envs/<env>/01-addons/*` | helmfile | Karpenter, metrics-server, LBC, ExternalDNS, cert-manager, external-secrets, Kyverno, KEDA, NodeLocal DNS |
| 2 · platform | `envs/<env>/02-platform/*` | helmfile | Argo CD, kube-prometheus-stack, Velero, Argo Rollouts, Kubecost, Kuma, Falco |

**Helm values are hardcoded plain YAML** (`values.yaml` per release) — no `.gotmpl`
templating and no `tofu output` wiring. This works because every value the add-ons
need is deterministic per env (cluster name `eks-<env>`, region, the module's stable
`Karpenter-<cluster>` node-role, `<env>-<bucket>` for Velero, `10.100.0.10` for the
default service CIDR). VPC id is omitted — the LB controller auto-discovers it.
Raw K8s manifests (NodePool, ClusterIssuer, ClusterSecretStore, NetworkPolicies) are
delivered as helm releases via the shared `charts/app` raw-manifest chart.

## Prerequisites
- `tofu`, `helmfile`, `helm`, `aws`, `kubectl` installed.
- **AWS credentials** for the `default` profile — see `hands-on/AWS-CREDENTIALS.md`; verify with
  `aws sts get-caller-identity`.
- Foundation set up **once** (S3 state backend + shared ECR + Route 53 zone): `(cd ../foundation && ./apply.sh)`.

## Run
```bash
cd envs/dev  && ./deploy.sh     # dev  = small preset (5 add-ons, 2 platform services)
cd envs/prod && ./deploy.sh     # prod = large preset (full security, private API, egress firewall)
```
Each run applies `00-infra/*` (in `00→07` order) into `<env>`-prefixed state, wires the
kubeconfig, applies the default StorageClass, then applies `01-addons/*` and
`02-platform/*` in order.

## envs/&lt;env&gt;/
| Path | What |
|---|---|
| `00-infra/<NN-layer>/main.tf` | one Terraform root: concrete S3 backend (key `<env>/layer0/<layer>`), provider, `terraform_remote_state` for deps, one `module` call (from `../../../../modules/*`) with this env's values, and outputs |
| `01-addons/<NN-addon>/helmfile.yaml` + `values.yaml` | one core add-on, values hardcoded for this env |
| `02-platform/<NN-service>/helmfile.yaml` + `values.yaml` | one platform service |
| `deploy.sh` / `teardown.sh` | this env's orchestrators |

Modules are shared in `modules/`; only the roots + helm values differ per env. State
bucket is shared (`eks-iac-tfstate`); the **key** is `<env>`-prefixed and independent
of the directory path, so the `00-infra/` grouping did not move any state. Global names
(buckets, WAF) are `<env>`-prefixed inside the modules; cluster name is per env.

**Add a new system:** `cp -r envs/dev envs/staging`, edit each `00-infra/*/main.tf`
(env, cluster_name, CIDR, toggles) and search-replace `eks-dev` → `eks-staging` in the
`01-addons/`/`02-platform/` values, then `cd envs/staging && ./deploy.sh`. Isolated
state + `<env>`-prefixed names automatically.

## Cost per preset
`ap-southeast-1`, 24/7 monthly. Billing is hourly — a short run + `teardown.sh` costs a few dollars.

| Preset (env) | ~Monthly | Main drivers |
|---|---|---|
| dev (small) | **~$180** | control plane $73 · 1 NAT · 2× t4g.medium · endpoints |
| medium* | **~$250–320** | + GuardDuty · WAF · CloudWatch logs · backup |
| prod (large) | **~$1,200–1,600** | + 3× NAT · full CloudTrail/Config/Security Hub · AMP · **Network Firewall ~$865** |

\*medium = a preset you can add (`cp -r envs/dev envs/staging`, then turn on
logging/encryption/backup/GuardDuty/WAF). Biggest levers:
`enable_network_firewall=false` (−~$865/mo), `nat_per_az=false` (−~$66/mo).

## Notes
- **prod sets a private API endpoint** — run `envs/prod/deploy.sh` from inside the VPC
  (bastion/VPN/SSM), else the post-cluster kubectl/helmfile steps can't reach the API.
- Global-unique names (state keys, S3 buckets, WAF, ECR repos) are prefixed with
  `<env>` and the cluster name is per env — two systems in one account don't collide.
- The state **bucket** is shared across envs (`eks-iac-tfstate`); only the **key** is
  per-env. For separate AWS accounts, point each env's backend at that account's bucket.

## Teardown
```bash
cd envs/<env> && ./teardown.sh
```
