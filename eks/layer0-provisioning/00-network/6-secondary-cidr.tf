# Secondary VPC CIDR for pod IPs — use when the app subnets run dry. Pods then
# draw IPs from these subnets via VPC CNI custom networking (an ENIConfig CRD,
# applied in-cluster — not managed here). Gated; off by default.
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  count      = var.enable_secondary_cidr ? 1 : 0
  vpc_id     = aws_vpc.main.id
  cidr_block = var.secondary_cidr_block
}

resource "aws_subnet" "pod" {
  count             = var.enable_secondary_cidr ? length(var.azs) : 0
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.secondary_cidr_block, 2, count.index) # /18 per AZ
  availability_zone = var.azs[count.index]
  depends_on        = [aws_vpc_ipv4_cidr_block_association.secondary]
  tags = {
    Name                     = "pod-${var.azs[count.index]}"
    "karpenter.sh/discovery" = var.cluster_name
  }
}

resource "aws_route_table_association" "pod" {
  count          = var.enable_secondary_cidr ? length(var.azs) : 0
  subnet_id      = aws_subnet.pod[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

output "pod_subnet_ids" {
  value = aws_subnet.pod[*].id
}
