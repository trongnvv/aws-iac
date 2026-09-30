#!/usr/bin/env bash
# Tear down the prod environment. Order matters: FIRST drain the AWS resources that live
# OUTSIDE Terraform (Karpenter EC2 nodes, LBC ALBs/NLBs) while their controllers are still
# running — otherwise their orphaned ENIs block the VPC destroy. Then Helm releases, then
# the Terraform layers in reverse. Guards skip anything not applied.
set -uo pipefail
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
cd "$(dirname "$0")"
REGION=ap-southeast-1
CLUSTER=eks-prod

# point kubeconfig at this env's cluster (best effort)
( aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1 ) || true

echo "== drain out-of-band AWS resources (while their controllers are still up) =="
# Karpenter: stop provisioning, then terminate existing nodes (the finalizer waits for the
# EC2 instance to actually terminate — else it orphans and its ENI blocks the VPC).
kubectl delete nodepools.karpenter.sh --all --ignore-not-found 2>/dev/null || true
kubectl delete nodeclaims.karpenter.sh --all --ignore-not-found --wait=true --timeout=180s 2>/dev/null || true
# LBC: delete everything that provisions an ALB/NLB so LBC removes them + their ENIs.
kubectl delete ingress --all-namespaces --all --ignore-not-found 2>/dev/null || true
kubectl delete gateways.gateway.networking.k8s.io --all-namespaces --all --ignore-not-found 2>/dev/null || true
kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer --ignore-not-found 2>/dev/null || true
echo "== wait 90s for LBC/Karpenter to delete the AWS LBs + instances =="
sleep 90

echo "== 02-platform (reverse) =="
for d in $(ls -d 02-platform/*/ 2>/dev/null | sort -r); do ( cd "$d" && helmfile destroy 2>/dev/null ) || true; done

echo "== 01-addons (reverse) =="
for d in $(ls -d 01-addons/*/ 2>/dev/null | sort -r); do ( cd "$d" && helmfile destroy 2>/dev/null ) || true; done

echo "== 00-infra (reverse) =="
for d in $(ls -d 00-infra/*/ | sort -r); do
  ( cd "$d" && tofu init >/dev/null 2>&1 && tofu destroy -auto-approve 2>/dev/null ) || true
done

echo "== done: teardown prod =="
echo "If 00-network still fails (VPC 'DependencyViolation'), orphaned ENIs remain — list them:"
echo "  VPC=<vpc-id>; aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=\$VPC \\"
echo "    --query 'NetworkInterfaces[].[NetworkInterfaceId,Status,Description]' --output table"
