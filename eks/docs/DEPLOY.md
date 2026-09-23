# Deploy

**Multi-env — one codebase, many systems.** Each environment lives under
`envs/<env>/` with its own state (S3 key prefixed by `<env>`), toggles, and add-on
lists, so a second system never collides with the first.

## Prerequisites
- `tofu`, `helmfile`, `aws`, `kubectl` installed.
- **AWS credentials** for the `default` profile — see `AWS-CREDENTIALS.md`; verify with
  `aws sts get-caller-identity`.
- Foundation set up **once** (S3 state backend + Route 53 zone): `(cd ../foundation && ./apply.sh)`.

## Run
```bash
./scripts/deploy.sh dev     # dev  = small preset (nothing paid)
./scripts/deploy.sh prod    # prod = large preset (full security, private API, egress firewall)
```
Each run applies layer0 (`00→08`) into `<env>`-prefixed state, wires the kubeconfig,
then applies the env's layer1/layer2 add-on lists. Infra vars come from `tofu output`.

## envs/&lt;env&gt;/
| File | What |
|---|---|
| `backend.hcl` | S3 bucket + lock table + region. State bucket is shared; the **key** is `<env>/layer0/<folder>/...` |
| `config.env` | `TF_VAR_env`, `TF_VAR_cluster_name`, the `enable_*` toggles, `ACME_EMAIL`/`DOMAIN_FILTER`, and the `L1`/`L2` add-on lists + `NETPOL` |

**Add a new system:** `cp -r envs/dev envs/staging`, edit `envs/staging/config.env`
(env name, cluster_name, toggles, add-on lists), then `./scripts/deploy.sh staging`.
It gets isolated state and `<env>`-prefixed resource names automatically.

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
- **prod sets a private API endpoint** — run `deploy.sh prod` from inside the VPC
  (bastion/VPN/SSM), else the post-cluster kubectl/helmfile steps can't reach the API.
- Global-unique names (state keys, S3 buckets, WAF, ECR repos) are prefixed with
  `<env>` and the cluster name is per env — two systems in one account don't collide.
- The state **bucket** is shared across envs (`eks-iac-tfstate`); only the **key** is
  per-env. For separate AWS accounts, point each env's `backend.hcl` at that account's bucket.

## Teardown
```bash
./scripts/teardown.sh <env>
```
