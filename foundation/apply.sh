#!/usr/bin/env bash
# One-time foundation setup: state backend, then DNS zone + ACM cert.
set -euo pipefail
cd "$(dirname "$0")"
(cd 00-tf-backend && tofu init && tofu apply -auto-approve)
(cd 01-dns && tofu init && tofu apply -auto-approve)
echo "== set these NS records at your registrar: =="
(cd 01-dns && tofu output name_servers)
