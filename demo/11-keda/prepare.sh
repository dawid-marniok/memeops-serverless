#!/usr/bin/env bash
# Demo 11: KEDA (Helm) + Redis + worker skalowany od zera. Ok. 1–2 min.
# Użycie: demo/11-keda/prepare.sh [--delete]
set -euo pipefail
cd "$(dirname "$0")/../.."
KEDA_VERSION=2.21.0
if [ "${1:-}" = --delete ]; then
  kubectl delete -f demo/11-keda/keda.yaml --ignore-not-found
  helm uninstall keda -n keda || true
  kubectl delete ns keda --ignore-not-found --wait=false
  exit
fi
helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1 || true
helm repo update kedacore >/dev/null
helm upgrade --install keda kedacore/keda --version "$KEDA_VERSION" -n keda --create-namespace --wait --timeout 5m
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/11-keda/keda.yaml
kubectl -n demo rollout status deploy/redis --timeout=120s
kubectl -n demo wait scaledobject/generator --for=condition=Ready --timeout=120s
echo "Gotowe. Obserwuj: kubectl get pods -n demo -l app=generator -w"
