# ICMP across the link (both the 10/8 cloud side and the 192.168/16 on-prem side), so the test hosts
# can ping each other once the data path (VPN transport stand-in) is up. SSM itself needs no inbound
# rule (outbound only).
resource "aws_security_group" "this" {
  for_each = local.vpcs
  name     = "net-lab-dx-${each.key}"
  vpc_id   = aws_vpc.this[each.key].id

  ingress {
    description = "ICMP from the cloud side (10/8)"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = ["10.0.0.0/8"]
  }
  ingress {
    description = "ICMP from the on-prem side (192.168/16)"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = ["192.168.0.0/16"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-dx-${each.key}" }
}

# Dedicated SG for the strongSwan appliance (the on-prem router / VPN transport stand-in). It must
# accept the IPsec control/data plane FROM AWS's two public tunnel endpoints. We don't know those IPs
# until 4-vpn creates the aws_vpn_connection, so here we open the IPsec ports to the internet
# (lab-grade) and additionally allow ICMP from both sides. Tighten to the two tunnel outside IPs for
# anything beyond a lab.
resource "aws_security_group" "strongswan" {
  name        = "net-lab-dx-strongswan"
  description = "strongSwan on-prem router - IPsec (IKE/NAT-T/ESP) + ICMP (VPN transport stand-in)"
  vpc_id      = aws_vpc.this["onprem"].id

  ingress {
    description = "IKE (ISAKMP)"
    protocol    = "udp"
    from_port   = 500
    to_port     = 500
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "IPsec NAT-T"
    protocol    = "udp"
    from_port   = 4500
    to_port     = 4500
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ESP (IPsec payload)"
    protocol    = "50"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  # ICMP so the appliance itself is pingable and can forward ping across the link.
  ingress {
    description = "ICMP from the cloud side (10/8)"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = ["10.0.0.0/8"]
  }
  ingress {
    description = "ICMP from the on-prem side (192.168/16)"
    protocol    = "icmp"
    from_port   = -1
    to_port     = -1
    cidr_blocks = ["192.168.0.0/16"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "net-lab-dx-strongswan" }
}
