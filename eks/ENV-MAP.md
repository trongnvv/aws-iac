# Env → enable map

Consolidated per-env toggle reference. Two mechanisms:

- **layer0 (tofu):** every paid/behavior-changing feature has an `enable_*` variable —
  set it per env in that folder's `terraform.tfvars`. Defaults are cost-minimal.
- **layer1 / layer2 (helmfile):** no enable var — apply or skip a folder per env
  (see each layer's `README.md` for the small/medium/large apply lists).

## layer0 tofu toggles

| Folder | Variable | Small | Medium | Large |
|---|---|---|---|---|
| 00-network | `nat_per_az` | false | false | true |
| 00-network | `enable_secondary_cidr` | false | false | true if IP-heavy |
| 01-eks | `enable_control_plane_logging` | false | true | true |
| 01-eks | `enable_secret_encryption` | false | true | true |
| 01-eks | `cluster_endpoint_public_access` | true | true (narrow CIDRs) | false |
| 01-eks | `cluster_endpoint_private_access` | true | true | true |
| 01-eks | `enable_prefix_delegation` | true | true | true |
| 01-eks | `enable_pod_eni` | false | false | true |
| 01-eks | `enable_network_policy` | false | true | true |
| 01-eks | `enable_efs_csi` | false | if RWX | true |
| 05-ecr | `enable_enhanced_scan` | false | false | true |
| 06-security-baseline | `enable_guardduty` | false | true | true |
| 06-security-baseline | `enable_cloudtrail` | false | false | true |
| 06-security-baseline | `enable_config` | false | false | true |
| 06-security-baseline | `enable_securityhub` | false | false | true |
| 07-observability-aws | `enable_amp` | false | optional | true |
| 08-backup-aws | `enable_backup` | false | true | true |
| 09-waf | `enable_waf` | false | true | true |
| 10-network-firewall | `enable_network_firewall` | false | false | true if required |

`02-node-group`, `03-karpenter-infra`, `04-addon-iam` have no paid toggle — always applied.

## layer1 helmfile — apply per size
- **Small:** 00-karpenter · 01-metrics-server · 02-aws-load-balancer-controller · 04-cert-manager · 05-external-secrets
- **Medium:** + 03-external-dns · 06-kyverno · 08-keda
- **Large:** + 07-network-policy · 09-dns-scale

## layer2 helmfile — apply per size
- **Small:** (optional) 00-argocd · 01-observability
- **Medium:** 00-argocd · 01-observability · 02-velero
- **Large:** + 03-argo-rollouts · 04-kubecost · 05-api-gateway · 06-service-mesh · 07-falco

## Example — large (prod/regulated) tfvars

```hcl
# 00-network/terraform.tfvars
nat_per_az            = true
enable_secondary_cidr = true

# 01-eks/terraform.tfvars
enable_control_plane_logging   = true
enable_secret_encryption       = true
cluster_endpoint_public_access = false
endpoint_public_access_cidrs   = ["<office-ip>/32"]
enable_pod_eni                 = true
enable_network_policy          = true

# 06-security-baseline/terraform.tfvars
enable_guardduty   = true
enable_cloudtrail  = true
enable_config      = true
enable_securityhub = true

# 07-observability-aws  → enable_amp = true
# 08-backup-aws         → enable_backup = true
# 09-waf                → enable_waf = true
# 10-network-firewall   → enable_network_firewall = true   # only if egress inspection is required
```
