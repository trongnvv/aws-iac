# IAM for the EBS CSI driver managed add-on, via EKS Pod Identity.
# Gives dynamic block storage (gp3 PVCs). The gp3 default StorageClass itself is a
# k8s object applied post-cluster (ad-hoc/gp3-default-storageclass.yaml).
resource "aws_iam_role" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0
  name  = "${var.cluster_name}-ebs-csi"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = var.enable_ebs_csi ? 1 : 0
  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  count           = var.enable_ebs_csi ? 1 : 0
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi[0].arn
}
