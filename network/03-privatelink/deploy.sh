#!/usr/bin/env bash
# Apply the lab layers in dependency order: VPC → provider (NLB + endpoint service) → consumer
# (interface endpoint) → EC2 (consumer test host). The order matters: the consumer endpoint needs the
# provider's endpoint service name, and the test host needs the endpoint's DNS name.
set -euo pipefail
cd "$(dirname "$0")"

for d in 1-vpc 2-provider 3-consumer 4-ec2; do
  echo "=== apply $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu apply -auto-approve)
done

echo "=== consumer test host (SSM in, then curl the endpoint) ==="
(cd 4-ec2 && tofu output consumer_instance_id && tofu output test_command)
