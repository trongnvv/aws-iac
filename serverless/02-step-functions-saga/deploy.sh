#!/usr/bin/env bash
# Apply the lab layers in dependency order: lambdas → state machine.
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-lambdas 2-state-machine; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== start an execution (payment declines on purpose, watch the compensation path) ==="
(cd 2-state-machine && aws stepfunctions start-execution \
  --state-machine-arn "$(tofu output -raw state_machine_arn)" \
  --input '{"order_id": "demo"}' \
  --profile default --region ap-southeast-1)
echo "Check the execution in the Step Functions console — ReserveInventory → ChargePayment (fails) → ReleaseInventory → OrderFailed."
