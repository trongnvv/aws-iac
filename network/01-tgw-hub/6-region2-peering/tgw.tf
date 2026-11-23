resource "aws_ec2_transit_gateway" "region2" {
  count                           = local.on ? 1 : 0
  provider                        = aws.region2
  description                     = "net-lab region2"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags                            = { Name = "net-lab-region2" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "region2" {
  count                                           = local.on ? 1 : 0
  provider                                        = aws.region2
  transit_gateway_id                              = aws_ec2_transit_gateway.region2[0].id
  vpc_id                                          = aws_vpc.region2[0].id
  subnet_ids                                      = [aws_subnet.region2[0].id]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = { Name = "net-lab-region2" }
}

# Single flat route table — this layer proves peering + static routing, not segmentation.
resource "aws_ec2_transit_gateway_route_table" "region2" {
  count              = local.on ? 1 : 0
  provider           = aws.region2
  transit_gateway_id = aws_ec2_transit_gateway.region2[0].id
  tags               = { Name = "net-lab-region2" }
}

resource "aws_ec2_transit_gateway_route_table_association" "region2_vpc" {
  count                          = local.on ? 1 : 0
  provider                       = aws.region2
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.region2[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.region2[0].id
}
