#!/usr/bin/env bash
# Tear down one environment: scripts/teardown.sh <env>
# Reverse order; guards skip what wasn't applied. Removes the LB controller
# (and its ALBs/ENIs) before the VPC.
set -uo pipefail
cd "$(dirname "$0")/.."
ENV="${1:?usage: teardown.sh <env>}"
ENVDIR="envs/$ENV"
[ -d "$ENVDIR/00-network" ] || { echo "no such env: $ENVDIR"; exit 1; }
source "$ENVDIR/config.env"

# point kubeconfig at this env's cluster (best effort)
( cd "$ENVDIR/01-eks" && tofu init >/dev/null 2>&1 && C=$(tofu output -raw cluster_name 2>/dev/null) \
  && aws eks update-kubeconfig --name "$C" --region ap-southeast-1 >/dev/null 2>&1 ) || true

echo "== layer2 =="
for d in ${L2:-}; do [ -f "layer2-platform/$d/helmfile.yaml" ] && ( cd "layer2-platform/$d" && helmfile destroy 2>/dev/null ) || true; done

echo "== layer1 =="
kubectl delete -f layer1-addons/07-network-policy/manifests.yaml 2>/dev/null || true
for d in ${L1:-}; do [ -f "layer1-addons/$d/helmfile.yaml" ] && ( cd "layer1-addons/$d" && helmfile destroy 2>/dev/null ) || true; done

echo "== layer0 (reverse) =="
for d in 08-waf 07-backup-aws 06-observability-aws 05-security-baseline 04-ecr 03-addon-iam 02-karpenter-infra 01-eks 00-network; do
  ( cd "$ENVDIR/$d" && tofu init >/dev/null 2>&1 && tofu destroy -auto-approve 2>/dev/null ) || true
done

echo "== done: teardown $ENV =="
