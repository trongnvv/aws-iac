resource "aws_iam_role" "authorizer" {
  name               = "net-lab-api-authorizer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "authorizer_logs" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "net-lab-api-authorizer"
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.authorizer.arn
  timeout          = 10
}

resource "aws_iam_role" "hello" {
  name               = "net-lab-api-hello"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "hello_logs" {
  role       = aws_iam_role.hello.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hello" {
  function_name    = "net-lab-api-hello"
  filename         = data.archive_file.hello.output_path
  source_code_hash = data.archive_file.hello.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.hello.arn
  timeout          = 10
}
