#!/usr/bin/env bash
# Destroy in reverse: 4-ec2 → 3-onprem-dns → 2-dns → 1-vpc.
# Resolver endpoints bill ~$0.125/ENI/hour (4 ENIs ≈ $0.50/h) — the pricey part. Tear down promptly.
# To stop just the compute (keep endpoints) run `(cd 4-ec2 && tofu destroy)` + the on-prem host.
set -euo pipefail
cd "$(dirname "$0")"

for d in 4-ec2 3-onprem-dns 2-dns 1-vpc; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
