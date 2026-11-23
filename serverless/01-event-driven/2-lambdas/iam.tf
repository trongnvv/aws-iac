# Producer: basic logging + permission to put events on the bus only — nothing else.
resource "aws_iam_role" "producer" {
  name               = "net-lab-events-producer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "producer_logs" {
  role       = aws_iam_role.producer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "producer_put_events" {
  name = "put-events"
  role = aws_iam_role.producer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = local.bus_arn
    }]
  })
}

# Consumers: basic logging only, shared by both — neither needs any bus permission (EventBridge
# invokes them, they never call EventBridge themselves).
resource "aws_iam_role" "consumer" {
  name               = "net-lab-events-consumer"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy_attachment" "consumer_logs" {
  role       = aws_iam_role.consumer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
