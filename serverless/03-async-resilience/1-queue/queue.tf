# DLQ first — the main queue's redrive policy references it.
resource "aws_sqs_queue" "dlq" {
  name                      = "net-lab-orders-dlq"
  message_retention_seconds = 1209600 # 14 days — keep failed messages around to inspect/replay
}

resource "aws_sqs_queue" "main" {
  name                       = "net-lab-orders-queue"
  visibility_timeout_seconds = 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3 # a poison message gets 3 attempts, then lands in the DLQ instead of looping forever
  })
}
