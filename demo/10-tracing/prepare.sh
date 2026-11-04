#!/usr/bin/env bash
# Demo 10: OTel Collector + Tempo na klastrze memeops, tracing w Knative włączony. Ok. 2 min.
# Wymaga platformy z --monitoring (Grafana z kube-prometheus-stack).
# Użycie: demo/10-tracing/prepare.sh [--delete]
set -euo pipefail
cd "$(dirname "$0")"
K="kubectl --context kind-memeops"
if [ "${1:-}" = --delete ]; then
  $K delete -f function.yaml -f tracing.yaml --ignore-not-found
  $K patch configmap/config-observability -n knative-serving --type json -p '[
    {"op":"remove","path":"/data/tracing-protocol"},{"op":"remove","path":"/data/tracing-endpoint"},
    {"op":"remove","path":"/data/tracing-sampling-rate"}]' || true
  $K -n knative-serving rollout restart deploy/activator
  exit
fi
$K get ns monitoring >/dev/null 2>&1 || { echo "Brak Grafany: uruchom setup/platform.sh --monitoring" >&2; exit 1; }
$K apply -f tracing.yaml
$K -n observability rollout status deploy/tempo deploy/otel-collector --timeout=180s
# Od 1.18 tracing w Knative to OTLP, domyślnie wyłączony (tracing-protocol: none).
# Sampling 1 = każde żądanie; na produkcji 0.01–0.1.
$K patch configmap/config-observability -n knative-serving --type merge -p '{"data":{
  "tracing-protocol":"http/protobuf",
  "tracing-endpoint":"http://otel-collector.observability:4318/v1/traces",
  "tracing-sampling-rate":"1"}}'
# activator czyta konfigurację przy starcie; queue-proxy dostaje ją przy tworzeniu poda rewizji
$K -n knative-serving rollout restart deploy/activator
$K -n knative-serving rollout status deploy/activator --timeout=120s
# funkcja dopiero teraz: jej queue-proxy startuje już z konfiguracją tracingu
$K apply -f ../00-namespace.yaml -f function.yaml
$K -n demo wait ksvc/meme-trace --for=condition=Ready --timeout=120s
echo "Gotowe. Funkcja: http://meme-trace.demo.127.0.0.1.sslip.io  Grafana → Explore → Tempo"
