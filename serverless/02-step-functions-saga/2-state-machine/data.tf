data "terraform_remote_state" "lambdas" {
  backend = "s3"
  config  = { bucket = "serverless-iac-tfstate", key = "02-step-functions-saga/1-lambdas/terraform.tfstate", region = "ap-southeast-1" }
}

data "aws_iam_policy_document" "states_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

locals {
  arns = data.terraform_remote_state.lambdas.outputs.function_arns
}
