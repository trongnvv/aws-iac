output "egress_enabled" { value = local.on }
output "nat_public_ip" { value = local.on ? aws_eip.nat[0].public_ip : null }
output "private_instances" {
  value = { for k, i in aws_instance.private : k => { id = i.id, private_ip = i.private_ip } }
}
