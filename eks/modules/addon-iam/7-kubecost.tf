# Kubecost role — read Cost Explorer / pricing for accurate cost allocation.
# Granted via Pod Identity to the cost-analyzer SA.
resource "aws_iam_role" "kubecost" {
  name = "${var.cluster_name}-kubecost"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "kubecost" {
  name = "cost-read"
  role = aws_iam_role.kubecost.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ce:GetCostAndUsage",
        "ce:GetDimensionValues",
        "ce:GetTags",
        "pricing:GetProducts",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "kubecost" {
  cluster_name    = var.cluster_name
  namespace       = "kubecost"
  service_account = "kubecost-cost-analyzer"
  role_arn        = aws_iam_role.kubecost.arn
}

output "kubecost_role_arn" {
  value = aws_iam_role.kubecost.arn
}
