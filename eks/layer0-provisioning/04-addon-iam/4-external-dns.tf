# ExternalDNS role (Route 53), granted via EKS Pod Identity to SA external-dns.
resource "aws_iam_role" "external_dns" {
  name = "${local.cluster_name}-external-dns"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "external_dns" {
  name = "route53"
  role = aws_iam_role.external_dns.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = local.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}
