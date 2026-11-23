resource "aws_lambda_function" "step" {
  for_each         = toset(local.steps)
  function_name    = "net-lab-saga-${each.key}"
  filename         = data.archive_file.step[each.key].output_path
  source_code_hash = data.archive_file.step[each.key].output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.step.arn
  timeout          = 10
}
