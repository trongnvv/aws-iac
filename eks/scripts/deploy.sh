#!/usr/bin/env bash
# Deploy one environment: scripts/deploy.sh <env>   (e.g. dev, prod)
# Each env is a set of per-layer roots under envs/<env>/ that call ../../modules/*.
# Roots have concrete S3 backends (key prefixed by env), so `tofu init` just works.
# Prereq: run ../foundation/apply.sh once (state backend + DNS).
set -euo pipefail
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"   # shared across every root here — same aws/http provider version everywhere
export GODEBUG="${GODEBUG:+$GODEBUG,}http2client=0"   # tofu's HTTP/2 provider downloads from GitHub CDN intermittently stall at ~160KB/s
cd "$(dirname "$0")/.."
ENV="${1:?usage: deploy.sh <env>   (dir must exist under envs/)}"
ENVDIR="envs/$ENV"
[ -d "$ENVDIR/00-network" ] || { echo "no such env: $ENVDIR"; exit 1; }
REGION=ap-southeast-1
source "$ENVDIR/config.env"

# ECR is shared (foundation/02-ecr), not per-env — run `foundation/apply.sh` first.
LAYER0="00-network 01-eks 02-karpenter-infra 03-addon-iam 04-security-baseline 05-observability-aws 06-backup-aws 07-waf"

echo "== layer0 · env=$ENV =="
for d in $LAYER0; do
  ( cd "$ENVDIR/$d" && tofu init && tofu apply -auto-approve )
done

echo "== wire cluster + env =="
export AWS_REGION=$REGION
export CLUSTER_NAME=$(cd "$ENVDIR/01-eks" && tofu output -raw cluster_name)
export VPC_ID=$(cd "$ENVDIR/00-network" && tofu output -raw vpc_id)
export KARPENTER_QUEUE_NAME=$(cd "$ENVDIR/02-karpenter-infra" && tofu output -raw karpenter_queue_name)
export KARPENTER_NODE_ROLE=$(cd "$ENVDIR/02-karpenter-infra" && tofu output -raw karpenter_node_iam_role_name)
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
kubectl apply -f ad-hoc/gp3-default-storageclass.yaml   # default StorageClass (EBS CSI)
echo "${L2:-}" | grep -q velero && export BACKUP_BUCKET=$(cd "$ENVDIR/06-backup-aws" && tofu output -raw velero_bucket)
echo "${L1:-}" | grep -q 09-dns-scale && export DNS_CLUSTER_IP=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')

echo "== layer1 =="
for d in ${L1:-}; do ( cd "layer1-addons/$d" && helmfile apply ); done
[ "${NETPOL:-0}" = "1" ] && kubectl apply -f layer1-addons/07-network-policy/manifests.yaml

echo "== layer2 =="
for d in ${L2:-}; do ( cd "layer2-platform/$d" && helmfile apply ); done

echo "== done: $ENV =="
