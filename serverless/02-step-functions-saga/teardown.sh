#!/usr/bin/env bash
# Destroy in reverse order: state machine → lambdas.
set -euo pipefail
cd "$(dirname "$0")"

for d in 2-state-machine 1-lambdas; do
  echo "=== destroy $d ==="
  (cd "$d" && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
done
