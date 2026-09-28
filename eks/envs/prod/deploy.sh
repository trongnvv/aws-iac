#!/usr/bin/env bash
# Deploy the prod environment end-to-end: 00-infra (Terraform) -> 01-addons -> 02-platform.
# Self-contained: every Helm value is hardcoded plain YAML, so there is no
# `tofu output` wiring between the layers.
# Prereq: run ../../foundation/apply.sh once (state backend + shared ECR + DNS).
set -euo pipefail
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"   # shared across every root — same provider version everywhere
export GODEBUG="${GODEBUG:+$GODEBUG,}http2client=0"   # tofu HTTP/2 provider downloads occasionally stall
cd "$(dirname "$0")"
REGION=ap-southeast-1
CLUSTER=eks-prod

echo "== 00-infra (Terraform) · env=prod =="
for d in 00-infra/*/; do
  ( cd "$d" && tofu init && tofu apply -auto-approve )
done

# Cache the real Terraform outputs into one file (keyed by root). Reference only —
# the helm values are hardcoded; diff this file to confirm they still match reality
# (cluster_name, vpc_id, karpenter queue/role, velero bucket, ...). Git-ignored.
echo "== cache infra outputs -> outputs.cache.json =="
for d in 00-infra/*/; do
  ( cd "$d" && tofu output -json 2>/dev/null || echo '{}' ) | jq --arg k "$(basename "$d")" '{($k): .}'
done | jq -s 'add' > outputs.cache.json

echo "== wire kubeconfig =="
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl apply -f ../../ad-hoc/gp3-default-storageclass.yaml   # default StorageClass (EBS CSI)

echo "== 01-addons =="
for d in 01-addons/*/; do ( cd "$d" && helmfile apply ); done

echo "== 02-platform =="
for d in 02-platform/*/; do ( cd "$d" && helmfile apply ); done

echo "== done: prod =="
