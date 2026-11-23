data "archive_file" "downstream" {
  type        = "zip"
  source_dir  = "${path.module}/src/downstream"
  output_path = "${path.module}/.build/downstream.zip"
}
data "archive_file" "upstream" {
  type        = "zip"
  source_dir  = "${path.module}/src/upstream"
  output_path = "${path.module}/.build/upstream.zip"
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
