resource "aws_lambda_function" "producer" {
  function_name    = "net-lab-events-producer"
  filename         = data.archive_file.producer.output_path
  source_code_hash = data.archive_file.producer.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.producer.arn
  timeout          = 10

  environment {
    variables = { EVENT_BUS_NAME = local.bus_name }
  }
}
