data "terraform_remote_state" "bus" {
  backend = "s3"
  config  = { bucket = "serverless-iac-tfstate", key = "01-event-driven/1-bus/terraform.tfstate", region = "ap-southeast-1" }
}

data "archive_file" "producer" {
  type        = "zip"
  source_dir  = "${path.module}/src/producer"
  output_path = "${path.module}/.build/producer.zip"
}
data "archive_file" "consumer_a" {
  type        = "zip"
  source_dir  = "${path.module}/src/consumer_a"
  output_path = "${path.module}/.build/consumer_a.zip"
}
data "archive_file" "consumer_b" {
  type        = "zip"
  source_dir  = "${path.module}/src/consumer_b"
  output_path = "${path.module}/.build/consumer_b.zip"
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

locals {
  bus_name = data.terraform_remote_state.bus.outputs.bus_name
  bus_arn  = data.terraform_remote_state.bus.outputs.bus_arn
}
