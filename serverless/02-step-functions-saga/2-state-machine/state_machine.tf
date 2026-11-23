resource "aws_sfn_state_machine" "saga" {
  name     = "net-lab-order-saga"
  role_arn = aws_iam_role.states.arn
  type     = "STANDARD" # needs full execution history for this lab's Core goal (inspect the Catch path)

  definition = templatefile("${path.module}/asl.json.tftpl", {
    reserve_inventory_arn = local.arns["reserve_inventory"]
    charge_payment_arn    = local.arns["charge_payment"]
    release_inventory_arn = local.arns["release_inventory"]
    ship_order_arn        = local.arns["ship_order"]
  })
}
