#!/usr/bin/env bash
# Single layer — just the two lambdas.
set -euo pipefail
cd "$(dirname "$0")"

(cd 1-lambdas && tofu init -input=false >/dev/null && tofu apply -auto-approve)

echo "=== invoke upstream (traces through to downstream) ==="
FN=$(cd 1-lambdas && tofu output -raw upstream_function_name)
aws lambda invoke --function-name "$FN" --profile default --region ap-southeast-1 /dev/stdout
echo "Check the X-Ray trace: aws xray get-trace-summaries --start-time \$(date -v-5M +%s) --end-time \$(date +%s) --profile default --region ap-southeast-1"
echo "Or just open the console: X-Ray → Traces (last few minutes) — one trace spanning net-lab-obs-upstream → net-lab-obs-downstream"
echo "Check the metric: CloudWatch → Metrics → net-lab/Serverless → ProcessingTimeMs"
