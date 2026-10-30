#!/usr/bin/env bash
# Sprawdza stanowisko MemeOps. Każdy ❌ ma podpowiedź, co zrobić.
# Użycie: setup/check.sh
cd "$(dirname "$0")/.."
source setup/versions.env
ok=0; all=0
check() {  # check "opis" "podpowiedź" komenda...
  local desc=$1 hint=$2; shift 2; all=$((all + 1))
  if "$@" >/dev/null 2>&1; then ok=$((ok + 1)); printf '✅ %s\n' "$desc"
  else printf '❌ %s\n   → %s\n' "$desc" "$hint"; fi
}
for t in docker kind kubectl kn helm k6; do
  check "narzędzie: $t" "setup/install-tools.sh" command -v "$t"
done
check "Docker działa" "sudo systemctl start docker; użytkownik w grupie docker (newgrp docker)" docker info
check "rejestr localhost:${REGISTRY_PORT}" "setup/platform.sh" curl -sf "http://localhost:${REGISTRY_PORT}/v2/"
check "kontekst kubectl = kind-${CLUSTER_NAME}" "kubectl config use-context kind-${CLUSTER_NAME}" \
  test "$(kubectl config current-context 2>/dev/null)" = "kind-${CLUSTER_NAME}"
check "Knative Serving: wszystkie Deploymenty Available" "kubectl -n knative-serving get pods" \
  kubectl -n knative-serving wait --for=condition=Available deploy --all --timeout=5s
check "Kourier odpowiada na 127.0.0.1:${HTTP_PORT}" "kubectl -n kourier-system get pods,svc" \
  sh -c "curl -s -o /dev/null -w '%{http_code}' -H 'Host: nic.default.127.0.0.1.sslip.io' http://127.0.0.1:${HTTP_PORT} | grep -q 404"
check "DNS: *.127.0.0.1.sslip.io → 127.0.0.1" "brak DNS do sslip.io: używaj curl -H 'Host: …' http://127.0.0.1 (setup/README.md)" \
  sh -c "getent hosts test.default.127.0.0.1.sslip.io 2>/dev/null | grep -q 127.0.0.1 || dscacheutil -q host -a name test.default.127.0.0.1.sslip.io 2>/dev/null | grep -q 127.0.0.1"
check "obraz meme-api:v1 w rejestrze" "setup/platform.sh" \
  sh -c "curl -sf http://localhost:${REGISTRY_PORT}/v2/meme-api/tags/list | grep -q v1"
echo
if [ "$ok" = "$all" ]; then echo "SUKCES: $ok/$all"; else echo "WYNIK: $ok/$all"; exit 1; fi
