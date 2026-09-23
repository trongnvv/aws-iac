#!/usr/bin/env bash
# Medium (staging): + logging, encryption, network policy, backup, GuardDuty, WAF,
# DNS automation, policy engine, event scaling.
# Requires: ACME_EMAIL, DOMAIN_FILTER.
set -euo pipefail
cd "$(dirname "$0")/.."
REGION=ap-southeast-1
: "${ACME_EMAIL:?export ACME_EMAIL=you@example.com before running}"
: "${DOMAIN_FILTER:?export DOMAIN_FILTER=example.com before running}"

echo "== remote state =="
(cd bootstrap/00-tf-backend && tofu init && tofu apply -auto-approve)

echo "== tfvars (medium) =="
cat > layer0-provisioning/01-eks/terraform.tfvars <<'EOF'
enable_control_plane_logging = true
enable_secret_encryption     = true
enable_network_policy        = true
EOF
echo 'enable_guardduty = true' > layer0-provisioning/05-security-baseline/terraform.tfvars
echo 'enable_backup    = true' > layer0-provisioning/07-backup-aws/terraform.tfvars
echo 'enable_waf       = true' > layer0-provisioning/08-waf/terraform.tfvars

echo "== layer0 =="
for d in 00-network 01-eks 02-karpenter-infra 03-addon-iam 04-ecr \
         05-security-baseline 07-backup-aws 08-waf; do
  (cd "layer0-provisioning/$d" && tofu init && tofu apply -auto-approve)
done

echo "== wire cluster + env =="
export AWS_REGION=$REGION
export CLUSTER_NAME=$(cd layer0-provisioning/01-eks && tofu output -raw cluster_name)
export VPC_ID=$(cd layer0-provisioning/00-network && tofu output -raw vpc_id)
export KARPENTER_QUEUE_NAME=$(cd layer0-provisioning/02-karpenter-infra && tofu output -raw karpenter_queue_name)
export KARPENTER_NODE_ROLE=$(cd layer0-provisioning/02-karpenter-infra && tofu output -raw karpenter_node_iam_role_name)
export BACKUP_BUCKET=$(cd layer0-provisioning/07-backup-aws && tofu output -raw velero_bucket)
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo "== layer1 =="
for d in 00-karpenter 01-metrics-server 02-aws-load-balancer-controller 03-external-dns \
         04-cert-manager 05-external-secrets 06-kyverno 08-keda; do
  (cd "layer1-addons/$d" && helmfile apply)
done

echo "== layer2 =="
for d in 00-argocd 01-observability 02-velero; do (cd "layer2-platform/$d" && helmfile apply); done

echo "== done: medium =="
