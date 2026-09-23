#!/usr/bin/env bash
# Tear down one environment: scripts/teardown.sh <env>
# Reverse order; guards skip what wasn't applied. Removes the LB controller
# (and its ALBs/ENIs) before the VPC.
set -uo pipefail
cd "$(dirname "$0")/.."
ENV="${1:?usage: teardown.sh <env>}"
ENVDIR="envs/$ENV"
[ -f "$ENVDIR/config.env" ] || { echo "no env config: $ENVDIR/config.env"; exit 1; }
source "$ENVDIR/config.env"
BACKEND="$PWD/$ENVDIR/backend.hcl"

init0() { tofu init -reconfigure -backend-config="$BACKEND" -backend-config="key=$ENV/layer0/$1/terraform.tfstate" >/dev/null 2>&1; }

# point kubeconfig at this env's cluster (best effort)
( cd layer0-provisioning/01-eks && init0 01-eks && C=$(tofu output -raw cluster_name 2>/dev/null) \
  && aws eks update-kubeconfig --name "$C" --region ap-southeast-1 >/dev/null 2>&1 ) || true

echo "== layer2 =="
for d in ${L2:-}; do [ -f "layer2-platform/$d/helmfile.yaml" ] && (cd "layer2-platform/$d" && helmfile destroy 2>/dev/null) || true; done

echo "== layer1 =="
kubectl delete -f layer1-addons/07-network-policy/manifests.yaml 2>/dev/null || true
for d in ${L1:-}; do [ -f "layer1-addons/$d/helmfile.yaml" ] && (cd "layer1-addons/$d" && helmfile destroy 2>/dev/null) || true; done

echo "== layer0 (reverse) =="
for d in 08-waf 07-backup-aws 06-observability-aws 05-security-baseline 04-ecr 03-addon-iam 02-karpenter-infra 01-eks 00-network; do
  (cd "layer0-provisioning/$d" && init0 "$d" && tofu destroy -auto-approve 2>/dev/null) || true
done

echo "== done: teardown $ENV =="
