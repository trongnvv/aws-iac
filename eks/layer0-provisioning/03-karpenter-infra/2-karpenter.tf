# AWS-side pieces only: node IAM role + instance profile, SQS interruption queue,
# and the Pod Identity association for the controller. The controller Helm chart
# and the NodePool/EC2NodeClass live in layer1/00-karpenter.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name                    = local.cluster_name
  enable_pod_identity             = true
  create_pod_identity_association = true
  node_iam_role_use_name_prefix   = false # stable name: Karpenter-<cluster>, referenced by EC2NodeClass

  tags = {
    ManagedBy = "opentofu"
    Cluster   = local.cluster_name
  }
}

output "karpenter_queue_name" {
  value = module.karpenter.queue_name
}

output "karpenter_node_iam_role_name" {
  value = module.karpenter.node_iam_role_name
}
