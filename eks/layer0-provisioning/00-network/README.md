# 00-network

VPC foundation for the EKS cluster.

**Builds:** VPC (`/16`), public + private-app + private-isolated subnets across 3 AZs,
IGW, single NAT (lab cost), VPC endpoints (ECR/S3/etc. to cut NAT cost).

**Key tags:**
- Public subnets: `kubernetes.io/role/elb = 1`
- App subnets: `kubernetes.io/role/internal-elb = 1`, `karpenter.sh/discovery = <cluster>`

**Outputs (contract for later folders):** `vpc_id`, `public_subnet_ids`,
`app_subnet_ids`, `isolated_subnet_ids`.
