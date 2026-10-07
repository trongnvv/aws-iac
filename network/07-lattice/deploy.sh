#!/usr/bin/env bash
# Apply the lab layers in dependency order: VPC → service-network → service → client EC2.
#   1-vpc            : two VPCs A + B with OVERLAPPING CIDR (10.0.0.0/16 both), no peering/TGW
#   2-service-network: the Lattice service network + associate both VPCs (IAM auth)
#   3-service        : service EC2 in B + target group + Lattice service/listener + attach to network
#   4-ec2            : client EC2 in A that curls the Lattice DNS name
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-vpc 2-service-network 3-service 4-ec2; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== client + Lattice DNS name (SSM into the client, curl the DNS) ==="
(cd 4-ec2 && tofu output)
