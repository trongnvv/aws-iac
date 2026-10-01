#!/usr/bin/env bash
# One-time foundation setup: state backend, DNS zone + ACM cert, shared ECR, CI/CD pipeline.
set -euo pipefail
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"   # shared across every root — same provider version everywhere
export GODEBUG="${GODEBUG:+$GODEBUG,}http2client=0"   # tofu HTTP/2 provider downloads occasionally stall
cd "$(dirname "$0")"
# (cd 00-tf-backend && tofu init && tofu apply -auto-approve)
(cd 01-dns && tofu init && tofu apply -auto-approve)
(cd 02-ecr && tofu init && tofu apply -auto-approve)

# 03-cicd: the GitLab webhook can only register once the connection is authorized. So create
# the connection first, pause for the one-time OAuth approval, then apply the rest (webhook).
(cd 03-cicd && tofu init && tofu apply -target=aws_codeconnections_connection.gitlab -auto-approve)
echo
echo "== Authorize the GitLab connection: Console -> Developer Tools -> Connections -> gitlab -> Update pending connection =="
read -r -p "Press ENTER once it shows AVAILABLE... "
(cd 03-cicd && tofu apply -auto-approve)

# 04-app-cicd reuses the 03-cicd connection (remote state) -> must run after it.
(cd 04-app-cicd && tofu init && tofu apply -auto-approve)

echo "== set these NS records at your registrar: =="
(cd 01-dns && tofu output name_servers)
