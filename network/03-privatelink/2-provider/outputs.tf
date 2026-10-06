# The service name the consumer plugs into its interface endpoint (remote_state in 3-consumer).
output "endpoint_service_name" { value = aws_vpc_endpoint_service.service.service_name }
output "nlb_dns_name" { value = aws_lb.service.dns_name }
output "service_instance_id" { value = aws_instance.service.id }

# Reused by the consumer test host in 4-ec2 (one SSM profile for the whole lab).
output "instance_profile_name" { value = aws_iam_instance_profile.ssm.name }
