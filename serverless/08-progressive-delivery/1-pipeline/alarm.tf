# Watches the "live" alias specifically (not the function as a whole) — this is what
# alarm_configuration below plugs into CodeDeploy as the auto-rollback trigger.
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "net-lab-pd-hello-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.hello.function_name
    Resource     = "${aws_lambda_function.hello.function_name}:${aws_lambda_alias.live.name}"
  }
}
