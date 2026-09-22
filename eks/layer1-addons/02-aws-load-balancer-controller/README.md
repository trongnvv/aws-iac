# 02-aws-load-balancer-controller

AWS Load Balancer Controller — provisions ALB (L7) / NLB (L4) from Ingress/Service.
Uses the IAM role from `layer0/04-addon-iam`. Target-type `ip` (works with VPC CNI).

**Installs:** `helmfile.yaml` (aws-load-balancer-controller chart).
Needs subnet tags from `00-network` (`kubernetes.io/role/elb`).
