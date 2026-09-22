# EKS on AWS — layered IaC

A hands-on, production-shaped EKS build split into layers. `ap-southeast-1`,
OpenTofu for AWS resources, Helmfile for Kubernetes add-ons.

## Layers

| Layer | Tool | What |
|---|---|---|
| `layer0-provisioning/` | OpenTofu | AWS resources: VPC, EKS cluster, node group, Karpenter infra, add-on IAM |
| `layer1-addons/` | Helmfile | Kubernetes add-ons, one subfolder per add-on |
| `layer2-platform/` | Helmfile | Platform layer (ArgoCD, observability, sample app) — added later |

Each subfolder is numbered by apply order.

## Apply order

```
# Layer 0 (each folder has its own state; later folders read earlier ones via remote_state)
cd layer0-provisioning/00-network        && tofu init && tofu apply
cd layer0-provisioning/01-eks            && tofu init && tofu apply
cd layer0-provisioning/02-node-group     && tofu init && tofu apply
cd layer0-provisioning/03-karpenter-infra && tofu init && tofu apply
cd layer0-provisioning/04-addon-iam      && tofu init && tofu apply

# Wire kubeconfig + export layer0 outputs for Helmfile
aws eks update-kubeconfig --name <cluster> --region ap-southeast-1
source ./env.sh   # cluster_name / region / role ARNs consumed by layer1

# Layer 1 (dependency-ordered)
cd layer1-addons/00-karpenter                    && helmfile apply
cd layer1-addons/01-metrics-server               && helmfile apply
cd layer1-addons/02-aws-load-balancer-controller && helmfile apply
cd layer1-addons/03-external-dns                 && helmfile apply
cd layer1-addons/04-cert-manager                 && helmfile apply
cd layer1-addons/05-external-secrets             && helmfile apply
```

## Conventions

- IaC = OpenTofu (`tofu`, not `terraform`). AWS provider uses `profile = "default"`.
- Managed EKS add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI, Pod Identity) live in
  `01-eks` (AWS lifecycle). Everything else is Helm in layer1. One owner per component.
- Cost discipline: this is a lab. `tofu destroy` in reverse order when done.

## Teardown

Reverse order: `layer1` (helmfile destroy) → `layer0` `04 → 00`.
Watch for orphaned ALBs/ENIs from the LB Controller — delete Kubernetes
Ingress/Service before destroying the VPC or it will block deletion.
