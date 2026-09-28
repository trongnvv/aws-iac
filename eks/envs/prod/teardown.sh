#!/usr/bin/env bash
# Tear down the prod environment (reverse order). Remove the Helm-managed LBs before
# the VPC so no orphaned ALB/ENI blocks the network destroy. Guards skip anything
# that was not applied.
set -uo pipefail
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
cd "$(dirname "$0")"
REGION=ap-southeast-1
CLUSTER=eks-prod

# point kubeconfig at this env's cluster (best effort)
( aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1 ) || true

echo "== 02-platform (reverse) =="
for d in $(ls -d 02-platform/*/ 2>/dev/null | sort -r); do ( cd "$d" && helmfile destroy 2>/dev/null ) || true; done

echo "== 01-addons (reverse) =="
for d in $(ls -d 01-addons/*/ 2>/dev/null | sort -r); do ( cd "$d" && helmfile destroy 2>/dev/null ) || true; done

echo "== 00-infra (reverse) =="
for d in $(ls -d 00-infra/*/ | sort -r); do
  ( cd "$d" && tofu init >/dev/null 2>&1 && tofu destroy -auto-approve 2>/dev/null ) || true
done

echo "== done: teardown prod =="
