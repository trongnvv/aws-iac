resource "aws_iam_role" "consumer" {
  name               = "net-lab-async-consumer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "consumer_logs" {
  role       = aws_iam_role.consumer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "consumer_sqs" {
  name = "consume-queue"
  role = aws_iam_role.consumer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = local.queue_arn
    }]
  })
}

resource "aws_iam_role_policy" "consumer_dynamodb" {
  name = "idempotency-table"
  role = aws_iam_role.consumer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
      Resource = aws_dynamodb_table.idempotency.arn
    }]
  })
}
