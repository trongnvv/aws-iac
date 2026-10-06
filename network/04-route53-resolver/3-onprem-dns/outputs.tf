output "onprem_dns_ip" { value = aws_instance.dns.private_ip }
output "onprem_dns_instance_id" { value = aws_instance.dns.id }

# Reused by layer 4-ec2 so the two test hosts share this SSM instance profile.
output "instance_profile_name" { value = aws_iam_instance_profile.ssm.name }
