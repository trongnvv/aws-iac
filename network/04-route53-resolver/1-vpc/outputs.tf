output "vpc_ids" { value = { for k, v in aws_vpc.this : k => v.id } }
output "vpc_cidrs" { value = local.vpcs }
output "sg_ids" { value = { for k, s in aws_security_group.this : k => s.id } }

# AWS side: both subnet IDs (resolver endpoints span the 2 AZs).
output "aws_subnet_ids" { value = { for k, s in aws_subnet.aws : k => s.id } }
output "aws_cidr" { value = local.aws_cidr }

# On-prem side: the single subnet (DNS server + test host live here).
output "onprem_subnet_id" { value = aws_subnet.onprem.id }
output "onprem_cidr" { value = local.onprem_cidr }
