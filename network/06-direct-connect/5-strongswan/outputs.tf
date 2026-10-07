output "strongswan_instance_id" { value = aws_instance.strongswan.id }
output "strongswan_private_ip" { value = aws_instance.strongswan.private_ip }
output "strongswan_public_ip" { value = local.no.strongswan_eip }
output "strongswan_eni_id" { value = aws_instance.strongswan.primary_network_interface_id }

# 6-ec2 reads this to attach the same SSM instance profile to the test hosts.
output "instance_profile_name" { value = aws_iam_instance_profile.ssm.name }
