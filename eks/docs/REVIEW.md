# Review & hardening checklist

An EKS-expert pass over the repo. High-severity items and the redundancy cleanup
are done; what remains is Medium/Low hardening.

## Resolved
- **Remote state wired.** All layer0 folders + their `terraform_remote_state`
  reads use the S3 backend (bucket `eks-iac-tfstate`, native S3 locking `use_lockfile`);
  `foundation` stays local. (was High #1)
- **Network Firewall done right.** Folded into `00-network` with dedicated
  firewall subnets + app-egress redirect (app → firewall endpoint → NAT), gated by
  `enable_network_firewall`. (was High #2)
- **Chart versions verified.** All 16 pinned Helm charts (incl. kuma + the two OCI
  charts) exist at the pinned version. (was High #3)
- **Redundancy trimmed.** Removed 13 duplicate per-folder READMEs (kept the 3 layer
  READMEs + bootstrap); removed the empty `02-node-group` placeholder and renumbered
  layer0 to `00–08` contiguous.

## Correctness — Medium
1. **node-local-dns** values (`config.dnsServer/localDnsIp`) — verify against the
   deliveryhero chart schema; confirm the kube-dns ClusterIP.
2. **Observability not durable.** kube-prometheus-stack defaults Prometheus to
   `emptyDir`; the AMP workspace (`06`) isn't wired to `remoteWrite`. → PVC (gp3) +
   retention, or remoteWrite to AMP.
3. **Audit buckets lack encryption.** CloudTrail/Config S3 buckets have no SSE or
   lifecycle (trail should use KMS).
4. **No provider `default_tags`.** Add owner/env/cost-center tags globally.
5. **cert-manager HTTP-01 over ALB is flaky** (ALB latency vs ACME timeout). Prefer
   ACM for ALB-terminated TLS; HTTP-01 suits ingress-nginx.
6. **Secondary CIDR** is created but unused until the in-cluster `ENIConfig` (custom
   networking) is applied and `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true`.
7. **Kong's Gateway API mode (unmanaged `GatewayClass`) and Kuma haven't been run
   yet** — first real exercise is `docs/hands-on/test-plans/01-TEST-INGRESS-GATEWAY-API.md`.

## Correctness — Low
- System node group untainted — add `CriticalAddonsOnly` + tolerations.
- Karpenter NodePool sets only `limits.cpu` — add `limits.memory` + `expireAfter`.
- Kyverno installed with no policies — add a baseline set.
- GuardDuty enables EKS_AUDIT_LOGS only — runtime monitoring agent off.

## Strengths
- Clean layer separation, one owner per component, managed-add-on vs Helm split.
- Pod Identity over IRSA; Access Entries (API mode) over aws-auth.
- Paid features default `enable_* = false` — real cost discipline.
- Prefix delegation, Karpenter discovery tags, static egress IP, VPC endpoints,
  proper Network Firewall egress path.
- Helmfile `values/*.gotmpl` convention; deploy scripts self-derive infra vars.
