#!/usr/bin/env bash
# Destroy in reverse order: EC2 → SSM → Peering → VPC. (Destroy just 4-ec2 to stop EC2 cost while
# keeping the VPCs/peerings up — peerings themselves have no hourly charge.)
set -euo pipefail
cd "$(dirname "$0")"

for d in 4-ec2 3-ssm 2-peering 1-vpc; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
