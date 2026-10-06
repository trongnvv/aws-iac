output "vpc_ids" { value = { for k, v in aws_vpc.this : k => v.id } }
output "subnet_ids" { value = { for k, s in aws_subnet.this : k => s.id } }
output "vpc_cidrs" { value = local.vpcs }
output "provider_svc_sg_id" { value = aws_security_group.provider_svc.id }
output "consumer_host_sg_id" { value = aws_security_group.consumer_host.id }
