# TGW hub. Default route-table assoc/propagation OFF → two custom RTs segment:
#   shared RT learns prod+dev (shared reaches both) · spoke RT learns shared only (prod ⊥ dev).
resource "aws_ec2_transit_gateway" "this" {
  description                     = "net-lab hub"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags                            = { Name = "net-lab" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each                                        = local.vpc_ids
  transit_gateway_id                              = aws_ec2_transit_gateway.this.id
  vpc_id                                          = each.value
  subnet_ids                                      = [local.attach_subnet[each.key]]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = { Name = "net-lab-${each.key}" }
}

resource "aws_ec2_transit_gateway_route_table" "shared" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "net-lab-shared" }
}
resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "net-lab-spoke" }
}

# Associations
resource "aws_ec2_transit_gateway_route_table_association" "shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["shared"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}
resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  for_each                       = toset(["prod", "dev"])
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Propagations
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_learns_spokes" {
  for_each                       = toset(["prod", "dev"])
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared.id
}
resource "aws_ec2_transit_gateway_route_table_propagation" "spokes_learn_shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["shared"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Cross-VPC route added to each VPC's route table (created in 1-vpc): 10/8 → TGW.
resource "aws_route" "tgw" {
  for_each               = local.rt_ids
  route_table_id         = each.value
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.this]
}
