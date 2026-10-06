#!/usr/bin/env bash
# Apply the lab layers in dependency order: VPC → TGW → VPN → strongSwan → EC2.
#   1-vpc        two VPCs (aws + simulated on-prem), subnets, IGW, SGs
#   2-tgw        Transit Gateway + aws VPC attachment + route table
#   3-vpn        customer gateway + Site-to-Site VPN (2 tunnels, BGP) + EIP for the appliance
#   4-strongswan the on-prem CGW appliance (strongSwan IPsec + FRR BGP), SSM IAM, onprem→aws route
#   5-ec2        test hosts (aws + onprem) to ping across
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-vpc 2-tgw 3-vpn 4-strongswan 5-ec2; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== strongSwan appliance (Customer Gateway) ==="
(cd 4-strongswan && tofu output)
echo "=== test instances (ping aws ↔ onprem across the VPN) ==="
(cd 5-ec2 && tofu output instances)
echo
echo "VPN tunnels take ~1–2 min to come UP + BGP to establish. Check:"
echo "  aws ec2 describe-vpn-connections --query 'VpnConnections[].VgwTelemetry'"
