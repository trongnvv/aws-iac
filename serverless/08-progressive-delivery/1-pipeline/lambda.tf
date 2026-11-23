resource "aws_iam_role" "hello" {
  name               = "net-lab-pd-hello"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "hello_logs" {
  role       = aws_iam_role.hello.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hello" {
  function_name    = "net-lab-pd-hello"
  filename         = data.archive_file.hello.output_path
  source_code_hash = data.archive_file.hello.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.hello.arn
  timeout          = 10
  publish          = true

  environment {
    variables = {
      FAIL          = tostring(var.fail)
      VERSION_LABEL = var.version_label
    }
  }
}

# CodeDeploy manages this alias's traffic weighting during a canary rollout — never point
# anything at a raw version ARN, always at "live".
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.hello.function_name
  function_version = aws_lambda_function.hello.version

  lifecycle {
    # CodeDeploy, not Terraform, owns this once a canary deployment starts shifting traffic.
    ignore_changes = [routing_config]
  }
}
