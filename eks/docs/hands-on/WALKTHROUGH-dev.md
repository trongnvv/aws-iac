# Walkthrough — bring up `dev` by hand

The small steps that `cd envs/dev && ./deploy.sh` runs, spelled out. In this repo each
env is a set of **per-layer roots** under `envs/dev/` that call `modules/*`; every
root has a concrete S3 backend, so `tofu init` just works (no `-backend-config`).
`dev` = small preset: public API, single NAT, nothing paid. Run from the `eks/` root.

## 0. Prerequisites (once)
```bash
tofu version && helmfile version && aws sts get-caller-identity   # tools + creds
(cd ../foundation && ./apply.sh)                                  # S3 state backend + Route 53 zone
```

## 1. Helm values are hardcoded per release (no env context to load)
There's no `config.env` to source anymore — each add-on/platform release keeps its
values as plain YAML next to it (e.g. the ACME email in
`envs/dev/01-addons/04-cert-manager/clusterissuer.yaml`, the domain filter in the
relevant `values.yaml` under `01-addons`/`02-platform`). Edit those files directly.

## 2. Infra — apply each root
Infra values (cluster_name, CIDR, toggles) live inside each root's `main.tf`.
Review the plan before `yes` (drop `-auto-approve` to stay in control).

### 2.1 Network
```bash
( cd envs/dev/00-infra/00-network && tofu init && tofu apply )
```

### 2.2 EKS cluster (~15–20 min)
```bash
( cd envs/dev/00-infra/01-eks && tofu init && tofu apply )
```

### 2.3–2.4 Karpenter infra · add-on IAM
(ECR is not part of the env infra — it's a shared repo created once by
`foundation/02-ecr` in step 0.)
```bash
for d in 02-karpenter-infra 03-addon-iam; do
  ( cd "envs/dev/00-infra/$d" && tofu init && tofu apply -auto-approve )
done
```

### 2.6 Security / observability / backup / WAF (04–07)
Apply them too (they read state cleanly); at dev toggles they create **nothing**
(prod turns them on). Or skip to save a few `init`s:
```bash
for d in 04-security-baseline 05-observability-aws 06-backup-aws 07-waf; do
  ( cd "envs/dev/00-infra/$d" && tofu init && tofu apply -auto-approve )
done
```

## 3. Wire kubeconfig
```bash
CLUSTER=$(cd envs/dev/00-infra/01-eks && tofu output -raw cluster_name)   # eks-dev
aws eks update-kubeconfig --name "$CLUSTER" --region ap-southeast-1
kubectl get nodes        # the 2 system nodes should be Ready
```

## 4. Helm values (hardcoded plain YAML, no tofu-output wiring)
Helm values are no longer wired from `tofu output`/env vars/`.gotmpl` — each release
keeps its values as plain YAML next to it (e.g. cluster name, VPC ID, Karpenter queue,
ACME email are written directly into the relevant `values.yaml` under
`01-addons`/`02-platform`, such as `envs/dev/01-addons/04-cert-manager/clusterissuer.yaml`).
If any value changed (new cluster name, VPC ID, Karpenter queue/role), edit those YAML
files first. You can still read the current infra outputs for reference:
```bash
(cd envs/dev/00-infra/00-network && tofu output -raw vpc_id)
(cd envs/dev/00-infra/02-karpenter-infra && tofu output -raw karpenter_queue_name)
(cd envs/dev/00-infra/02-karpenter-infra && tofu output -raw karpenter_node_iam_role_name)
```

## 5. Add-ons (dev list)
```bash
for d in 00-karpenter 01-metrics-server 02-aws-load-balancer-controller 04-cert-manager 05-external-secrets; do
  ( cd "envs/dev/01-addons/$d" && helmfile apply )
done
```
```bash
kubectl -n kube-system get pods | grep -E 'karpenter|aws-load-balancer|metrics-server'
kubectl get nodepool,ec2nodeclass
kubectl -n cert-manager get pods
kubectl -n external-secrets get pods
```

## 6. Platform (dev: GitOps + dashboards)
```bash
( cd envs/dev/02-platform/00-argocd && helmfile apply )
( cd envs/dev/02-platform/01-observability && helmfile apply )
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
( cd envs/dev/02-platform/01-observability && helmfile destroy )
( cd envs/dev/02-platform/00-argocd && helmfile destroy )
for d in 05-external-secrets 04-cert-manager 02-aws-load-balancer-controller 01-metrics-server 00-karpenter; do
  ( cd "envs/dev/01-addons/$d" && helmfile destroy )
done
for d in 07-waf 06-backup-aws 05-observability-aws 04-security-baseline 03-addon-iam 02-karpenter-infra 01-eks 00-network; do
  ( cd "envs/dev/00-infra/$d" && tofu init && tofu destroy -auto-approve )
done
```

*(Automated equivalent: `cd envs/dev && ./deploy.sh` / `cd envs/dev && ./teardown.sh`.)*
