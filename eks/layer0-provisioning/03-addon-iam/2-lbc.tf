# AWS Load Balancer Controller role, granted via EKS Pod Identity to the
# aws-load-balancer-controller ServiceAccount in kube-system.
data "http" "lbc_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${var.lbc_policy_version}/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "lbc" {
  name   = "${local.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  policy = data.http.lbc_policy.response_body
}

resource "aws_iam_role" "lbc" {
  name = "${local.cluster_name}-lbc"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# namespace + service_account must match the Helm release (layer1/02).
resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = local.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}

output "lbc_role_arn" {
  value = aws_iam_role.lbc.arn
}
