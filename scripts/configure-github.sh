#!/usr/bin/env bash
# Configura um repositório GitHub para usar OIDC com a Azure (após o bootstrap).
# Cria os GitHub Environments e grava as Variables (IDs não são segredos).
#
# Uso:
#   scripts/configure-github.sh <repo> <infra|deployer> [env ...] [-- CHAVE=VALOR ...]
# Exemplos:
#   scripts/configure-github.sh platform-infra infra dev
#   scripts/configure-github.sh pedidos-service deployer dev prd -- ACR_NAME=acredpdevabcde
set -euo pipefail

OWNER="${GITHUB_OWNER:-ViniciusOtoni}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

repo="${1:?informe o repositório}"
role="${2:?informe o papel: infra|deployer}"
shift 2

envs=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
[ "${1:-}" = "--" ] && shift
extra=("$@")

case "$role" in
  infra) client_output="infra_client_id" ;;
  deployer) client_output="deployer_client_id" ;;
  *) echo "papel inválido: $role" >&2; exit 1 ;;
esac

out() { terraform -chdir="$ROOT/bootstrap" output -raw "$1"; }

client_id="$(out "$client_output")"
tenant_id="$(out tenant_id)"
subscription_id="$(out subscription_id)"

echo "Configurando $OWNER/$repo (papel: $role)"
gh variable set AZURE_CLIENT_ID --repo "$OWNER/$repo" --body "$client_id"
gh variable set AZURE_TENANT_ID --repo "$OWNER/$repo" --body "$tenant_id"
gh variable set AZURE_SUBSCRIPTION_ID --repo "$OWNER/$repo" --body "$subscription_id"

for kv in "${extra[@]}"; do
  gh variable set "${kv%%=*}" --repo "$OWNER/$repo" --body "${kv#*=}"
done

for env in "${envs[@]}"; do
  gh api --silent -X PUT "repos/$OWNER/$repo/environments/$env"
  echo "  environment '$env' ok"
done

echo "Pronto. Lembre-se: o subject OIDC precisa estar em github_identities (bootstrap/variables.tf)."
