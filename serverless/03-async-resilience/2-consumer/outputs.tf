output "consumer_function_name" { value = aws_lambda_function.consumer.function_name }
output "idempotency_table_name" { value = aws_dynamodb_table.idempotency.name }
