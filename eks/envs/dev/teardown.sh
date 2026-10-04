#!/usr/bin/env bash
# Tear down the dev environment. Order matters: FIRST drain the AWS resources that live
# OUTSIDE Terraform (Karpenter EC2 nodes, LBC ALBs/NLBs) while their controllers are still
# running — otherwise their orphaned ENIs block the VPC destroy. Then Helm releases, then
# the Terraform layers in reverse. Guards skip anything not applied.
set -uo pipefail
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
cd "$(dirname "$0")"
REGION=ap-southeast-1
CLUSTER=eks-dev

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

echo "== 03-application (reverse) =="
for d in $(ls -d 03-application/*/ 2>/dev/null | sort -r); do ( cd "$d" && helmfile destroy 2>/dev/null ) || true; done

echo "== 02-platform (reverse) =="
for d in $(ls -d 02-platform/*/ 2>/dev/null | sort -r); do ( cd "$d" && helmfile destroy 2>/dev/null ) || true; done

echo "== 01-addons (reverse) =="
for d in $(ls -d 01-addons/*/ 2>/dev/null | sort -r); do ( cd "$d" && helmfile destroy 2>/dev/null ) || true; done

echo "== 00-infra (reverse) =="
for d in $(ls -d 00-infra/*/ | sort -r); do
  targets=()
  if [ "$d" = "00-infra/05-observability-aws/" ]; then
    # Keep the AMP workspace: its ID is hardcoded in 02-platform values, and an idle
    # workspace costs ~$0. Destroying the roles also destroys their dependents
    # (policies, attachments, Pod Identity associations).
    targets=(-target=module.observability_aws.aws_iam_role.amp_write
             -target=module.observability_aws.aws_iam_role.fluent_bit
             -target=module.observability_aws.aws_iam_role.grafana)
  fi
  ( cd "$d" && tofu init >/dev/null 2>&1 && tofu destroy -auto-approve ${targets[@]+"${targets[@]}"} 2>/dev/null ) || true
done

echo "== orphaned EBS volumes (from PVCs — not deleted by tofu destroy) =="
ORPHANS=$(aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available \
  Name=tag:kubernetes.io/created-for/pvc/name,Values='*' \
  --query 'Volumes[].[VolumeId,Size,Tags[?Key==`kubernetes.io/created-for/pvc/name`]|[0].Value]' --output text)
if [ -n "$ORPHANS" ]; then
  echo "$ORPHANS"
  echo "⚠️  still billed (gp3 ~\$0.096/GB-month) — delete: aws ec2 delete-volume --volume-id <id>"
else
  echo "none"
fi

echo "== done: teardown dev =="
echo "If 00-network still fails (VPC 'DependencyViolation'), orphaned ENIs remain — list them:"
echo "  VPC=<vpc-id>; aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=\$VPC \\"
echo "    --query 'NetworkInterfaces[].[NetworkInterfaceId,Status,Description]' --output table"
