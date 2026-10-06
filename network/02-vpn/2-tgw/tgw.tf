# TGW that terminates the Site-to-Site VPN. Unlike lab 1 (which disabled the default RT to segment),
# this lab has just two attachments — the aws VPC and (added in 3-vpn) the VPN — that must reach each
# other, so we keep ONE custom route table and associate/propagate both into it:
#   - the VPC attachment propagates 10.10.0.0/16  → advertised to on-prem over BGP.
#   - the VPN attachment propagates 192.168.0.0/16 (BGP-learned from FRR) → the aws VPC reaches on-prem.
# Default assoc/propagation is disabled so we wire it explicitly (and 3-vpn's VPN attachment joins the
# same RT). amazon_side_asn is what the on-prem FRR peers against.
resource "aws_ec2_transit_gateway" "this" {
  description                     = "net-lab-vpn hub"
  amazon_side_asn                 = var.amazon_side_asn
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  # ECMP across the two VPN tunnels — a stretch item (load-balance over both tunnels). Harmless with
  # one tunnel pair; required to actually spread flows when both tunnels are UP.
  vpn_ecmp_support = "enable"
  tags             = { Name = "net-lab-vpn" }
}

# Single shared route table — both the VPC attachment and the VPN attachment (3-vpn) live here.
resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "net-lab-vpn-main" }
}

# ── aws VPC attachment ────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway_vpc_attachment" "aws" {
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = local.aws_vpc_id
  subnet_ids                                      = [local.aws_subnet_id]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = { Name = "net-lab-vpn-aws" }
}

resource "aws_ec2_transit_gateway_route_table_association" "aws" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.aws.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

# Propagate the aws VPC prefix (10.10/16) into the RT so the VPN attachment advertises it to on-prem.
resource "aws_ec2_transit_gateway_route_table_propagation" "aws" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.aws.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

# aws VPC → on-prem CIDR via the TGW. (Return path onprem → aws is handled on the onprem side in
# 4-strongswan by routing 10.10/16 to the strongSwan ENI.)
resource "aws_route" "aws_to_onprem" {
  route_table_id         = local.aws_rt_id
  destination_cidr_block = local.onprem_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.aws]
}
