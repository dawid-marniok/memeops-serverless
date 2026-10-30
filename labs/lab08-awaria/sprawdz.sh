#!/usr/bin/env bash
# LAB 8: czy meme-gen jest zdrowy po naprawie? Użycie: labs/lab08-awaria/sprawdz.sh
cd "$(dirname "$0")/../.."
NS=memeops; ok=0; all=0
check() { all=$((all + 1)); if eval "$2" >/dev/null 2>&1; then ok=$((ok + 1)); echo "✅ $1"; else echo "❌ $1"; fi; }
created=$(kubectl get ksvc meme-gen -n $NS -o jsonpath='{.status.latestCreatedRevisionName}')
ready=$(kubectl get ksvc meme-gen -n $NS -o jsonpath='{.status.latestReadyRevisionName}')
check "usługa meme-gen Ready" "kubectl get ksvc meme-gen -n $NS -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -qx True"
check "ostatnia utworzona rewizja ($created) = ostatnia gotowa ($ready)" "[ -n '$created' ] && [ '$created' = '$ready' ]"
export JWT_SECRET=$(kubectl -n $NS get secret meme-jwt -o jsonpath='{.data.JWT_SECRET}' | base64 -d)
TOKEN=$(tools/token.py sprawdzacz 5 2>/dev/null)
URL=$(kubectl get ksvc meme-gen -n $NS -o jsonpath='{.status.url}')
check "mem HD (scale 8) z tokenem → 201" "curl -sf -o /dev/null -XPOST $URL/api/memes -H 'Authorization: Bearer $TOKEN' -d '{\"top\":\"hd\",\"scale\":8}'"
check "bez tokenu → 401 (logowanie nadal działa)" "[ \"\$(curl -s -o /dev/null -w '%{http_code}' -XPOST $URL/api/memes -d '{}')\" = 401 ]"
echo; [ "$ok" = "$all" ] && echo "SUKCES: $ok/$all" || { echo "WYNIK: $ok/$all"; exit 1; }
