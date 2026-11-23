#!/usr/bin/env bash
# Apply the lab layers in dependency order: queue → consumer.
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-queue 2-consumer; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== send one good message + one poison message ==="
QUEUE_URL=$(cd 1-queue && tofu output -raw queue_url)
aws sqs send-message --queue-url "$QUEUE_URL" --message-body '{"order_id":"ok-1"}' --profile default --region ap-southeast-1
aws sqs send-message --queue-url "$QUEUE_URL" --message-body '{"order_id":"bad-1","poison":true}' --profile default --region ap-southeast-1
echo "Watch: the poison message retries 3x then lands in the DLQ; the good one processes once (check idempotency table net-lab-idempotency)."
