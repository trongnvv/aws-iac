# 01-eks

The EKS control plane + managed add-ons. Reads `00-network` via `terraform_remote_state`.

**Builds:**
- EKS cluster (private API optional), OIDC provider enabled
- Access Entries for the admin IAM role (no `aws-auth` ConfigMap)
- Control-plane logging → CloudWatch
- Managed add-ons: **VPC CNI (prefix delegation on)**, CoreDNS, kube-proxy,
  EBS CSI driver, EKS Pod Identity agent

**Outputs:** `cluster_name`, `cluster_endpoint`, `oidc_provider_arn`,
`cluster_security_group_id`.
