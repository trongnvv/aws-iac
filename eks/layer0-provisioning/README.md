# layer0-provisioning (OpenTofu — AWS resources)

AWS-side of the platform. Dependency-ordered; each folder has its own remote state
(S3 + DynamoDB lock from `bootstrap`) and reads earlier folders via `terraform_remote_state`.

| # | Folder | What |
|---|---|---|
| 00 | network | VPC, 3-AZ subnets, NAT, endpoints, discovery tags, static egress IP, secondary CIDR, **egress network firewall** |
| 01 | eks | cluster, managed add-ons, Access Entries, logging, KMS, prefix delegation, pod-ENI, netpol, EFS CSI |
| 02 | karpenter-infra | Karpenter node IAM role, instance profile, SQS interruption queue |
| 03 | addon-iam | Pod Identity roles: LBC, ESO, external-dns, KEDA, cert-manager, kubecost |
| 04 | ecr | private registry + image scanning |
| 05 | security-baseline | GuardDuty, CloudTrail, Config, Security Hub |
| 06 | observability-aws | Amazon Managed Prometheus workspace + IAM |
| 07 | backup-aws | Velero S3 bucket + IAM |
| 08 | waf | regional web ACL for the ALB |

Apply `00 → 08` in order. Paid folders left off create nothing until enabled.
Extra node pools (beyond the bootstrap pool in `01-eks`) are added ad-hoc when needed.

## Using variables by system size

Everything paid is behind an `enable_*` variable defaulting to `false`. Drive them
per env from a `terraform.tfvars` in each folder — **don't edit defaults**. `off` =
not used at that size.

**Networking — `00-network`**

| Variable | Small | Medium | Large |
|---|---|---|---|
| `nat_per_az` | off (single NAT) | off | true (per-AZ HA) |
| `enable_secondary_cidr` | off | off | true if IP-heavy |
| `enable_network_firewall` | off | off | true if egress inspection required |

**Cluster & identity — `01-eks`**

| Variable | Small | Medium | Large |
|---|---|---|---|
| `enable_control_plane_logging` | off | true | true |
| `enable_secret_encryption` | off | true | true |
| `cluster_endpoint_public_access` | true | true + narrow CIDRs | false (private only) |
| `enable_prefix_delegation` | true | true | true |
| `enable_pod_eni` | off | off | true |
| `enable_network_policy` | off | true | true |
| `enable_efs_csi` | off | if RWX | true |
| system node size | t4g.medium | t4g.large | m7g.large + Karpenter spot |

**Registry & security baseline — `04-ecr`, `05-security-baseline`**

| Variable | Small | Medium | Large |
|---|---|---|---|
| `enable_enhanced_scan` (04) | off | off | true |
| `enable_guardduty` (05) | off | true | true |
| `enable_cloudtrail` (05) | off | off | true |
| `enable_config` (05) | off | off | true |
| `enable_securityhub` (05) | off | off | true |

**Observability, backup, edge — `06`–`08`**

| Variable | Small | Medium | Large |
|---|---|---|---|
| `enable_amp` (06) | off | optional | true |
| `enable_backup` (07) | off | true | true |
| `enable_waf` (08) | off | true | true |

Rule of thumb: **small = correctness only** (cluster runs, IAM ready, nothing paid);
**medium = observability + backup + audit logging + encryption**; **large = full
security/compliance + private endpoint + edge/egress controls + per-AZ HA**.
