# publish=true gives a real numbered version — provisioned concurrency attaches to a version/alias,
# never to $LATEST.
resource "aws_lambda_function" "perf" {
  function_name    = "net-lab-perf"
  filename         = data.archive_file.perf.output_path
  source_code_hash = data.archive_file.perf.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.perf.arn
  timeout          = 10
  publish          = true
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.perf.function_name
  function_version = aws_lambda_function.perf.version
}

# Keeps 1 execution environment pre-initialized at all times — invoking via this alias skips
# Init Duration entirely; invoking $LATEST directly still pays it on a cold start.
resource "aws_lambda_provisioned_concurrency_config" "live" {
  function_name                     = aws_lambda_function.perf.function_name
  qualifier                         = aws_lambda_alias.live.name
  provisioned_concurrent_executions = 1
}
