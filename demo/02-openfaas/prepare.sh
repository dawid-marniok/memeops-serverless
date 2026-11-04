#!/usr/bin/env bash
# Demo 02: OpenFaaS CE na klastrze memeops + faas-cli w ~/.local/bin. Ok. 2 min.
# Użycie: demo/02-openfaas/prepare.sh [--delete]
set -euo pipefail
CHART_VERSION=15.0.13
FAAS_CLI_VERSION=0.18.16
if [ "${1:-}" = --delete ]; then helm uninstall openfaas -n openfaas; kubectl delete ns openfaas openfaas-fn --wait=false; exit; fi
kubectl config use-context kind-memeops
if ! command -v faas-cli >/dev/null; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) F=faas-cli ;; Linux-aarch64) F=faas-cli-arm64 ;;
    Darwin-x86_64) F=faas-cli-darwin ;; Darwin-arm64) F=faas-cli-darwin-arm64 ;;
  esac
  mkdir -p "$HOME/.local/bin"
  curl -fsSL "https://github.com/openfaas/faas-cli/releases/download/${FAAS_CLI_VERSION}/${F}" -o "$HOME/.local/bin/faas-cli"
  chmod +x "$HOME/.local/bin/faas-cli"
fi
helm repo add openfaas https://openfaas.github.io/faas-netes/ >/dev/null 2>&1 || true
helm repo update openfaas >/dev/null
kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml
helm upgrade --install openfaas openfaas/openfaas --version "$CHART_VERSION" -n openfaas \
  --set functionNamespace=openfaas-fn --set generateBasicAuth=true --wait --timeout 5m
echo "Hasło admina:"; kubectl -n openfaas get secret basic-auth -o jsonpath='{.data.basic-auth-password}' | base64 -d; echo
echo "W osobnym terminalu: kubectl -n openfaas port-forward svc/gateway 8080:8080"
