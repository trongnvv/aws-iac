resource "aws_iam_role" "perf" {
  name               = "net-lab-perf"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "perf_logs" {
  role       = aws_iam_role.perf.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
