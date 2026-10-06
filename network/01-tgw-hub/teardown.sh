#!/usr/bin/env bash
# Destroy in reverse order: EC2 → SSM → TGW → VPC. (Destroy just 4-ec2 to stop EC2 cost while
# keeping the TGW/VPC up.)
set -euo pipefail
cd "$(dirname "$0")"

for d in 5-egress 4-ec2 3-ssm 2-tgw 1-vpc; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
