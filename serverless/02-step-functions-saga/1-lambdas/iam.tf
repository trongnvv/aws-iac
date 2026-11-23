resource "aws_iam_role" "step" {
  name               = "net-lab-saga-step"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "step_logs" {
  role       = aws_iam_role.step.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
