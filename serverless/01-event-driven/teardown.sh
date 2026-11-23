#!/usr/bin/env bash
# Destroy in reverse order: lambdas → bus.
set -euo pipefail
cd "$(dirname "$0")"

for d in 2-lambdas 1-bus; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
