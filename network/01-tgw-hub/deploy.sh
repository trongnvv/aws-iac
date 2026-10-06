#!/usr/bin/env bash
# Apply the lab layers in dependency order: VPC → TGW → SSM → EC2.
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-vpc 2-tgw 3-ssm 4-ec2; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== test instances (ping these across the TGW) ==="
(cd 4-ec2 && tofu output instances)
