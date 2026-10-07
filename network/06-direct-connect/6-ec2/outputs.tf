output "instances" {
  description = "Per-VPC test instance: id + private IP (ping aws ↔ onprem across the DX/VPN path)."
  value       = { for k, i in aws_instance.test : k => { id = i.id, private_ip = i.private_ip } }
}
