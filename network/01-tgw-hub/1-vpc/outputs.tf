output "vpc_ids" { value = { for k, v in aws_vpc.this : k => v.id } }
output "subnet_ids" { value = { for k, s in aws_subnet.this : k => s.id } }
output "sg_ids" { value = { for k, s in aws_security_group.this : k => s.id } }
output "route_table_ids" { value = { for k, r in aws_route_table.this : k => r.id } }
output "vpc_cidrs" { value = local.vpcs }
output "shared_tgw_subnet_id" { value = aws_subnet.shared_tgw.id }
output "shared_tgw_route_table_id" { value = aws_route_table.shared_tgw.id }
