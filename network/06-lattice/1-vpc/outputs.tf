output "vpc_ids" { value = { for k, v in aws_vpc.this : k => v.id } }
output "subnet_ids" { value = { for k, s in aws_subnet.this : k => s.id } }
output "sg_ids" { value = { for k, s in aws_security_group.this : k => s.id } }
output "vpc_cidrs" { value = local.vpcs }
