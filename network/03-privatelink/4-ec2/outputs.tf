output "consumer_instance_id" { value = aws_instance.consumer.id }

# The exact command to run after `aws ssm start-session --target <consumer_instance_id>`.
output "test_command" {
  value = "curl http://${local.endpoint_dns_name}"
}
