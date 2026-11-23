resource "aws_lambda_function" "downstream" {
  function_name    = "net-lab-obs-downstream"
  filename         = data.archive_file.downstream.output_path
  source_code_hash = data.archive_file.downstream.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.downstream.arn
  timeout          = 10

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "upstream" {
  function_name    = "net-lab-obs-upstream"
  filename         = data.archive_file.upstream.output_path
  source_code_hash = data.archive_file.upstream.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.upstream.arn
  timeout          = 10

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = { DOWNSTREAM_FUNCTION_NAME = aws_lambda_function.downstream.function_name }
  }
}
