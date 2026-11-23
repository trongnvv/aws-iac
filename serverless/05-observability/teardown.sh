#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
(cd 1-lambdas && tofu init -input=false >/dev/null && tofu destroy -auto-approve)
