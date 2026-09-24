# Walkthrough — bring up `dev` by hand

The small steps that `scripts/deploy.sh dev` runs, spelled out. In this repo each
env is a set of **per-layer roots** under `envs/dev/` that call `modules/*`; every
root has a concrete S3 backend, so `tofu init` just works (no `-backend-config`).
`dev` = small preset: public API, single NAT, nothing paid. Run from the `eks/` root.

## 0. Prerequisites (once)
```bash
tofu version && helmfile version && aws sts get-caller-identity   # tools + creds
(cd ../foundation && ./apply.sh)                                  # S3 state backend + Route 53 zone
```

## 1. Load the env context (helmfile vars only)
```bash
source envs/dev/config.env          # ACME_EMAIL, L1/L2 add-on lists
```

## 2. Layer0 — apply each root
Layer0 values (cluster_name, CIDR, toggles) live inside each root's `main.tf`.
Review the plan before `yes` (drop `-auto-approve` to stay in control).

### 2.1 Network
```bash
( cd envs/dev/00-network && tofu init && tofu apply )
```

### 2.2 EKS cluster (~15–20 min)
```bash
( cd envs/dev/01-eks && tofu init && tofu apply )
```

### 2.3–2.5 Karpenter infra · add-on IAM · ECR
```bash
for d in 02-karpenter-infra 03-addon-iam 04-ecr; do
  ( cd "envs/dev/$d" && tofu init && tofu apply -auto-approve )
done
```

### 2.6 Security / observability / backup / WAF (05–08)
Apply them too (they read state cleanly); at dev toggles they create **nothing**
(prod turns them on). Or skip to save a few `init`s:
```bash
for d in 05-security-baseline 06-observability-aws 07-backup-aws 08-waf; do
  ( cd "envs/dev/$d" && tofu init && tofu apply -auto-approve )
done
```

## 3. Wire kubeconfig
```bash
CLUSTER=$(cd envs/dev/01-eks && tofu output -raw cluster_name)   # eks-dev
aws eks update-kubeconfig --name "$CLUSTER" --region ap-southeast-1
kubectl get nodes        # the 2 system nodes should be Ready
```

## 4. Export the values Helm needs (from root outputs)
```bash
export AWS_REGION=ap-southeast-1
export CLUSTER_NAME="$CLUSTER"
export VPC_ID=$(cd envs/dev/00-network && tofu output -raw vpc_id)
export KARPENTER_QUEUE_NAME=$(cd envs/dev/02-karpenter-infra && tofu output -raw karpenter_queue_name)
export KARPENTER_NODE_ROLE=$(cd envs/dev/02-karpenter-infra && tofu output -raw karpenter_node_iam_role_name)
# ACME_EMAIL already came from envs/dev/config.env
```

## 5. Layer1 add-ons (dev list)
```bash
for d in 00-karpenter 01-metrics-server 02-aws-load-balancer-controller 04-cert-manager 05-external-secrets; do
  ( cd "layer1-addons/$d" && helmfile apply )
done
```
```bash
kubectl -n kube-system get pods | grep -E 'karpenter|aws-load-balancer|metrics-server'
kubectl get nodepool,ec2nodeclass
kubectl -n cert-manager get pods
kubectl -n external-secrets get pods
```

## 6. Layer2 (dev: GitOps + dashboards)
```bash
( cd layer2-platform/00-argocd && helmfile apply )
( cd layer2-platform/01-observability && helmfile apply )
kubectl -n argocd get pods
kubectl -n monitoring get pods
```

## 7. Smoke test
```bash
kubectl get nodes
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

## 8. Teardown (reverse)
```bash
( cd layer2-platform/01-observability && helmfile destroy )
( cd layer2-platform/00-argocd && helmfile destroy )
for d in 05-external-secrets 04-cert-manager 02-aws-load-balancer-controller 01-metrics-server 00-karpenter; do
  ( cd "layer1-addons/$d" && helmfile destroy )
done
for d in 08-waf 07-backup-aws 06-observability-aws 05-security-baseline 04-ecr 03-addon-iam 02-karpenter-infra 01-eks 00-network; do
  ( cd "envs/dev/$d" && tofu init && tofu destroy -auto-approve )
done
```

*(Automated equivalent: `./scripts/deploy.sh dev` / `./scripts/teardown.sh dev`.)*
