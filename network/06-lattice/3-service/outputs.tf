output "instance_profile_name" {
  description = "Reused by 4-ec2 for the client host."
  value       = aws_iam_instance_profile.ssm.name
}

output "service_instance_id" { value = aws_instance.service.id }
output "service_id" { value = aws_vpclattice_service.this.id }

output "service_dns_name" {
  description = "Lattice DNS name of service B - the client in VPC A curls this (http://<dns>)."
  value       = aws_vpclattice_service.this.dns_entry[0].domain_name
}
