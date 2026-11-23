data "terraform_remote_state" "queue" {
  backend = "s3"
  config  = { bucket = "serverless-iac-tfstate", key = "03-async-resilience/1-queue/terraform.tfstate", region = "ap-southeast-1" }
}

data "archive_file" "consumer" {
  type        = "zip"
  source_dir  = "${path.module}/src/consumer"
  output_path = "${path.module}/.build/consumer.zip"
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
  queue_arn = data.terraform_remote_state.queue.outputs.queue_arn
}
