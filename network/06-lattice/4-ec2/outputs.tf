output "client_instance_id" {
  description = "SSM into this (VPC A), then curl the service DNS name below."
  value       = aws_instance.client.id
}

output "service_dns_name" {
  description = "curl http://<this> from the client - reaches VPC B across overlapping CIDR."
  value       = local.service_dns_name
}
