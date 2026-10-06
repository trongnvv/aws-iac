# One SG per VPC. The DNS rules are the heart of the lab: allow port 53 (udp + tcp) between the two
# CIDRs so resolver endpoints and the on-prem dnsmasq can exchange queries. ICMP for ping sanity,
# egress-all for the SSM agent. No SSH inbound (Session Manager only).
resource "aws_security_group" "this" {
  for_each = local.vpcs
  name     = "net-lab-r53-${each.key}"
  vpc_id   = aws_vpc.this[each.key].id

  ingress {
    description = "DNS (UDP) from the other VPC"
    protocol    = "udp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [local.aws_cidr, local.onprem_cidr]
  }
  ingress {
    description = "DNS (TCP) from the other VPC - truncated/large answers fall back to TCP"
    protocol    = "tcp"
    from_port   = 53
    to_port     = 53
    cidr_blocks = [local.aws_cidr, local.onprem_cidr]
  }
  ingress {
    description = "ICMP from both VPCs (ping sanity)"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = [local.aws_cidr, local.onprem_cidr]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-r53-${each.key}" }
}
