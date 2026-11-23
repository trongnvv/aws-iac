#!/usr/bin/env bash
# Single layer. Provisioned concurrency takes a minute or two to actually warm up after apply —
# wait a bit before the "live" invoke below if you want a clean comparison.
set -euo pipefail
cd "$(dirname "$0")"

(cd 1-lambda && tofu init -input=false >/dev/null && tofu apply -auto-approve)

FN=$(cd 1-lambda && tofu output -raw function_name)
ALIAS=$(cd 1-lambda && tofu output -raw live_alias)

echo "=== cold: invoking \$LATEST right after apply (pays the 1s init.sleep stand-in) ==="
aws lambda invoke --function-name "$FN" --qualifier '$LATEST' --profile default --region ap-southeast-1 /dev/stdout

echo "=== provisioned: invoking the '$ALIAS' alias (should show ~0 Init Duration) ==="
aws lambda invoke --function-name "$FN" --qualifier "$ALIAS" --profile default --region ap-southeast-1 /dev/stdout

echo "Compare Init Duration in both REPORT lines:"
echo "aws logs tail /aws/lambda/$FN --since 5m --profile default --region ap-southeast-1 | grep REPORT"
