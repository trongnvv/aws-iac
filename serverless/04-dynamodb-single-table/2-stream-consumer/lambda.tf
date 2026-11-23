resource "aws_lambda_function" "consumer" {
  function_name    = "net-lab-stream-consumer"
  filename         = data.archive_file.consumer.output_path
  source_code_hash = data.archive_file.consumer.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.consumer.arn
  timeout          = 10
}

resource "aws_lambda_event_source_mapping" "stream" {
  event_source_arn  = local.stream_arn
  function_name     = aws_lambda_function.consumer.arn
  starting_position = "LATEST"
  batch_size        = 10
}
