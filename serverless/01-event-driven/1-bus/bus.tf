# Custom bus, not the account's default bus — keeps this lab's events (and any schema discovery)
# isolated from everything else in the account.
resource "aws_cloudwatch_event_bus" "this" {
  name = "net-lab-orders"
}
