data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = "${path.module}/src/authorizer"
  output_path = "${path.module}/.build/authorizer.zip"
}
data "archive_file" "hello" {
  type        = "zip"
  source_dir  = "${path.module}/src/hello"
  output_path = "${path.module}/.build/hello.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_caller_identity" "current" {}
