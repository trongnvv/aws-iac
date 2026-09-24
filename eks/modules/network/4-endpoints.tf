# S3 gateway endpoint (free): S3 / ECR-layer traffic skips NAT.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    aws_route_table.app[*].id,
    [aws_route_table.isolated.id]
  )
}

resource "aws_security_group" "vpce" {
  name   = "${var.cluster_name}-vpce-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

# Interface endpoints: billed per AZ but cheaper than NAT per-GB for image pulls.
# private_dns keeps the normal AWS hostnames resolving to these private ENIs.
resource "aws_vpc_endpoint" "interface" {
  for_each = toset([
    "com.amazonaws.${var.region}.ecr.api",
    "com.amazonaws.${var.region}.ecr.dkr",
    "com.amazonaws.${var.region}.secretsmanager",
  ])
  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true
}
