#!/usr/bin/env bash
# Destroy in reverse order: stream consumer → table.
set -euo pipefail
cd "$(dirname "$0")"

for d in 2-stream-consumer 1-table; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
