# 00-karpenter

Karpenter Helm chart + a default `NodePool` and `EC2NodeClass`.
Depends on `layer0/03-karpenter-infra` (IAM role, instance profile, SQS queue)
and runs on the `layer0/02-node-group` nodes.

**Installs:** `helmfile.yaml` (karpenter chart) + manifests:
- `NodePool` — spot + on-demand, c/m/r families, amd64 + arm64, consolidation on
- `EC2NodeClass` — AMI family, subnets/SGs via `karpenter.sh/discovery` tag
