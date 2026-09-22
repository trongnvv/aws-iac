#!/usr/bin/env bash
# Large (prod/regulated): full security baseline, private endpoint, pod-ENI,
# per-AZ NAT, AMP, WAF, egress firewall, delivery, cost, API gateway, mesh, Falco.
# Requires: ACME_EMAIL, DOMAIN_FILTER.
set -euo pipefail
cd "$(dirname "$0")/.."
REGION=ap-southeast-1
: "${ACME_EMAIL:?export ACME_EMAIL=you@example.com before running}"
: "${DOMAIN_FILTER:?export DOMAIN_FILTER=example.com before running}"

echo "== remote state =="
(cd bootstrap/00-tf-backend && tofu init -input=false && tofu apply -auto-approve)

echo "== tfvars (large) =="
cat > layer0-provisioning/00-network/terraform.tfvars <<'EOF'
nat_per_az            = true
enable_secondary_cidr = true
EOF
cat > layer0-provisioning/01-eks/terraform.tfvars <<'EOF'
enable_control_plane_logging   = true
enable_secret_encryption       = true
cluster_endpoint_public_access = false
enable_pod_eni                 = true
enable_network_policy          = true
enable_efs_csi                 = true
EOF
cat > layer0-provisioning/06-security-baseline/terraform.tfvars <<'EOF'
enable_guardduty   = true
enable_cloudtrail  = true
enable_config      = true
enable_securityhub = true
EOF
echo 'enable_enhanced_scan    = true' > layer0-provisioning/05-ecr/terraform.tfvars
echo 'enable_amp              = true' > layer0-provisioning/07-observability-aws/terraform.tfvars
echo 'enable_backup           = true' > layer0-provisioning/08-backup-aws/terraform.tfvars
echo 'enable_waf              = true' > layer0-provisioning/09-waf/terraform.tfvars
echo 'enable_network_firewall = true' > layer0-provisioning/10-network-firewall/terraform.tfvars

echo "== layer0 =="
for d in 00-network 01-eks 02-node-group 03-karpenter-infra 04-addon-iam 05-ecr \
         06-security-baseline 07-observability-aws 08-backup-aws 09-waf 10-network-firewall; do
  (cd "layer0-provisioning/$d" && tofu init -input=false && tofu apply -auto-approve)
done
echo "!! wire app route tables through the firewall endpoints (env-specific) — see 10-network-firewall"

echo "== wire cluster + env =="
export AWS_REGION=$REGION
export CLUSTER_NAME=$(cd layer0-provisioning/01-eks && tofu output -raw cluster_name)
export VPC_ID=$(cd layer0-provisioning/00-network && tofu output -raw vpc_id)
export KARPENTER_QUEUE_NAME=$(cd layer0-provisioning/03-karpenter-infra && tofu output -raw karpenter_queue_name)
export KARPENTER_NODE_ROLE=$(cd layer0-provisioning/03-karpenter-infra && tofu output -raw karpenter_node_iam_role_name)
export BACKUP_BUCKET=$(cd layer0-provisioning/08-backup-aws && tofu output -raw velero_bucket)
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
export DNS_CLUSTER_IP=$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}')

echo "== layer1 (07-network-policy is manifests) =="
for d in 00-karpenter 01-metrics-server 02-aws-load-balancer-controller 03-external-dns \
         04-cert-manager 05-external-secrets 06-kyverno 08-keda 09-dns-scale; do
  (cd "layer1-addons/$d" && helmfile apply)
done
kubectl apply -f layer1-addons/07-network-policy/manifests.yaml

echo "== layer2 =="
for d in 00-argocd 01-observability 02-velero 03-argo-rollouts 04-kubecost \
         05-api-gateway 06-service-mesh 07-falco; do
  (cd "layer2-platform/$d" && helmfile apply)
done

echo "== done: large =="
