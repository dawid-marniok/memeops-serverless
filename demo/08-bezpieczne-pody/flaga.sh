#!/usr/bin/env bash
# Demo 08: włącza albo wyłącza flagę secure-pod-defaults w Knative (dotyczy całego klastra, tylko NOWYCH rewizji).
# Użycie: demo/08-bezpieczne-pody/flaga.sh Enabled|AllowRootBounded|Disabled
set -euo pipefail
V=${1:?podaj Enabled, AllowRootBounded albo Disabled}
kubectl patch configmap/config-features -n knative-serving --type merge -p "{\"data\":{\"secure-pod-defaults\":\"$V\"}}"
kubectl get cm config-features -n knative-serving -o jsonpath='secure-pod-defaults = {.data.secure-pod-defaults}{"\n"}'
