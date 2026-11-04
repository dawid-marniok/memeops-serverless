#!/usr/bin/env bash
# Demo 12: osobny klaster kind z shimem Spin (containerd-shim-spin v0.26.0). Ok. 2 min.
# Użycie: demo/12-wasm/prepare.sh [--delete]
set -euo pipefail
cd "$(dirname "$0")"
if [ "${1:-}" = --delete ]; then kind delete cluster --name wasm; kubectl config use-context kind-memeops; exit; fi
if ! kind get clusters | grep -qx wasm; then
  # Obraz kind ma binarkę shima, ale runtime trzeba zarejestrować w containerd — bez tego:
  # „no runtime for "spin" is configured” (pułapka z próby 29.10)
  cat <<'YAML' | kind create cluster --name wasm --image ghcr.io/spinframework/containerd-shim-spin/kind:v0.26.0 --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.spin]
    runtime_type = "io.containerd.spin.v2"
YAML
fi
kubectl --context kind-wasm apply -f wasm.yaml
kubectl --context kind-wasm rollout status deploy/wasm-hello deploy/python-hello --timeout=180s
kubectl config use-context kind-memeops   # wróć do klastra szkolenia
echo "Gotowe. Demo: kubectl --context kind-wasm …"
