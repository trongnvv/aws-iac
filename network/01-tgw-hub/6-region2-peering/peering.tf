# The core lesson of this layer: a TGW Peering attachment does NOT propagate routes — every route
# below is static, added by hand, on BOTH sides. Compare with 2-tgw's VPC attachments, which use
# propagation (`aws_ec2_transit_gateway_route_table_propagation`) — peering never gets that.

# Requester: created against the HOME region's TGW/provider, naming the peer TGW + its region.
resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  count                   = local.on ? 1 : 0
  transit_gateway_id      = local.home_tgw_id
  peer_transit_gateway_id = aws_ec2_transit_gateway.region2[0].id
  peer_region             = var.region2
  tags                    = { Name = "net-lab-region-peering" }
}

# Accepter: created against the PEER region's provider — same-account peering still needs an
# explicit accept, it's just not a separate AWS account approving it.
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  count                         = local.on ? 1 : 0
  provider                      = aws.region2
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.this[0].id
  tags                          = { Name = "net-lab-region-peering" }
}

# ── Home side: associate the peering attachment to Lab 1's existing "shared" TGW route table,
# then add ONE static route for region2's CIDR. Nothing else in Lab 1 changes.
resource "aws_ec2_transit_gateway_route_table_association" "home_peering" {
  count                          = local.on ? 1 : 0
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this[0].id
  transit_gateway_route_table_id = local.home_shared_rt_id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.this]
}

resource "aws_ec2_transit_gateway_route" "home_to_region2" {
  count                          = local.on ? 1 : 0
  destination_cidr_block         = var.region2_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this[0].id
  transit_gateway_route_table_id = local.home_shared_rt_id
  depends_on                     = [aws_ec2_transit_gateway_route_table_association.home_peering]
}

# ── Region2 side: associate the peering attachment to region2's own TGW route table, then add
# the one static route back to the home region's shared VPC.
resource "aws_ec2_transit_gateway_route_table_association" "region2_peering" {
  count                          = local.on ? 1 : 0
  provider                       = aws.region2
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.this[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.region2[0].id
}

resource "aws_ec2_transit_gateway_route" "region2_to_home" {
  count                          = local.on ? 1 : 0
  provider                       = aws.region2
  destination_cidr_block         = local.home_shared_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.this[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.region2[0].id
  depends_on                     = [aws_ec2_transit_gateway_route_table_association.region2_peering]
}
