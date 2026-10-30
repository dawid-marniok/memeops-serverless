#!/usr/bin/env bash
# Platforma MemeOps na lokalnym klastrze kind: rejestr obrazów, Knative Serving + Kourier, obrazy meme-api.
# LAB 1 krok 2. Skrypt jest idempotentny: można go uruchomić ponownie.
#
# Użycie: setup/platform.sh [--monitoring] [--cert-manager] [--bez-obrazow]
#   --monitoring    kube-prometheus-stack (Prometheus + Grafana) — LAB 5 i LAB 8, wymaga ok. 2 GB RAM więcej
#   --cert-manager  cert-manager + integracja z Knative (TLS w LAB 6)
#   --bez-obrazow   nie buduj obrazów meme-api (np. przy ponownym uruchomieniu)
set -euo pipefail
cd "$(dirname "$0")/.."
source setup/versions.env
MON=0; CM=0; IMAGES=1
for a in "$@"; do
  case $a in
    --monitoring) MON=1 ;; --cert-manager) CM=1 ;; --bez-obrazow) IMAGES=0 ;;
    *) echo "Nieznana opcja: $a" >&2; exit 1 ;;
  esac
done
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
KN=https://github.com/knative

step "1/6 Rejestr obrazów localhost:${REGISTRY_PORT}"
if [ "$(docker inspect -f '{{.State.Running}}' "$REGISTRY_NAME" 2>/dev/null || true)" != 'true' ]; then
  docker run -d --restart=always -p "127.0.0.1:${REGISTRY_PORT}:5000" --network bridge --name "$REGISTRY_NAME" registry:2
fi

step "2/6 Klaster kind '${CLUSTER_NAME}' (port ${HTTP_PORT} na hoście → Kourier)"
if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  cat <<YAML | kind create cluster --name "$CLUSTER_NAME" --image "$KIND_NODE_IMAGE" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 31080
    hostPort: ${HTTP_PORT}
    listenAddress: "127.0.0.1"
  - containerPort: 31443
    hostPort: 443
    listenAddress: "127.0.0.1"
  - containerPort: 30300
    hostPort: ${GRAFANA_PORT}
    listenAddress: "127.0.0.1"
YAML
fi
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
# localhost:5001 w podach = kontener rejestru w sieci kind
for node in $(kind get nodes --name "$CLUSTER_NAME"); do
  docker exec "$node" mkdir -p "/etc/containerd/certs.d/localhost:${REGISTRY_PORT}"
  printf '[host."http://%s:5000"]\n' "$REGISTRY_NAME" | docker exec -i "$node" cp /dev/stdin "/etc/containerd/certs.d/localhost:${REGISTRY_PORT}/hosts.toml"
done
docker network connect kind "$REGISTRY_NAME" 2>/dev/null || true
kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ConfigMap
metadata: {name: local-registry-hosting, namespace: kube-public}
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
YAML

step "3/6 Knative Serving ${KNATIVE_VERSION}"
kubectl apply -f "$KN/serving/releases/download/${KNATIVE_VERSION}/serving-crds.yaml"
kubectl wait --for=condition=Established crd/services.serving.knative.dev --timeout=60s
kubectl apply -f "$KN/serving/releases/download/${KNATIVE_VERSION}/serving-core.yaml"

step "4/6 Kourier (ingress) + domena 127.0.0.1.sslip.io"
kubectl apply -f "https://github.com/knative-extensions/net-kourier/releases/download/${KNATIVE_VERSION}/kourier.yaml"
kubectl patch configmap/config-network -n knative-serving --type merge \
  -p '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
kubectl patch configmap/config-domain -n knative-serving --type merge -p '{"data":{"127.0.0.1.sslip.io":""}}'
# Kontroler Knative nie widzi localhost:5001 (to adres hosta) — nie rozwiązuj tagów na digest dla tego rejestru
kubectl patch configmap/config-deployment -n knative-serving --type merge \
  -p "{\"data\":{\"registries-skipping-tag-resolving\":\"kind.local,ko.local,dev.local,localhost:${REGISTRY_PORT}\"}}"
# Metryki w formacie Prometheusa (od 1.18 Knative używa OpenTelemetry, domyślnie eksport wyłączony: none)
kubectl patch configmap/config-observability -n knative-serving --type merge \
  -p '{"data":{"metrics-protocol":"prometheus","request-metrics-protocol":"prometheus"}}'
kubectl -n knative-serving rollout restart deploy/autoscaler deploy/activator
kubectl -n kourier-system wait --for=condition=Available deploy/3scale-kourier-gateway --timeout=180s
kubectl patch svc kourier -n kourier-system --type merge -p '{"spec":{"type":"NodePort","ports":[
  {"name":"http2","port":80,"protocol":"TCP","targetPort":8080,"nodePort":31080},
  {"name":"https","port":443,"protocol":"TCP","targetPort":8443,"nodePort":31443}]}}'
kubectl -n knative-serving wait --for=condition=Available deploy --all --timeout=300s

if [ "$CM" = 1 ]; then
  # Od Knative 1.15 integracja z cert-managerem jest w serving-core (ConfigMap config-certmanager),
  # osobny net-certmanager nie jest już potrzebny. Konfiguracja TLS: labs/lab06 (dla chętnych).
  step "cert-manager ${CERT_MANAGER_VERSION}"
  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
  kubectl -n cert-manager wait --for=condition=Available deploy --all --timeout=300s
  # kontroler Knative włącza obsługę cert-managera tylko, gdy przy starcie widzi jego CRD — restart
  kubectl -n knative-serving rollout restart deploy/controller
  kubectl -n knative-serving rollout status deploy/controller --timeout=120s
fi

if [ "$MON" = 1 ]; then
  step "kube-prometheus-stack ${KPS_CHART_VERSION} (Grafana: http://localhost:${GRAFANA_PORT}, admin/memeops)"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update prometheus-community >/dev/null
  helm upgrade --install kps prometheus-community/kube-prometheus-stack --version "$KPS_CHART_VERSION" \
    -n monitoring --create-namespace -f setup/monitoring-values.yaml --wait --timeout 10m
  kubectl apply -f setup/monitoring-knative.yaml
fi

step "5/6 Obrazy meme-api v1 i v2 → localhost:${REGISTRY_PORT}"
if [ "$IMAGES" = 1 ]; then
  for v in v1 v2; do
    docker build -q -t "localhost:${REGISTRY_PORT}/meme-api:$v" --build-arg VERSION=$v app/meme-api
    docker push -q "localhost:${REGISTRY_PORT}/meme-api:$v"
  done
fi

step "6/6 Sprawdzenie"
setup/check.sh
