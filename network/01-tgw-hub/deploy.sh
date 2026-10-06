#!/usr/bin/env bash
# Apply the lab layers in dependency order: VPC → TGW → SSM → EC2.
set -euo pipefail
cd "$(dirname "$0")"

# 5-egress is optional (enable_egress=false by default → no-op). To turn on centralized egress:
#   (cd 5-egress && tofu apply -var enable_egress=true)
for d in 1-vpc 2-tgw 3-ssm 4-ec2 5-egress; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== test instances (ping these across the TGW) ==="
(cd 4-ec2 && tofu output instances)
