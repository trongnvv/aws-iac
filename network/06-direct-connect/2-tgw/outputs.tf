output "tgw_id" { value = aws_ec2_transit_gateway.this.id }
output "tgw_route_table_id" { value = aws_ec2_transit_gateway_route_table.main.id }
output "aws_attachment_id" { value = aws_ec2_transit_gateway_vpc_attachment.aws.id }
output "amazon_side_asn" { value = var.amazon_side_asn }
