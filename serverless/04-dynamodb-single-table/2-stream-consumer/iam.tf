resource "aws_iam_role" "consumer" {
  name               = "net-lab-stream-consumer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "consumer_logs" {
  role       = aws_iam_role.consumer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "consumer_stream" {
  name = "read-stream"
  role = aws_iam_role.consumer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:DescribeStream",
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator",
        "dynamodb:ListStreams",
      ]
      Resource = local.stream_arn
    }]
  })
}
