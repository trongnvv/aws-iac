# ── NAT in the shared VPC (public subnet) ────────────────────────────────────
resource "aws_eip" "nat" {
  count  = local.on ? 1 : 0
  domain = "vpc"
  tags   = { Name = "net-lab-egress" }
}

resource "aws_nat_gateway" "this" {
  count         = local.on ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = local.shared_public_sub
  tags          = { Name = "net-lab-egress" }
}

# Return path: traffic arriving from spokes at the shared TGW-attachment subnet → NAT.
resource "aws_route" "shared_tgw_to_nat" {
  count                  = local.on ? 1 : 0
  route_table_id         = local.shared_tgw_rt
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

# TGW spoke route table: default route → shared attachment (so spokes send 0/0 to the hub).
resource "aws_ec2_transit_gateway_route" "spoke_default" {
  count                          = local.on ? 1 : 0
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = local.shared_attach
  transit_gateway_route_table_id = local.spoke_tgw_rt
}
