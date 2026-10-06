#!/usr/bin/env bash
# Destroy in reverse order: EC2 → consumer → provider → VPC. (Destroy just 4-ec2 + 2-provider to stop
# the EC2 + NLB cost while keeping the VPCs.)
set -euo pipefail
cd "$(dirname "$0")"

for d in 4-ec2 3-consumer 2-provider 1-vpc; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
