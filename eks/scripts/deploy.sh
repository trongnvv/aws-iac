#!/usr/bin/env bash
# Deploy one environment: scripts/deploy.sh <env>   (e.g. dev, prod)
# Each env has its own state (key prefix = <env>) and its own toggles/add-on lists
# in envs/<env>/. Prereq: run ../foundation/apply.sh once (state backend + DNS).
set -euo pipefail
cd "$(dirname "$0")/.."
ENV="${1:?usage: deploy.sh <env>   (dir must exist under envs/)}"
ENVDIR="envs/$ENV"
[ -f "$ENVDIR/config.env" ] || { echo "no env config: $ENVDIR/config.env"; exit 1; }
REGION=ap-southeast-1
source "$ENVDIR/config.env"
BACKEND="$PWD/$ENVDIR/backend.hcl"

LAYER0="00-network 01-eks 02-karpenter-infra 03-addon-iam 04-ecr 05-security-baseline 06-observability-aws 07-backup-aws 08-waf"

echo "== layer0 · env=$ENV =="
for d in $LAYER0; do
  (cd "layer0-provisioning/$d" \
    && tofu init -reconfigure -backend-config="$BACKEND" -backend-config="key=$ENV/layer0/$d/terraform.tfstate" \
    && tofu apply -auto-approve)
done

echo "== wire cluster + env =="
export AWS_REGION=$REGION
export CLUSTER_NAME=$(cd layer0-provisioning/01-eks && tofu output -raw cluster_name)
export VPC_ID=$(cd layer0-provisioning/00-network && tofu output -raw vpc_id)
export KARPENTER_QUEUE_NAME=$(cd layer0-provisioning/02-karpenter-infra && tofu output -raw karpenter_queue_name)
export KARPENTER_NODE_ROLE=$(cd layer0-provisioning/02-karpenter-infra && tofu output -raw karpenter_node_iam_role_name)
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
[ "${TF_VAR_enable_backup:-false}" = "true" ] && export BACKUP_BUCKET=$(cd layer0-provisioning/07-backup-aws && tofu output -raw velero_bucket)
echo "${L1:-}" | grep -q 09-dns-scale && export DNS_CLUSTER_IP=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')

echo "== layer1 =="
for d in ${L1:-}; do (cd "layer1-addons/$d" && helmfile apply); done
[ "${NETPOL:-0}" = "1" ] && kubectl apply -f layer1-addons/07-network-policy/manifests.yaml

echo "== layer2 =="
for d in ${L2:-}; do (cd "layer2-platform/$d" && helmfile apply); done

echo "== done: $ENV =="
