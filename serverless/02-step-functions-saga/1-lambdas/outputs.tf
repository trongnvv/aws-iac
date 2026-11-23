output "function_arns" { value = { for k, f in aws_lambda_function.step : k => f.arn } }
output "function_names" { value = { for k, f in aws_lambda_function.step : k => f.function_name } }
