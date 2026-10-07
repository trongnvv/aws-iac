#!/usr/bin/env bash
# Apply the lab layers in dependency order: VPC → TGW → DXGW → VPN → strongSwan → EC2.
#   1-vpc        two VPCs (aws + simulated on-prem), subnets, IGW, SGs
#   2-tgw        Transit Gateway + aws VPC attachment + route table
#   3-dxgw       DX Gateway + DXGW↔TGW association (allowed_prefixes) — the DX-as-code control plane
#   4-vpn        customer gateway + Site-to-Site VPN (2 tunnels, BGP) + EIP — the transport stand-in
#   5-strongswan the on-prem router appliance (strongSwan IPsec + FRR BGP), SSM IAM, onprem→aws route
#   6-ec2        test hosts (aws + onprem) to ping across
#
# The physical cross-connect + Transit VIF (BGP to the DX Gateway) is the ONE manual step — see the
# README "⚠️ Verify live" / the manual step box. This script builds everything that IaC can build.
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-vpc 2-tgw 3-dxgw 4-vpn 5-strongswan 6-ec2; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== DX Gateway + association (the DX-as-code half) ==="
(cd 3-dxgw && tofu output)
echo "=== strongSwan appliance (on-prem router / VPN transport stand-in) ==="
(cd 5-strongswan && tofu output)
echo "=== test instances (ping aws ↔ onprem across the DX/VPN path) ==="
(cd 6-ec2 && tofu output instances)
echo
echo "VPN tunnels take ~1–2 min to come UP + BGP to establish. Check:"
echo "  aws ec2 describe-vpn-connections --query 'VpnConnections[].VgwTelemetry'"
echo "  aws directconnect describe-direct-connect-gateway-associations"
