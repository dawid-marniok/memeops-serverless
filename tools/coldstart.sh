#!/usr/bin/env bash
# Mierzy cold start usługi Knative: czeka, aż usługa zejdzie do zera podów, i mierzy pierwsze żądanie,
# potem kilka ciepłych dla porównania.
# Użycie: tools/coldstart.sh <usługa> [namespace=memeops] [ścieżka=/] [metoda=GET] [dane JSON]
#   tools/coldstart.sh meme-api
#   tools/coldstart.sh meme-gen memeops /api/memes POST '{"top":"zimny","bottom":"start"}'
#   NOWY_WEZEL=1 tools/coldstart.sh meme-gen ...   # po zejściu do zera usuń obraz z węzła (jak nowy węzeł bez cache)
set -euo pipefail
SVC=${1:?podaj nazwę usługi}; NS=${2:-memeops}; P=${3:-/}; M=${4:-GET}; DATA=${5:-}
URL=$(kubectl get ksvc "$SVC" -n "$NS" -o jsonpath='{.status.url}')
args=(-s -o /dev/null -w '%{http_code} %{time_total}' -X "$M")
[ -n "$DATA" ] && args+=(-H 'Content-Type: application/json' -d "$DATA")
[ -n "${TOKEN:-}" ] && args+=(-H "Authorization: Bearer $TOKEN")
REV=$(kubectl get ksvc "$SVC" -n "$NS" -o jsonpath='{.status.latestReadyRevisionName}')
printf 'Czekam, aż rewizja %s zejdzie do zera podów (maks. 5 min)' "$REV"
for _ in $(seq 1 60); do
  n=$(kubectl get pods -n "$NS" -l "serving.knative.dev/revision=$REV" --no-headers 2>/dev/null | grep -vc Terminating || true)
  [ "$n" = 0 ] && break; printf '.'; sleep 5
done
[ "$n" = 0 ] || { echo; echo "Rewizja nadal ma pody. Czy ktoś wysyła ruch albo ustawiony jest min-scale?" >&2; exit 1; }
echo " 0 podów."
if [ -n "${NOWY_WEZEL:-}" ]; then
  IMG=$(kubectl get revision -n "$NS" "$REV" -o jsonpath='{.spec.containers[0].image}')
  docker exec memeops-control-plane crictl rmi "$IMG" >/dev/null && echo "Usunięty z węzła: $IMG"
fi
measure() { local out; out=$(curl "${args[@]}" "$URL$P"); code=${out% *}; ms=$(awk "BEGIN{printf \"%.0f\", ${out#* } * 1000}"); }
measure
printf 'ZIMNY start: HTTP %s, %6s ms\n' "$code" "$ms"
for i in 1 2 3; do
  measure
  printf 'ciepły #%s:   HTTP %s, %6s ms\n' "$i" "$code" "$ms"
done
