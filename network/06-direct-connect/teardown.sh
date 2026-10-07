#!/usr/bin/env bash
# Destroy in reverse order: EC2 → strongSwan → VPN → DXGW → TGW → VPC. (Destroy just 6-ec2 + 5-strongswan
# to stop EC2 cost while keeping the VPN/DXGW/TGW up — though the VPN connection itself bills ~$0.05/h.)
#
# Order matters: the DXGW↔TGW association (3-dxgw) must go before the TGW (2-tgw). The VPN attachment
# (4-vpn) also rides the TGW, so it is destroyed before the TGW too.
set -euo pipefail
cd "$(dirname "$0")"

for d in 6-ec2 5-strongswan 4-vpn 3-dxgw 2-tgw 1-vpc; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
