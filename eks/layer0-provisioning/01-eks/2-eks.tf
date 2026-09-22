# Cluster + managed add-ons + bootstrap node group. Everything beyond the system
# pool is provisioned just-in-time by Karpenter (layer1/00).
# 💰 control plane ~$0.10/h + node group — destroy when done.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = local.vpc_id
  subnet_ids = local.app_subnet_ids

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Access Entries (API), not the aws-auth ConfigMap; applying identity gets admin.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true # create before nodes so the first pods get IPs
      configuration_values = jsonencode({
        env = var.enable_prefix_delegation ? {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        } : {}
      })
    }
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    system = {
      instance_types = var.system_instance_types
      ami_type       = var.system_ami_type
      capacity_type  = var.system_capacity_type
      min_size       = var.system_min_size
      max_size       = var.system_max_size
      desired_size   = var.system_desired_size
      labels         = { role = "system" }
    }
  }

  tags = {
    ManagedBy = "opentofu"
    Cluster   = var.cluster_name
  }
}
