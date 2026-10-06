locals {
  nat_count = var.nat_per_az ? length(var.azs) : 1
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  # Tagged so teardown can scope an orphaned-EIP release to THIS cluster's NAT EIPs only.
  tags = { Name = "${var.cluster_name}-nat" }
}

# NAT must sit in a public subnet to reach the IGW.
resource "aws_nat_gateway" "nat" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "nat-${var.azs[count.index]}" }
  depends_on    = [aws_internet_gateway.igw]
}
