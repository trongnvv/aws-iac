output "service_network_id" { value = aws_vpclattice_service_network.this.id }
output "service_network_arn" { value = aws_vpclattice_service_network.this.arn }
output "vpc_association_ids" {
  value = { for k, a in aws_vpclattice_service_network_vpc_association.this : k => a.id }
}
