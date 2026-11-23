# The four saga steps. All same shape — one archive each, one shared basic-logging role (none
# needs any AWS permission beyond CloudWatch Logs, this lab is about orchestration, not access).
locals {
  steps = ["reserve_inventory", "charge_payment", "release_inventory", "ship_order"]
}

data "archive_file" "step" {
  for_each    = toset(local.steps)
  type        = "zip"
  source_dir  = "${path.module}/src/${each.key}"
  output_path = "${path.module}/.build/${each.key}.zip"
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
