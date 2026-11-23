output "peering_enabled" { value = local.on }
output "region2_tgw_id" { value = local.on ? aws_ec2_transit_gateway.region2[0].id : null }
output "peering_attachment_id" { value = local.on ? aws_ec2_transit_gateway_peering_attachment.this[0].id : null }
output "region2_test_instance" {
  value = local.on ? { id = aws_instance.region2_test[0].id, private_ip = aws_instance.region2_test[0].private_ip } : null
}
