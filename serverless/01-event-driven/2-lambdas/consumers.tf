# Both consumers match the SAME detail-type on the SAME bus — this is the fan-out proof: adding
# consumer_b required zero changes to the producer or consumer_a.
locals {
  consumers = {
    consumer_a = data.archive_file.consumer_a
    consumer_b = data.archive_file.consumer_b
  }
}

resource "aws_lambda_function" "consumer" {
  for_each         = local.consumers
  function_name    = "net-lab-events-${each.key}"
  filename         = each.value.output_path
  source_code_hash = each.value.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  role             = aws_iam_role.consumer.arn
  timeout          = 10
}

resource "aws_cloudwatch_event_rule" "order_created" {
  for_each       = local.consumers
  name           = "net-lab-order-created-${each.key}"
  event_bus_name = local.bus_name
  event_pattern = jsonencode({
    source      = ["net-lab.orders"]
    detail-type = ["order.created"]
  })
}

resource "aws_cloudwatch_event_target" "consumer" {
  for_each       = local.consumers
  rule           = aws_cloudwatch_event_rule.order_created[each.key].name
  event_bus_name = local.bus_name
  arn            = aws_lambda_function.consumer[each.key].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  for_each      = local.consumers
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.consumer[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_created[each.key].arn
}
