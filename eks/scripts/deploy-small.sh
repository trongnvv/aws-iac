#!/usr/bin/env bash
# Small (dev/lab): cluster + core add-ons only. No paid features (defaults off).
# Requires: ACME_EMAIL (cert-manager).
set -euo pipefail
cd "$(dirname "$0")/.."
REGION=ap-southeast-1
: "${ACME_EMAIL:?export ACME_EMAIL=you@example.com before running}"

# Prereq: run ../foundation/apply.sh once (S3 state backend + DNS zone) first.

echo "== layer0 =="
for d in 00-network 01-eks 02-karpenter-infra 03-addon-iam 04-ecr; do
  (cd "layer0-provisioning/$d" && tofu init && tofu apply -auto-approve)
done

echo "== wire cluster + env =="
export AWS_REGION=$REGION
export CLUSTER_NAME=$(cd layer0-provisioning/01-eks && tofu output -raw cluster_name)
export VPC_ID=$(cd layer0-provisioning/00-network && tofu output -raw vpc_id)
export KARPENTER_QUEUE_NAME=$(cd layer0-provisioning/02-karpenter-infra && tofu output -raw karpenter_queue_name)
export KARPENTER_NODE_ROLE=$(cd layer0-provisioning/02-karpenter-infra && tofu output -raw karpenter_node_iam_role_name)
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo "== layer1 =="
for d in 00-karpenter 01-metrics-server 02-aws-load-balancer-controller 04-cert-manager 05-external-secrets; do
  (cd "layer1-addons/$d" && helmfile apply)
done

echo "== layer2 =="
for d in 00-argocd 01-observability; do (cd "layer2-platform/$d" && helmfile apply); done

echo "== done: small =="
