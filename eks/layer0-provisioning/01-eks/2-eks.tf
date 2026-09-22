locals {
  vpc_cni_env = merge(
    var.enable_prefix_delegation ? { ENABLE_PREFIX_DELEGATION = "true", WARM_PREFIX_TARGET = "1" } : {},
    var.enable_pod_eni ? { ENABLE_POD_ENI = "true" } : {},
  )
}

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

  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  # Access Entries (API), not the aws-auth ConfigMap; applying identity gets admin.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # P0 toggles (env-driven).
  cluster_enabled_log_types = var.enable_control_plane_logging ? var.control_plane_log_types : []

  create_kms_key            = var.enable_secret_encryption
  cluster_encryption_config = var.enable_secret_encryption ? { resources = ["secrets"] } : {}

  cluster_addons = merge(
    {
      coredns    = {}
      kube-proxy = {}
      vpc-cni = {
        before_compute = true # create before nodes so the first pods get IPs
        configuration_values = jsonencode({
          enableNetworkPolicy = var.enable_network_policy ? "true" : "false"
          env                 = local.vpc_cni_env
        })
      }
      eks-pod-identity-agent = {}
    },
    var.enable_efs_csi ? { aws-efs-csi-driver = {} } : {},
  )

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

  # Tag the node SG so Karpenter's EC2NodeClass can discover it by tag.
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = {
    ManagedBy = "opentofu"
    Cluster   = var.cluster_name
  }
}
