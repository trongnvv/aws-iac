# Deploy

One self-contained script per size in `scripts/`. Each runs the full pipeline —
per-size `terraform.tfvars` → layer0 → kubeconfig/env → layer1 → layer2. Infra env
vars (cluster name, VPC id, Karpenter queue/role, backup bucket, DNS IP) are derived
from `tofu output`; you only export the app-specific ones.

## Prerequisites
- `tofu`, `helmfile`, `aws`, `kubectl` installed and `aws sts get-caller-identity` works.
- **Foundation set up once** (S3 state backend + Route 53 zone): `(cd ../foundation && ./apply.sh)`.

## Run
```bash
export ACME_EMAIL=you@example.com    # all sizes  (cert-manager)
export DOMAIN_FILTER=example.com     # medium/large (external-dns)

./scripts/deploy-small.sh     # dev/lab      — cluster + core add-ons, nothing paid
./scripts/deploy-medium.sh    # staging      — + logging, encryption, backup, GuardDuty, WAF
./scripts/deploy-large.sh     # prod/regulated — full security, private endpoint, mesh, edge/egress
```

What each size builds (folders + toggles) is in the `layer*/README.md` sizing tables.

## Notes
- **`deploy-large.sh` sets a private API endpoint** — run it from inside the VPC
  (bastion/VPN/SSM), otherwise the post-cluster `kubectl`/`helmfile` steps can't
  reach the API server.
- Egress network firewall (large) lives in `00-network` (`enable_network_firewall`):
  dedicated firewall subnets + app-egress redirect are wired automatically.
- Generated `terraform.tfvars` are local and gitignored.

## Cost per size

Rough `ap-southeast-1` estimates, **24/7 monthly**. Billing is hourly — a few-hours
lab run then `teardown.sh` costs only a few dollars, not these figures.

| Size | ~Monthly (24/7) | Main drivers |
|---|---|---|
| Small | **~$180** | EKS control plane $73 · 1 NAT ~$33 · 2× t4g.medium ~$49 · interface endpoints ~$22 |
| Medium | **~$250–320** | Small + GuardDuty + WAF + CloudWatch log ingest + backup S3 |
| Large | **~$1,200–1,600** | Medium + 3× NAT (per-AZ) + full CloudTrail/Config/Security Hub + AMP + **Network Firewall ~$865 (3 endpoints)** |

Biggest levers: **Network Firewall** (`enable_network_firewall=false` drops Large by
~$865/mo) and **per-AZ NAT** (`nat_per_az=false` saves ~$66/mo). Control plane ($73)
is fixed while the cluster exists.

## Teardown
```bash
./scripts/teardown.sh
```
