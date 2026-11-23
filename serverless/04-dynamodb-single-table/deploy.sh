#!/usr/bin/env bash
# Apply the lab layers in dependency order: table → stream consumer.
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-table 2-stream-consumer; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== write a customer + an order ==="
TABLE=$(cd 1-table && tofu output -raw table_name)
aws dynamodb put-item --table-name "$TABLE" --profile default --region ap-southeast-1 --item '{
  "PK": {"S": "CUSTOMER#1"}, "SK": {"S": "CUSTOMER#1"},
  "GSI1PK": {"S": "CUSTOMER#1"}, "GSI1SK": {"S": "METADATA"},
  "name": {"S": "Trong"}
}'
aws dynamodb put-item --table-name "$TABLE" --profile default --region ap-southeast-1 --item '{
  "PK": {"S": "CUSTOMER#1"}, "SK": {"S": "ORDER#1001"},
  "GSI1PK": {"S": "ORDER#1001"}, "GSI1SK": {"S": "ORDER#1001"},
  "amount": {"N": "42"}
}'
echo "Check: aws logs tail /aws/lambda/net-lab-stream-consumer --since 2m --profile default --region ap-southeast-1"
echo "Access pattern 1 (customer + all orders): aws dynamodb query --table-name $TABLE --key-condition-expression 'PK = :pk' --expression-attribute-values '{\":pk\":{\"S\":\"CUSTOMER#1\"}}'"
echo "Access pattern 2 (order by its own id, via GSI1): aws dynamodb query --table-name $TABLE --index-name GSI1 --key-condition-expression 'GSI1PK = :pk' --expression-attribute-values '{\":pk\":{\"S\":\"ORDER#1001\"}}'"
