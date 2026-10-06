# The DNS name the consumer curls. Shape: vpce-xxxx-yyyy.vpce-svc-zzzz.<region>.vpce.amazonaws.com
# (an AZ-pinned variant also exists). This resolves to the endpoint ENI's private IP in VPC B.
output "endpoint_dns_name" {
  value = aws_vpc_endpoint.service.dns_entry[0].dns_name
}

output "endpoint_id" { value = aws_vpc_endpoint.service.id }
output "endpoint_sg_id" { value = aws_security_group.endpoint.id }
