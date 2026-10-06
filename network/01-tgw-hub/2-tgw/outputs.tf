output "tgw_id" { value = aws_ec2_transit_gateway.this.id }
output "spoke_route_table_id" { value = aws_ec2_transit_gateway_route_table.spoke.id }
output "shared_attachment_id" { value = aws_ec2_transit_gateway_vpc_attachment.this["shared"].id }
