resource "aws_lambda_function" "consumer" {
  function_name    = "net-lab-async-consumer"
  filename         = data.archive_file.consumer.output_path
  source_code_hash = data.archive_file.consumer.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.consumer.arn
  timeout          = 10

  environment {
    variables = { IDEMPOTENCY_TABLE = aws_dynamodb_table.idempotency.name }
  }
}

# ReportBatchItemFailures: the handler returns only the failed message IDs — SQS retries just
# those, not the whole batch. Without this, one bad message in a batch fails everything in it.
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn        = local.queue_arn
  function_name           = aws_lambda_function.consumer.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
}
