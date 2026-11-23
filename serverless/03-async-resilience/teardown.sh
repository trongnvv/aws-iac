#!/usr/bin/env bash
# Destroy in reverse order: consumer → queue.
set -euo pipefail
cd "$(dirname "$0")"

for d in 2-consumer 1-queue; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
