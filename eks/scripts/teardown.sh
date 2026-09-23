#!/usr/bin/env bash
# Reverse teardown. Guards skip folders/releases that were never applied.
# helmfile destroy of the LB controller removes ALBs/ENIs — do it BEFORE the VPC.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "== layer2 =="
for d in 07-falco 06-service-mesh 05-api-gateway 04-kubecost 03-argo-rollouts 02-velero 01-observability 00-argocd; do
  [ -f "layer2-platform/$d/helmfile.yaml" ] && (cd "layer2-platform/$d" && helmfile destroy 2>/dev/null) || true
done

echo "== layer1 =="
kubectl delete -f layer1-addons/07-network-policy/manifests.yaml 2>/dev/null || true
for d in 09-dns-scale 08-keda 06-kyverno 05-external-secrets 04-cert-manager 03-external-dns \
         02-aws-load-balancer-controller 01-metrics-server 00-karpenter; do
  [ -f "layer1-addons/$d/helmfile.yaml" ] && (cd "layer1-addons/$d" && helmfile destroy 2>/dev/null) || true
done

echo "== layer0 (reverse) =="
for d in 08-waf 07-backup-aws 06-observability-aws 05-security-baseline 04-ecr \
         03-addon-iam 02-karpenter-infra 01-eks 00-network; do
  (cd "layer0-provisioning/$d" && tofu destroy -auto-approve 2>/dev/null) || true
done

echo "== done: teardown =="
