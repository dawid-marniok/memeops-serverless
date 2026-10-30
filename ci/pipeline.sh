#!/usr/bin/env bash
# Pipeline MemeOps uruchamiany lokalnie: test → build → skan → push → deploy (canary).
# Te same etapy są w ci/github-actions.yml i ci/azure-pipelines.yml (wzorce na prawdziwy CI).
#
# Użycie: ci/pipeline.sh <wersja> [procent ruchu dla nowej rewizji=10] [THEME=light|dark]
#   ci/pipeline.sh 2.2.0 10 dark     # nowa rewizja z ciemnym motywem dostaje 10% ruchu i tag "canary"
set -euo pipefail
cd "$(dirname "$0")/.."; source setup/versions.env
VERSION=${1:?podaj wersję, np. 2.2.0}; PERCENT=${2:-10}; THEME=${3:-light}
APP=app/meme-gen; NS=memeops
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
IMAGE="localhost:${REGISTRY_PORT}/meme-gen:${VERSION}"
stage() { printf '\n\033[1;35m[%s] %s\033[0m\n' "$1" "$2"; }

stage 1/5 "test (pytest w kontenerze, ta sama wersja Pythona co obraz)"
docker run --rm -v "$PWD/$APP:/src:ro" -w /src python:3.12-slim \
  sh -c "pip install -q --root-user-action=ignore pytest -r requirements.txt && python -m pytest -q -p no:cacheprovider"

stage 2/5 "build ${IMAGE} (+ tag ${SHA})"
docker build -q -f "$APP/Dockerfile.slim" -t "$IMAGE" -t "localhost:${REGISTRY_PORT}/meme-gen:${SHA}" \
  --label "org.opencontainers.image.revision=${SHA}" "$APP"

stage 3/5 "skan Trivy ${TRIVY_VERSION}: HIGH/CRITICAL z dostępną poprawką przerywają pipeline"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
docker save "$IMAGE" -o "$TMP/image.tar"
docker run --rm -v "$TMP:/scan:ro" -v memeops-trivy-cache:/root/.cache "aquasec/trivy:${TRIVY_VERSION}" \
  image --quiet --input /scan/image.tar --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1

stage 4/5 "push"
docker push -q "$IMAGE"; docker push -q "localhost:${REGISTRY_PORT}/meme-gen:${SHA}"

stage 5/5 "deploy: nowa rewizja dostaje ${PERCENT}% ruchu (tag canary)"
CURRENT=$(kubectl get ksvc meme-gen -n "$NS" -o jsonpath='{.status.latestReadyRevisionName}')
REV="meme-gen-$(echo "$VERSION" | tr . -)"
# Jedna zmiana: nowa rewizja + przypięcie obecnej. Bez --traffic nowa rewizja dostałaby od razu 100%.
kn service update meme-gen -n "$NS" --image "$IMAGE" --revision-name "$REV" \
  --env APP_VERSION="$VERSION" --env THEME="$THEME" --annotation-revision "memeops/git-sha=${SHA}" \
  --traffic "$CURRENT=$((100 - PERCENT))" --traffic "@latest=$PERCENT" --tag "@latest=canary"
kn revision list -n "$NS" -s meme-gen | head -4
echo; echo "Canary: $(kubectl get ksvc meme-gen -n $NS -o jsonpath='{.status.traffic[?(@.tag=="canary")].url}')"
echo "Promocja: kn service update meme-gen -n $NS --traffic $REV=100   Wycofanie: --traffic $CURRENT=100"
