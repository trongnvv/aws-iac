# Consumed by 01-eks via terraform_remote_state.
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "isolated_subnet_ids" {
  value = aws_subnet.isolated[*].id
}

# Fixed egress IPs (NAT EIPs) — give these to partners/exchanges for source-IP allowlisting.
output "nat_public_ips" {
  value = aws_eip.nat[*].public_ip
}
