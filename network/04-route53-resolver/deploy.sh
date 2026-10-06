#!/usr/bin/env bash
# Apply in dependency order:
#   1-vpc         — AWS VPC + on-prem VPC + peering + routes + SGs
#   2-dns         — PHZ aws.internal, inbound + outbound resolver endpoints, corp.local forwarding rule
#                   (rule targets the STATIC on-prem DNS IP 192.168.0.53 — host built next)
#   3-onprem-dns  — dnsmasq EC2 at that static IP; its user_data gets the inbound endpoint IPs from 2-dns
#   4-ec2         — the two SSM test hosts (aws + onprem)
#
# Ordering trick (chicken-and-egg): the outbound rule (2-dns) needs the on-prem DNS IP, and the on-prem
# dnsmasq (3) needs the inbound endpoint IPs. Broken by PINNING the on-prem DNS IP static → 2-dns can
# target it before layer 3 exists; 3 then reads the inbound IPs out of 2's remote state. So 2 before 3.
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-vpc 2-dns 3-onprem-dns 4-ec2; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== test hosts (SSM in and run the dig tests — see README) ==="
(cd 4-ec2 && tofu output instances)
