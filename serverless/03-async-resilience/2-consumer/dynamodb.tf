# Idempotency ledger — one item per processed message_id, checked before any real work happens.
resource "aws_dynamodb_table" "idempotency" {
  name         = "net-lab-idempotency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "message_id"

  attribute {
    name = "message_id"
    type = "S"
  }
}
