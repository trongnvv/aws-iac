resource "aws_iam_role" "states" {
  name               = "net-lab-saga-states"
  assume_role_policy = data.aws_iam_policy_document.states_assume.json
}

resource "aws_iam_role_policy" "invoke_steps" {
  name = "invoke-saga-lambdas"
  role = aws_iam_role.states.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = [for arn in local.arns : arn]
    }]
  })
}
