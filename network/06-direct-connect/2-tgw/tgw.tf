# TGW that both the DX Gateway (3-dxgw, the DX-as-code control plane) and the Site-to-Site VPN
# (4-vpn, the transport stand-in for the physical Transit VIF) attach to. Three attachments end up on
# ONE custom route table so they reach each other:
#   - the aws VPC attachment propagates 10.30.0.0/16  → the cloud prefix, advertised toward on-prem.
#   - the VPN attachment propagates 192.168.30.0/16 (BGP-learned from FRR) → the aws VPC reaches on-prem.
#   - the DX Gateway association is wired with allowed_prefixes = [onprem CIDR] (3-dxgw) — this is what a
#     real Transit VIF would plug into; in a live DX the on-prem prefix would arrive via BGP over the VIF.
# Default assoc/propagation is disabled so we wire everything explicitly. amazon_side_asn is what the
# on-prem FRR peers against over the VPN stand-in.
resource "aws_ec2_transit_gateway" "this" {
  description                     = "net-lab-dx hub"
  amazon_side_asn                 = var.amazon_side_asn
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  # ECMP across the two VPN tunnels — a stretch item (load-balance over both tunnels). Harmless with
  # one tunnel pair; required to actually spread flows when both tunnels are UP.
  vpn_ecmp_support = "enable"
  tags             = { Name = "net-lab-dx" }
}

# Single shared route table — the VPC attachment, the VPN attachment (4-vpn) and the DX Gateway
# association (3-dxgw) all live here.
resource "aws_ec2_transit_gateway_route_table" "main" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "net-lab-dx-main" }
}

# ── aws VPC attachment ────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway_vpc_attachment" "aws" {
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = local.aws_vpc_id
  subnet_ids                                      = [local.aws_subnet_id]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = { Name = "net-lab-dx-aws" }
}

resource "aws_ec2_transit_gateway_route_table_association" "aws" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.aws.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

# Propagate the aws VPC prefix (10.30/16) into the RT so it is advertised to on-prem (over the DX
# Gateway association in a real DX, and over the VPN stand-in here).
resource "aws_ec2_transit_gateway_route_table_propagation" "aws" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.aws.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.main.id
}

# aws VPC → on-prem CIDR via the TGW. (Return path onprem → aws is handled on the onprem side in
# 5-strongswan by routing 10.30/16 to the strongSwan ENI.)
resource "aws_route" "aws_to_onprem" {
  route_table_id         = local.aws_rt_id
  destination_cidr_block = local.onprem_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.aws]
}
