output "invoke_url" { value = "${aws_api_gateway_stage.lab.invoke_url}/hello" }
output "api_key_id" { value = aws_api_gateway_api_key.client1.id }
output "api_key_value" {
  value     = aws_api_gateway_api_key.client1.value
  sensitive = true
}
