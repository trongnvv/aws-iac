data "archive_file" "perf" {
  type        = "zip"
  source_dir  = "${path.module}/src/perf"
  output_path = "${path.module}/.build/perf.zip"
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
