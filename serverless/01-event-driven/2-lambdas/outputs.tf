output "producer_function_name" { value = aws_lambda_function.producer.function_name }
output "consumer_function_names" { value = { for k, f in aws_lambda_function.consumer : k => f.function_name } }
