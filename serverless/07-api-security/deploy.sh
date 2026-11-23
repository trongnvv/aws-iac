#!/usr/bin/env bash
# Single layer — API Gateway + both lambdas + usage plan.
set -euo pipefail
cd "$(dirname "$0")"

(cd 1-api && tofu init -input=false >/dev/null && tofu apply -auto-approve)

URL=$(cd 1-api && tofu output -raw invoke_url)
KEY=$(cd 1-api && aws apigateway get-api-key --api-key "$(tofu output -raw api_key_id)" --include-value --profile default --region ap-southeast-1 --query value --output text)

echo "=== unauthorized caller — expect 403 ==="
curl -s -o /dev/null -w "%{http_code}\n" "$URL" -H "x-api-key: $KEY"

echo "=== authorized caller — expect 200 ==="
curl -s -o /dev/null -w "%{http_code}\n" "$URL" -H "Authorization: Bearer net-lab-secret-token" -H "x-api-key: $KEY"

echo "=== burst past the usage plan's rate limit (5 req/s, burst 10) — expect some 429s ==="
for i in $(seq 1 20); do
  curl -s -o /dev/null -w "%{http_code} " "$URL" -H "Authorization: Bearer net-lab-secret-token" -H "x-api-key: $KEY" &
done
wait
echo
