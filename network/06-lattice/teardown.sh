#!/usr/bin/env bash
# Destroy in reverse order: client EC2 → service → service-network → VPC.
# (Destroy just 3-service + 4-ec2 to stop EC2 + per-service Lattice cost while keeping the network.)
set -euo pipefail
cd "$(dirname "$0")"

for d in 4-ec2 3-service 2-service-network 1-vpc; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
