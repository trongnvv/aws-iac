output "instances" {
  description = "Per-side test host: id + private IP. SSM in and run the dig tests (see README)."
  value       = { for k, i in aws_instance.test : k => { id = i.id, private_ip = i.private_ip } }
}
