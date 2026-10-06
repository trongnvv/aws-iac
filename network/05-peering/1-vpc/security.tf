# ICMP from any lab VPC → lets us ping across the peering connections. SSM needs no inbound rule.
resource "aws_security_group" "this" {
  for_each = local.vpcs
  name     = "net-lab-peer-${each.key}"
  vpc_id   = aws_vpc.this[each.key].id

  ingress {
    description = "ICMP from lab VPCs"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-peer-${each.key}" }
}
