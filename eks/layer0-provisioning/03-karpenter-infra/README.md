# 03-karpenter-infra

The AWS-side prerequisites for Karpenter. The Helm chart + NodePool live in
`layer1-addons/00-karpenter`.

**Builds:**
- Karpenter controller IAM role (IRSA or Pod Identity)
- Node IAM role + instance profile for Karpenter-launched nodes
- SQS interruption queue + EventBridge rules (spot interruption / rebalance notices)
