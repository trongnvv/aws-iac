# Deploy

One self-contained script per size in `scripts/`. Each runs the full pipeline —
remote state → per-size `terraform.tfvars` → layer0 → kubeconfig/env → layer1 →
layer2. Infra env vars (cluster name, VPC id, Karpenter queue/role, backup bucket,
DNS IP) are derived from `tofu output`; you only export the app-specific ones.

## Prerequisites
`tofu`, `helmfile`, `aws`, `kubectl` installed and `aws sts get-caller-identity` works.

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

## Teardown
```bash
./scripts/teardown.sh
```
