resource "aws_iam_role" "codedeploy" {
  name               = "net-lab-pd-codedeploy"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume.json
}
resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda"
}

resource "aws_codedeploy_app" "this" {
  name             = "net-lab-pd-app"
  compute_platform = "Lambda"
}

# Canary 10% → 100% over 5 minutes, watched by the Errors alarm above — a breach mid-canary
# rolls the "live" alias straight back to the prior version, no manual intervention.
resource "aws_codedeploy_deployment_group" "this" {
  app_name               = aws_codedeploy_app.this.name
  deployment_group_name  = "net-lab-pd-dg"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.LambdaCanary10Percent5Minutes"

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  alarm_configuration {
    alarms  = [aws_cloudwatch_metric_alarm.errors.alarm_name]
    enabled = true
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }
}
