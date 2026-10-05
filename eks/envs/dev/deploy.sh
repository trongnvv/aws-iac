#!/usr/bin/env bash
# Deploy dev. No arg = all layers in order; or pass one: 00-infra|01-addons|02-platform|03-application.
# Prereq: run ../../foundation/apply.sh once (state backend + shared ECR + DNS).
set -euo pipefail
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
export GODEBUG="${GODEBUG:+$GODEBUG,}http2client=0"   # tofu HTTP/2 provider downloads occasionally stall
cd "$(dirname "$0")"
REGION=ap-southeast-1
CLUSTER=eks-dev
GWAPI_VERSION=v1.6.0   # matches LBC v3.5 conformance

LAYER="${1:-all}"
case "$LAYER" in
  all|00-infra|01-addons|02-platform|03-application) ;;
  *) echo "usage: $0 [all|00-infra|01-addons|02-platform|03-application]"; exit 1 ;;
esac
run() { [ "$LAYER" = "all" ] || [ "$LAYER" = "$1" ]; }

if run 00-infra; then
  echo "== 00-infra (Terraform) · env=dev =="
  for d in 00-infra/*/; do
    ( cd "$d" && tofu init && tofu apply -auto-approve )
  done

  # Reference cache (git-ignored); helm values are hardcoded — diff this to confirm they still match.
  echo "== cache infra outputs -> outputs.cache.json =="
  for d in 00-infra/*/; do
    ( cd "$d" && tofu output -json 2>/dev/null || echo '{}' ) | jq --arg k "$(basename "$d")" '{($k): .}'
  done | jq -s 'add' > outputs.cache.json
fi

if run 01-addons || run 02-platform || run 03-application; then
  echo "== wire kubeconfig =="
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"

  # Upstream Gateway API CRDs — applied before addons so LBC starts with them present.
  # LBC's own gateway.k8s.aws CRDs ship with its chart. Idempotent (server-side apply).
  echo "== Gateway API CRDs (${GWAPI_VERSION}) =="
  kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GWAPI_VERSION}/standard-install.yaml"
fi

if run 01-addons; then
  echo "== 01-addons =="
  for d in 01-addons/*/; do ( cd "$d" && helmfile apply --skip-diff-on-install ); done
fi

if run 02-platform; then
  echo "== 02-platform =="
  # Stamp the AMP workspace ID into the observability values (plain YAML, no tofu-output wiring).
  # Idempotent: no-op once stamped. AMP survives teardown so the ID stays stable.
  if [ -d 00-infra/05-observability-aws ]; then
    WS=$(cd 00-infra/05-observability-aws && tofu output -raw amp_endpoint 2>/dev/null | sed -nE 's#.*/workspaces/(ws-[0-9a-f-]+)/?#\1#p') || true
    if [ -n "${WS:-}" ]; then
      for f in 02-platform/01-observability/values.yaml 02-platform/07-observability-aws/adot-values.yaml; do
        perl -pi -e "s/ws-REPLACE-ME/$WS/g" "$f"
      done
      echo "stamped AMP workspace $WS"
    fi
  fi
  for d in 02-platform/*/; do ( cd "$d" && helmfile apply --skip-diff-on-install ); done
fi

if run 03-application; then
  echo "== 03-application =="
  for d in 03-application/*/; do ( cd "$d" && helmfile apply --skip-diff-on-install ); done
fi

echo "== done: dev ($LAYER) =="
