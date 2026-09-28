#!/usr/bin/env bash
# Deploy the dev environment. By default runs all three layers in order; pass a
# layer name to run just that one.
#   ./deploy.sh                 # 00-infra -> 01-addons -> 02-platform
#   ./deploy.sh 00-infra        # Terraform infra only (+ refresh outputs.cache.json)
#   ./deploy.sh 01-addons       # core add-ons only (cluster must already be up)
#   ./deploy.sh 02-platform     # platform services only
# Self-contained: every Helm value is hardcoded plain YAML, so there is no
# `tofu output` wiring between the layers.
# Prereq: run ../../foundation/apply.sh once (state backend + shared ECR + DNS).
set -euo pipefail
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"   # shared across every root — same provider version everywhere
export GODEBUG="${GODEBUG:+$GODEBUG,}http2client=0"   # tofu HTTP/2 provider downloads occasionally stall
cd "$(dirname "$0")"
REGION=ap-southeast-1
CLUSTER=eks-dev

LAYER="${1:-all}"
case "$LAYER" in
  all|00-infra|01-addons|02-platform) ;;
  *) echo "usage: $0 [all|00-infra|01-addons|02-platform]"; exit 1 ;;
esac
run() { [ "$LAYER" = "all" ] || [ "$LAYER" = "$1" ]; }

if run 00-infra; then
  echo "== 00-infra (Terraform) · env=dev =="
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
fi

if run 01-addons || run 02-platform; then
  echo "== wire kubeconfig =="
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
  kubectl apply -f ../../ad-hoc/gp3-default-storageclass.yaml   # default StorageClass (EBS CSI)
fi

if run 01-addons; then
  echo "== 01-addons =="
  for d in 01-addons/*/; do ( cd "$d" && helmfile apply --skip-diff-on-install ); done
fi

if run 02-platform; then
  echo "== 02-platform =="
  for d in 02-platform/*/; do ( cd "$d" && helmfile apply --skip-diff-on-install ); done
fi

echo "== done: dev ($LAYER) =="
