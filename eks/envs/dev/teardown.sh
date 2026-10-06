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

# VPC id (00-network still has state at this point) — scopes every AWS-API sweep below to THIS VPC.
VPC_ID=$( (cd 00-infra/00-network && tofu output -raw vpc_id 2>/dev/null) || true )

# Directly delete the LBC-created ALBs/NLBs for THIS cluster — independent of the controller, which
# may already be down (then nothing else deletes them, and their ENIs block the VPC destroy). Scoped
# twice: load balancer must be IN this VPC *and* carry the LBC tag elbv2.k8s.aws/cluster=<cluster>.
# Never touches LBs outside this cluster/VPC.
kill_cluster_lbs() {
  [ -n "${VPC_ID:-}" ] || return 0
  for arn in $(aws elbv2 describe-load-balancers --region "$REGION" \
      --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null); do
    owner=$(aws elbv2 describe-tags --region "$REGION" --resource-arns "$arn" \
      --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster'].Value | [0]" --output text 2>/dev/null)
    if [ "$owner" = "$CLUSTER" ]; then
      echo "  deleting LBC load balancer $arn"
      aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn" 2>/dev/null || true
    fi
  done
  # Orphaned target groups tagged for this cluster (delete-load-balancer leaves them behind).
  for tg in $(aws elbv2 describe-target-groups --region "$REGION" \
      --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" --output text 2>/dev/null); do
    owner=$(aws elbv2 describe-tags --region "$REGION" --resource-arns "$tg" \
      --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster'].Value | [0]" --output text 2>/dev/null)
    [ "$owner" = "$CLUSTER" ] && aws elbv2 delete-target-group --region "$REGION" --target-group-arn "$tg" 2>/dev/null || true
  done
}

# Delete detached (status=available) ENIs in this VPC — left by deleted LBs/endpoints, they're what
# causes the VPC 'DependencyViolation'. Only 'available' (orphaned), never in-use. Retries because an
# in-use ENI flips to 'available' only after its LB/endpoint finishes detaching (takes a minute).
sweep_enis() {
  [ -n "${VPC_ID:-}" ] || return 0
  for round in 1 2 3 4 5; do
    local found=0
    for eni in $(aws ec2 describe-network-interfaces --region "$REGION" \
        --filters Name=vpc-id,Values="$VPC_ID" Name=status,Values=available \
        --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null); do
      echo "  [round $round] deleting orphaned ENI $eni"
      aws ec2 delete-network-interface --region "$REGION" --network-interface-id "$eni" 2>/dev/null || true
      found=1
    done
    # stop early once a round finds nothing; else wait for more ENIs to detach
    [ "$found" = 0 ] && break
    sleep 20
  done
}

# Release only THIS cluster's NAT EIPs if they're left unassociated (tagged Name=<cluster>-nat by
# modules/network). Scoped by that tag + AssociationId==null → never releases an EIP outside this IaC.
release_cluster_eips() {
  for alloc in $(aws ec2 describe-addresses --region "$REGION" \
      --filters "Name=tag:Name,Values=${CLUSTER}-nat" \
      --query 'Addresses[?AssociationId==`null`].AllocationId' --output text 2>/dev/null); do
    echo "  releasing orphaned EIP $alloc (${CLUSTER}-nat)"
    aws ec2 release-address --region "$REGION" --allocation-id "$alloc" 2>/dev/null || true
  done
}

# Delete LBC-created security groups left behind when we kill LBs directly (controller down → its
# managed SGs orphan, and an SG is a VPC dependency → blocks the destroy). Scoped twice: SG in this
# VPC *and* tagged elbv2.k8s.aws/cluster=<cluster>; never the default SG, never non-LBC/tofu SGs.
# Retries (3 rounds) because deleting one SG can be blocked until another SG referencing it is gone.
sweep_cluster_sgs() {
  [ -n "${VPC_ID:-}" ] || return 0
  for round in 1 2 3; do
    local remaining=0
    for sg in $(aws ec2 describe-security-groups --region "$REGION" \
        --filters Name=vpc-id,Values="$VPC_ID" "Name=tag:elbv2.k8s.aws/cluster,Values=$CLUSTER" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null); do
      echo "  [round $round] deleting orphaned LBC security group $sg"
      aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null || true
      remaining=1
    done
    # nothing left to delete → done; else wait for cross-referencing SGs to clear, then retry
    [ "$remaining" = 0 ] && break
    sleep 10
  done
}

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
# Safety net: whatever the controller did NOT delete (e.g. it was already down), kill directly by tag.
echo "== kill any remaining LBC load balancers directly (controller-independent) =="
kill_cluster_lbs

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
  # VPC layer: LBs/endpoints that didn't delete leave ENIs → DependencyViolation. Kill any LBs still
  # up, sweep their now-detached ENIs (retry loop), retry the destroy, then release orphaned NAT EIPs.
  if [ "$d" = "00-infra/00-network/" ]; then
    kill_cluster_lbs
    sweep_enis
    sweep_cluster_sgs   # after ENIs: an SG only deletes once nothing references it
    ( cd "$d" && tofu destroy -auto-approve 2>/dev/null ) || true
    release_cluster_eips
  fi
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
echo "Auto-handled: LBC load balancers + security groups killed by tag, orphaned ENIs swept (retry loop), NAT EIPs released."
echo "If 00-network STILL fails (DependencyViolation), an ENI is likely in-use (slow detach) — wait a"
echo "minute and just re-run teardown (safe to repeat), or inspect:"
echo "  VPC=${VPC_ID:-<vpc-id>}; aws ec2 describe-network-interfaces --region $REGION --filters Name=vpc-id,Values=\$VPC \\"
echo "    --query 'NetworkInterfaces[].[NetworkInterfaceId,Status,InterfaceType,Description]' --output table"
