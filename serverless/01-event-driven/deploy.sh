#!/usr/bin/env bash
# Apply the lab layers in dependency order: bus → lambdas.
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-bus 2-lambdas; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== invoke the producer (fires one order.created event to both consumers) ==="
(cd 2-lambdas && aws lambda invoke --function-name "$(tofu output -raw producer_function_name)" --profile default --region ap-southeast-1 /dev/stdout)

echo "=== check both consumers got it ==="
echo "aws logs tail /aws/lambda/net-lab-events-consumer_a --since 2m --profile default --region ap-southeast-1"
echo "aws logs tail /aws/lambda/net-lab-events-consumer_b --since 2m --profile default --region ap-southeast-1"
