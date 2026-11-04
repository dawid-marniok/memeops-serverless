#!/usr/bin/env bash
# Demo 04: Knative Eventing (core + InMemoryChannel + broker MT) i scenariusz „mem dnia”. Ok. 2 min.
# Wersja Eventing = wersja Serving z setup/versions.env.
# Użycie: demo/04-eventing/prepare.sh [--delete]
set -euo pipefail
cd "$(dirname "$0")/../.."; source setup/versions.env
EV=https://github.com/knative/eventing/releases/download/${KNATIVE_VERSION}
if [ "${1:-}" = --delete ]; then
  kubectl delete -f demo/04-eventing/eventing.yaml --ignore-not-found
  kubectl delete -f "$EV/mt-channel-broker.yaml" -f "$EV/in-memory-channel.yaml" -f "$EV/eventing-core.yaml" --ignore-not-found
  kubectl delete -f "$EV/eventing-crds.yaml" --ignore-not-found
  exit
fi
kubectl apply -f "$EV/eventing-crds.yaml"
kubectl wait --for=condition=Established crd/brokers.eventing.knative.dev crd/triggers.eventing.knative.dev --timeout=60s
kubectl apply -f "$EV/eventing-core.yaml"
kubectl apply -f "$EV/in-memory-channel.yaml"
kubectl apply -f "$EV/mt-channel-broker.yaml"
kubectl -n knative-eventing wait --for=condition=Available deploy --all --timeout=300s
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/04-eventing/eventing.yaml
kubectl -n demo wait broker/default --for=condition=Ready --timeout=120s
kubectl -n demo wait ksvc/mem-dnia --for=condition=Ready --timeout=120s
echo "Gotowe. Logi funkcji: kubectl logs -n demo -l serving.knative.dev/service=mem-dnia -c user-container -f"
