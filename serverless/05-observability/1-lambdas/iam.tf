# Both roles get X-Ray write access — required for either function to emit trace segments once
# active tracing is turned on below.
resource "aws_iam_role" "downstream" {
  name               = "net-lab-obs-downstream"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "downstream_logs" {
  role       = aws_iam_role.downstream.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "downstream_xray" {
  role       = aws_iam_role.downstream.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role" "upstream" {
  name               = "net-lab-obs-upstream"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "upstream_logs" {
  role       = aws_iam_role.upstream.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "upstream_xray" {
  role       = aws_iam_role.upstream.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
resource "aws_iam_role_policy" "upstream_invoke_downstream" {
  name = "invoke-downstream"
  role = aws_iam_role.upstream.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.downstream.arn
    }]
  })
}
