#!/usr/bin/env bash
# Destroy in reverse order: EC2 → strongSwan → VPN → TGW → VPC. (Destroy just 5-ec2 + 4-strongswan to
# stop EC2 cost while keeping the VPN/TGW up — though the VPN connection itself bills ~$0.05/h.)
set -euo pipefail
cd "$(dirname "$0")"

for d in 5-ec2 4-strongswan 3-vpn 2-tgw 1-vpc; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
