# layer0-provisioning (OpenTofu — AWS resources)

AWS-side of the platform. Dependency-ordered; each folder has its own state and
later folders read earlier ones via `terraform_remote_state`.

| # | Folder | What |
|---|---|---|
| 00 | network | VPC, 3-AZ subnets, NAT, endpoints, discovery tags, static egress IP, secondary CIDR |
| 01 | eks | cluster, managed add-ons, Access Entries, logging, KMS, prefix delegation, pod-ENI, netpol, EFS CSI |
| 02 | node-group | reserved for extra node pools (bootstrap pool lives in 01) |
| 03 | karpenter-infra | Karpenter node IAM role, instance profile, SQS interruption queue |
| 04 | addon-iam | Pod Identity roles: LBC, ESO, external-dns, KEDA, cert-manager, kubecost |
| 05 | ecr | private registry + image scanning |
| 06 | security-baseline | GuardDuty, CloudTrail, Config, Security Hub |
| 07 | observability-aws | Amazon Managed Prometheus workspace + IAM |
| 08 | backup-aws | Velero S3 bucket + IAM |
| 09 | waf | regional web ACL for the ALB |
| 10 | network-firewall | centralized egress inspection / domain allowlist |

Apply `00 → 10` in order. `02`, and the paid folders left off, create nothing until enabled.

## Using variables by system size

Everything paid is behind an `enable_*` variable defaulting to `false`. Drive them
per env from a `terraform.tfvars` in each folder — **don't edit defaults**. Turn
features on as the system grows; a lab pays only for the cluster + NAT.
`off` = not used at that size.

**Networking — `00-network`**

| Variable | Small | Medium | Large |
|---|---|---|---|
| `nat_per_az` | off (single NAT) | off | true (per-AZ HA) |
| `enable_secondary_cidr` | off | off | true if IP-heavy |

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

**Registry & security baseline — `05-ecr`, `06-security-baseline`**

| Variable | Small | Medium | Large |
|---|---|---|---|
| `enable_enhanced_scan` (05) | off | off | true |
| `enable_guardduty` (06) | off | true | true |
| `enable_cloudtrail` (06) | off | off | true |
| `enable_config` (06) | off | off | true |
| `enable_securityhub` (06) | off | off | true |

**Observability, backup, edge & egress — `07`–`10`**

| Variable | Small | Medium | Large |
|---|---|---|---|
| `enable_amp` (07) | off | optional | true |
| `enable_backup` (08) | off | true | true |
| `enable_waf` (09) | off | true | true |
| `enable_network_firewall` (10) | off | off | true if required |

Rule of thumb: **small = correctness only** (cluster runs, IAM ready, nothing paid);
**medium = observability + backup + audit logging + encryption**; **large = full
security/compliance + private endpoint + edge/egress controls + per-AZ HA**.
