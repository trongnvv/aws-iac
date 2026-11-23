output "function_name" { value = aws_lambda_function.hello.function_name }
output "current_version" { value = aws_lambda_function.hello.version }
output "alias_name" { value = aws_lambda_alias.live.name }
output "codedeploy_app_name" { value = aws_codedeploy_app.this.name }
output "codedeploy_deployment_group" { value = aws_codedeploy_deployment_group.this.deployment_group_name }
