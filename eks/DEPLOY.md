# Deploy

Copy-paste scripts. Run from the repo root (`aws-iac/eks/`). Needs `tofu` + `helmfile`.
What each size *builds* is decided by `enable_*` in each folder's `terraform.tfvars`
(see `ENV-MAP.md`); the loops below just apply/skip folders.

## 0. Prerequisites
```bash
tofu version && helmfile version && aws sts get-caller-identity
```

## 1. Remote state (once)
```bash
(cd bootstrap/00-tf-backend && tofu init && tofu apply -auto-approve)
```

## 2. Layer 0 — AWS resources
```bash
LAYER0="00-network 01-eks 02-node-group 03-karpenter-infra 04-addon-iam \
        05-ecr 06-security-baseline 07-observability-aws 08-backup-aws 09-waf 10-network-firewall"
for d in $LAYER0; do
  (cd layer0-provisioning/$d && tofu init && tofu apply -auto-approve)
done
```

## 3. Kubeconfig + env
```bash
CLUSTER=$(cd layer0-provisioning/01-eks && tofu output -raw cluster_name)
aws eks update-kubeconfig --name "$CLUSTER" --region ap-southeast-1
cp env.sh.example env.sh && "$EDITOR" env.sh && source env.sh
```

## 4. Layer 1 + Layer 2 — Helm. Build the folder list for your size, then apply.
```bash
# --- Small (dev/lab) ---
L1="00-karpenter 01-metrics-server 02-aws-load-balancer-controller 04-cert-manager 05-external-secrets"
L2="00-argocd 01-observability"

# --- Medium: run the Small line above, then append these ---
L1="$L1 03-external-dns 06-kyverno 08-keda"
L2="$L2 02-velero"

# --- Large: run Small + Medium above, then append these ---
L1="$L1 07-network-policy 09-dns-scale"
L2="$L2 03-argo-rollouts 04-kubecost 05-api-gateway 06-service-mesh 07-falco"

# Apply (07-network-policy is plain manifests, the rest are helmfile)
for d in $L1; do
  if [ -f "layer1-addons/$d/helmfile.yaml" ]; then (cd "layer1-addons/$d" && helmfile apply)
  else kubectl apply -f "layer1-addons/$d/manifests.yaml"; fi
done
for d in $L2; do (cd "layer2-platform/$d" && helmfile apply); done
```

## Teardown (reverse order)
```bash
for d in $(echo "$L2" | tr ' ' '\n' | tail -r); do (cd "layer2-platform/$d" && helmfile destroy); done
for d in $(echo "$L1" | tr ' ' '\n' | tail -r); do
  [ -f "layer1-addons/$d/helmfile.yaml" ] && (cd "layer1-addons/$d" && helmfile destroy)
done
# Delete Ingress/Service first so the LB Controller removes ALBs/ENIs, else the
# VPC destroy hangs on orphaned network interfaces.
for d in $(echo "$LAYER0" | tr ' ' '\n' | tail -r); do (cd "layer0-provisioning/$d" && tofu destroy -auto-approve); done
```
