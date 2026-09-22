# EKS Platform Roadmap

From "a cluster that runs" to a platform fit for a large, regulated system.
Legend: ✅ built · 🔲 todo · priority P0 (blocks prod) · P1 (needed at scale) · P2 (mature).
Cost: 🟢 free/negligible · 🟡 low · 🟠 moderate · 🔴 high.
Tag `0+N` = split across layers: IAM/AWS side in layer0, Helm chart in layer1/2.

## Current state
Layer0: network (prefix delegation) · cluster + managed add-ons · Access Entries ·
Karpenter infra · add-on IAM (LBC, ESO). Enough to run a cluster and expose one app.

## bootstrap/ — remote state (new layer)
| Item | Folder | Pri | Cost |
|---|---|---|---|
| ✅ S3 state bucket + DynamoDB lock | `bootstrap/00-tf-backend` | P0 | 🟢 pennies/mo |

## layer0-provisioning/ — OpenTofu (AWS resources)
| Item | Where | Pri | Cost |
|---|---|---|---|
| ✅ network · eks · karpenter-infra · addon-iam (LBC/ESO) | `00–04` | — | 🔴 anchor: EKS control plane ~$73/mo + NAT ~$32/mo + nodes + endpoints |
| ✅ Control-plane logging (`enable_control_plane_logging`) | `01-eks` | P0 | 🟡 CloudWatch ingest, scales with volume |
| ✅ Secret encryption at rest / KMS (`enable_secret_encryption`) | `01-eks` | P0 | 🟢 ~$1/key/mo |
| ✅ Private API endpoint (`cluster_endpoint_public/private_access`) | `01-eks` | P0 | 🟢 free (bastion/VPN if added = extra) |
| 🔲 SG-for-pods / secondary CIDR (IP scale) | patch `00-network`, `01-eks` | P1 | 🟢 free |
| 🔲 ECR + image scanning | `06-ecr` | P1 | 🟡 $0.10/GB storage; enhanced scan extra |
| 🔲 WAF (edge) | `07-waf` | P0 | 🟡 ~$5/ACL + $1/rule + $0.60/M req |
| ✅ Security baseline: GuardDuty EKS, CloudTrail, Config, Security Hub (`enable_guardduty/cloudtrail/config/securityhub`, default off) | `08-security-baseline` | P0 | 🟠 scales with events/items recorded |
| ✅ Managed Prometheus (AMP) workspace + IAM (`enable_amp`, default off) `(0+2)` | `09-observability-aws` | P0 | 🟠 per-sample ingest + storage |
| ✅ Backup vault / Velero IAM + S3 (`enable_backup`, default off) `(0+2)` | `10-backup-aws` | P0 | 🟡 snapshot + S3 storage |
| 🔲 IAM for KEDA / external-dns / cert-manager DNS-01 / kubecost | extend `04-addon-iam` | P1 | 🟢 free |

### What each layer0 addition does
- **Control-plane logging** — turn on `cluster_enabled_log_types` (api, audit, authenticator,
  controllerManager, scheduler) → CloudWatch. The audit trail auditors ask for, and the first
  thing you read when access or the API misbehaves.
- **Secret encryption at rest (KMS)** — `cluster_encryption_config` with a KMS key envelope-encrypts
  Kubernetes Secrets in etcd (on top of base EBS encryption). A hard requirement for regulated data.
- **Private API endpoint** — flip the endpoint to private (or tightly restrict the public CIDRs);
  the API server is then reachable only from inside the VPC, via a bastion/VPN. Shrinks the attack surface.
- **SG-for-pods / secondary CIDR** — `ENABLE_POD_ENI` attaches security groups to individual pods
  (e.g. only these pods may reach RDS); a secondary VPC CIDR / custom networking expands pod IP space
  before the app subnets run dry.
- **ECR + image scanning** — private image registry with scan-on-push (basic, or enhanced via Inspector)
  so images stay in-account and CVEs surface before deploy.
- **WAF (edge)** — a `wafv2` web ACL on the ALB: managed rule groups (SQLi/XSS), IP and rate rules.
  The L7 shield in front of ingress.
- **Security baseline** — GuardDuty (EKS runtime + audit-log threat detection), CloudTrail (API audit),
  Config (resource-compliance rules), Security Hub (aggregates the findings). The account-level controls
  a financial audit expects.
- **Managed Prometheus (AMP) workspace + IAM** — a managed metrics backend the collector remote-writes to,
  so you don't self-host Prometheus long-term storage. IAM lets ADOT/collector pods write to it.
- **Backup vault / Velero IAM + S3** — an S3 bucket / Backup vault plus the IAM Velero needs to snapshot
  volumes and cluster resources for DR and restore drills.
- **IAM for KEDA / external-dns / cert-manager DNS-01 / kubecost** — Pod Identity roles so those add-ons
  can call the AWS APIs they need (SQS/CloudWatch scalers for KEDA, Route 53 for external-dns and
  cert-manager DNS-01 challenges, cost/CUR access for kubecost). Charts live in layer1/2; the roles live here.

## layer1-addons/ — Helmfile (core cluster add-ons)
| Item | Folder | Pri | Cost |
|---|---|---|---|
| 🔲 karpenter · metrics-server · LBC · external-dns · cert-manager · external-secrets | `00–05` | P0 | 🟢 charts free (run on existing nodes); LBC→ALB billed separately (see N-S) |
| 🔲 EFS CSI (RWX)  *(EBS CSI = managed add-on in `01-eks`)* | `06-efs-csi` | P1 | 🟡 EFS ~$0.30/GB/mo |
| 🔲 CoreDNS autoscaler + NodeLocal DNSCache | `07-dns-scale` | P1 | 🟢 free (compute) |
| 🔲 Policy engine (Kyverno / Gatekeeper) | `08-kyverno` | P0 | 🟢 free (compute) |
| 🔲 NetworkPolicy (Cilium / VPC CNI netpol) | `09-network-policy` | P0 | 🟢 free |
| 🔲 KEDA (event-driven autoscale) `(0+1)` | `10-keda` | P1 | 🟢 free (compute) |

## layer2-platform/ — Helmfile (platform & apps)
| Item | Folder | Pri | Cost |
|---|---|---|---|
| 🔲 GitOps: ArgoCD app-of-apps + ApplicationSets | `00-argocd` | P0 | 🟢 free (compute) |
| 🔲 Observability stack: Prometheus/Grafana + Loki + Tempo + ADOT `(0+2)` | `01-observability` | P0 | 🟠 compute + EBS/S3 for TSDB/logs/traces |
| 🔲 Service mesh (Istio/Linkerd, mTLS) | `02-service-mesh` | P2 | 🟡 sidecar CPU/mem overhead (indirect) |
| 🔲 Progressive delivery (Argo Rollouts) | `03-argo-rollouts` | P1 | 🟢 free (compute) |
| 🔲 Cost visibility (Kubecost/OpenCost) `(0+2)` | `04-kubecost` | P1 | 🟢 OSS free (paid tier optional) |
| 🔲 Runtime security (Falco) | `05-falco` | P2 | 🟢 free (compute) |
| 🔲 Backup client (Velero) `(0+2)` | `06-velero` | P0 | 🟡 S3 backup storage |

## North-South networking (spans layers)
The one axis worth calling out explicitly.

**Inbound edge**
```
Internet → [CloudFront → WAF/Shield] → [ALB/NLB (LBC)] → [API GW / Gateway API] → Service
```
| Item | Where | Pri | Cost |
|---|---|---|---|
| ✅ Ingress: LBC → ALB/NLB + external-dns + cert-manager/ACM | `layer1/02,03,04` | — | 🟡 ALB ~$16/mo + LCU; ACM/LE certs free |
| 🔲 WAF + Shield (DDoS) + CloudFront | `layer0/07-waf` | P0 | 🟠 WAF + CloudFront per-GB; 🔴 Shield Advanced ~$3000/mo (Standard free) |
| 🔲 API management (Kong/APISIX or AWS API Gateway) — auth, rate-limit, quota | `layer2` or `layer0` | P1 | 🟡 Kong OSS free (compute) / API GW $3.50/M calls |
| 🔲 Gateway API (successor to Ingress) | `layer1` | P2 | 🟢 free (controller) |

**Outbound egress** — mostly absent today (all pods → NAT → open internet)
```
Service → [Egress NetworkPolicy] → [Egress GW / Network Firewall] → [NAT (static EIP)] → partner/exchange
```
| Item | Where | Pri | Cost |
|---|---|---|---|
| ✅ Static egress IP (fixed NAT EIP, output `nat_public_ips`) for partner/exchange source-IP allowlisting | `layer0/00-network` | P0 | 🟢 EIP free while attached (NAT already billed) |
| 🔲 Egress filtering (allowlist) | `layer1/09-network-policy` | P0 | 🟢 free |
| 🔲 Centralized egress inspection: AWS Network Firewall or Istio egress gateway | `layer0/00-network` or `layer2/02-service-mesh` | P1 | 🔴 Network Firewall ~$285/mo/endpoint + data; 🟡 Istio egress = compute |

## Not a platform layer (don't put these in subfolders)
| Item | Belongs to |
|---|---|
| PDB · topology-spread · priorityClass · ALB `group.name` | each app's manifests |
| Upgrade automation (`pluto`/`kubent`, Karpenter drift) | CI pipeline / scripts |
| Multi-cluster / landing zone (multi-account, SCP) | repo architecture — repeat layer0–2 per cluster + one ArgoCD hub; account-level in a separate foundation repo |

## Suggested build order
1. `bootstrap` remote state → patch `01-eks` (logging, KMS, private endpoint)
2. P0 security & edge: WAF, security-baseline, network-policy, static egress IP
3. P0 platform: ArgoCD → observability → external-secrets → backup
4. P1 scale: KEDA, dns-scale, cost, progressive delivery, API management
5. P2 mature: service mesh, Falco, Gateway API, multi-cluster
```
