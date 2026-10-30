#!/usr/bin/env bash
# „Dogoń grupę”: doprowadza klaster do stanu startowego wskazanego labu (= rozwiązanie poprzedniego).
# Usuwa i tworzy od nowa usługi Knative, więc tracisz własne rewizje — Twoje pliki w repo zostają.
# Użycie: tools/dogon.sh lab03|lab04|lab05|lab06|lab07|lab08
set -euo pipefail
cd "$(dirname "$0")/.."; source setup/versions.env
LAB=${1:?podaj lab, np. lab05}; N=${LAB#lab}; N=$((10#$N))
R="localhost:${REGISTRY_PORT}"; NS=memeops
kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f - >/dev/null
build() {  # build <tag> <wersja pillow albo "">
  local tmp; tmp=$(mktemp -d); cp -r app/meme-gen/. "$tmp"
  if [ -n "$2" ]; then echo "pillow==$2" > "$tmp/requirements.txt"; else : > "$tmp/requirements.txt"; fi
  docker build -q -f "$tmp/Dockerfile.slim" -t "$R/meme-gen:$1" "$tmp" >/dev/null && docker push -q "$R/meme-gen:$1" >/dev/null
  rm -rf "$tmp"; echo "obraz $R/meme-gen:$1"
}
fresh() { kubectl delete ksvc "$1" -n $NS --ignore-not-found >/dev/null; }
if [ "$N" -ge 3 ]; then fresh meme-api; kubectl apply -f labs/lab02-knative-mvp/meme-api.yaml >/dev/null; fi
if [ "$N" -ge 4 ]; then
  build 1.0.0 ""; fresh meme-gen
  sed 's/"UZUPELNIJ"/"dogon"/' labs/lab03-funkcja-python/meme-gen.yaml | kubectl apply -f - >/dev/null
fi
if [ "$N" -ge 5 ]; then
  build 2.0.0 12.3.0; fresh meme-gen
  sed 's/"UZUPELNIJ"/"dogon"/; s/meme-gen:1.0.0/meme-gen:2.0.0/; s/value: "1.0.0"/value: "2.0.0"/; s/value: svg/value: png/; s/memory: 128Mi/memory: 256Mi/' \
    labs/lab03-funkcja-python/meme-gen.yaml | kubectl apply -f - >/dev/null
fi
if [ "$N" -ge 6 ]; then fresh meme-gen; kubectl apply -f labs/lab05-keynote/autoscaling.yaml >/dev/null; fi
if [ "$N" -ge 7 ]; then
  kubectl get secret meme-jwt -n $NS >/dev/null 2>&1 || \
    kubectl create secret generic meme-jwt -n $NS --from-literal=JWT_SECRET="$(openssl rand -hex 32)" >/dev/null
  fresh meme-gen; kubectl apply -f labs/lab06-sekrety/konfiguracja.yaml -f labs/lab06-sekrety/meme-gen.yaml >/dev/null
fi
if [ "$N" -ge 8 ]; then
  build 2.2.0 13.0.0; fresh meme-gen
  sed 's/meme-gen:2.0.0/meme-gen:2.2.0/; s/value: "2.1.0"/value: "2.2.0"/' labs/lab06-sekrety/meme-gen.yaml | kubectl apply -f - >/dev/null
fi
kubectl wait ksvc --all -n $NS --for=condition=Ready --timeout=180s
echo "Gotowe: możesz zaczynać $LAB."
