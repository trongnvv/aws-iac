# Walkthrough — bring up `dev` by hand

The small steps that `scripts/deploy.sh dev` runs, spelled out so you can run/debug
each one manually. `dev` = small preset: public API, single NAT, nothing paid.
Run everything from the `eks/` root.

## 0. Prerequisites (once)
```bash
tofu version && helmfile version && aws sts get-caller-identity   # tools + creds
(cd ../foundation && ./apply.sh)                                  # S3 state backend + Route 53 zone
```

## 1. Load the env context
```bash
source envs/dev/config.env          # TF_VAR_env=dev, TF_VAR_cluster_name=eks-dev, ACME_EMAIL, L1/L2
BACKEND="$PWD/envs/dev/backend.hcl"  # bucket + lock + region
```

## 2. Layer0 — apply folder by folder
Each folder: `init` with a **dev-prefixed state key**, then `apply`. Review the plan
before typing `yes` (drop `-auto-approve` to stay in control).

### 2.1 Network (VPC, subnets, NAT, endpoints)
```bash
cd layer0-provisioning/00-network
tofu init -reconfigure -backend-config="$BACKEND" -backend-config="key=dev/layer0/00-network/terraform.tfstate"
tofu apply
cd ../..
```

### 2.2 EKS cluster (~15–20 min)
```bash
cd layer0-provisioning/01-eks
tofu init -reconfigure -backend-config="$BACKEND" -backend-config="key=dev/layer0/01-eks/terraform.tfstate"
tofu apply
cd ../..
```

### 2.3–2.5 Karpenter infra · add-on IAM · ECR
Same pattern — only the folder name + key change:
```bash
for d in 02-karpenter-infra 03-addon-iam 04-ecr; do
  ( cd "layer0-provisioning/$d" \
    && tofu init -reconfigure -backend-config="$BACKEND" -backend-config="key=dev/layer0/$d/terraform.tfstate" \
    && tofu apply -auto-approve )
done
```

### 2.6 Security / observability / backup / WAF (05–08)
**No-ops for dev** — their `enable_*` toggles are off, so they create nothing. Skip
them, or run the same pattern if you want the empty state files. (prod turns these on.)

## 3. Wire kubeconfig
```bash
CLUSTER=$(cd layer0-provisioning/01-eks && tofu output -raw cluster_name)   # eks-dev
aws eks update-kubeconfig --name "$CLUSTER" --region ap-southeast-1
kubectl get nodes        # the 2 system nodes should be Ready
```

## 4. Export the values Helm needs (derived from tofu outputs)
```bash
export AWS_REGION=ap-southeast-1
export CLUSTER_NAME="$CLUSTER"
export VPC_ID=$(cd layer0-provisioning/00-network && tofu output -raw vpc_id)
export KARPENTER_QUEUE_NAME=$(cd layer0-provisioning/02-karpenter-infra && tofu output -raw karpenter_queue_name)
export KARPENTER_NODE_ROLE=$(cd layer0-provisioning/02-karpenter-infra && tofu output -raw karpenter_node_iam_role_name)
# ACME_EMAIL already came from envs/dev/config.env
```

## 5. Layer1 add-ons (dev list)
```bash
for d in 00-karpenter 01-metrics-server 02-aws-load-balancer-controller 04-cert-manager 05-external-secrets; do
  ( cd "layer1-addons/$d" && helmfile apply )
done
```
Check as you go:
```bash
kubectl -n kube-system get pods | grep -E 'karpenter|aws-load-balancer|metrics-server'
kubectl get nodepool,ec2nodeclass          # Karpenter CRDs
kubectl -n cert-manager get pods
kubectl -n external-secrets get pods
```

## 6. Layer2 (dev: GitOps + dashboards)
```bash
( cd layer2-platform/00-argocd && helmfile apply )
( cd layer2-platform/01-observability && helmfile apply )
```
```bash
kubectl -n argocd get pods
kubectl -n monitoring get pods             # kube-prometheus-stack
```

## 7. Smoke test
```bash
kubectl get nodes
kubectl -n argocd port-forward svc/argocd-server 8080:443    # UI at https://localhost:8080
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80   # Grafana
```

## 8. Teardown (reverse)
```bash
( cd layer2-platform/01-observability && helmfile destroy )
( cd layer2-platform/00-argocd && helmfile destroy )
for d in 05-external-secrets 04-cert-manager 02-aws-load-balancer-controller 01-metrics-server 00-karpenter; do
  ( cd "layer1-addons/$d" && helmfile destroy )
done
for d in 04-ecr 03-addon-iam 02-karpenter-infra 01-eks 00-network; do
  ( cd "layer0-provisioning/$d" \
    && tofu init -reconfigure -backend-config="$BACKEND" -backend-config="key=dev/layer0/$d/terraform.tfstate" \
    && tofu destroy -auto-approve )
done
```
> Delete any app Ingress/Service before destroying `00-network` so the LB Controller
> removes the ALB/ENIs first, else the VPC destroy hangs.

*(The automated equivalent of all this is `./scripts/deploy.sh dev` / `./scripts/teardown.sh dev`.)*
