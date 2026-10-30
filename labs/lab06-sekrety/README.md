# lab06 — Sekrety, konfiguracja i logowanie

| Dzień | Czas | Po bloku |
|---|---|---|
| 2 | 50 min | 2.2 Sekrety, TLS i uwierzytelnianie |

> **Zgłoszenie od PO:** „Ktoś wrzuca memy anonimowo. Od teraz tylko uczestnicy z tokenem konferencji tworzą memy, galeria zostaje publiczna. I chcemy znak wodny konferencji bez budowania nowego obrazu.”

**Cel:** przenosisz konfigurację do ConfigMap, klucz podpisu tokenów do Secretu, zabezpieczasz kontekst kontenera i (dla chętnych) włączasz HTTPS.

**Zasada:** obraz jest ten sam na każdym środowisku — różni się tylko konfiguracja.

## Kroki

| # | Co robisz | Czas |
|---|---|---|
| 1 | Secret z kluczem JWT | 5 min |
| 2 | ConfigMap + usługa z sekretem | 10 min |
| 3 | Test: bez tokenu i z tokenem | 10 min |
| 4 | Co widzi każdy, kto ma dostęp do namespace'u | 10 min |
| 5 | Zmiana ConfigMap — pułapka | 10 min |
| 6 | Dla chętnych: HTTPS | 15 min |

### 1. Secret z kluczem JWT

```bash
kubectl -n memeops create secret generic meme-jwt --from-literal=JWT_SECRET="$(openssl rand -hex 32)"
```

Klucz nie trafia do repo ani do historii poleceń w postaci jawnej. Plik `konfiguracja.yaml` zawiera tylko ConfigMap — dlaczego nie Secret?

### 2. ConfigMap + usługa z sekretem

```bash
kubectl apply -f labs/lab06-sekrety/konfiguracja.yaml
kubectl apply -f labs/lab06-sekrety/meme-gen.yaml
```

Przeczytaj `meme-gen.yaml`: `secretKeyRef`, `envFrom`, `securityContext`. Ostrzeżenie `Kubernetes default value is insecure` z LAB 2 zniknęło — dlaczego?

### 3. Test: bez tokenu i z tokenem

```bash
U=http://meme-gen.memeops.127.0.0.1.sslip.io
curl -s -XPOST $U/api/memes -d '{"top":"anonim"}' -w ' → %{http_code}\n'
export JWT_SECRET=$(kubectl -n memeops get secret meme-jwt -o jsonpath='{.data.JWT_SECRET}' | base64 -d)
TOKEN=$(tools/token.py ania 120)
curl -s -XPOST $U/api/memes -H "Authorization: Bearer $TOKEN" -d '{"top":"z tokenem"}' -w ' → %{http_code}\n'
curl -s $U/api/memes        # galeria bez tokenu
```

✅ `401` bez tokenu, `201` z tokenem, galeria działa bez tokenu. Wklej token w polu na stronie i wygeneruj mema w przeglądarce — znak wodny `#MemeOpsConf 2026` jest z ConfigMap.

Uruchom keynote z tokenem: `k6 run -e TOKEN=$TOKEN tools/keynote.js` (wystarczy 30 s, potem Ctrl+C).

### 4. Co widzi każdy, kto ma dostęp do namespace'u

```bash
kubectl get secret meme-jwt -n memeops -o yaml          # base64 to nie szyfrowanie
kubectl get revision -n memeops -o yaml | grep -A3 JWT  # w rewizji jest tylko referencja
```

Zastanów się: kto w Twojej firmie ma `get secret` w namespace'ach produkcyjnych? Jak zmienia to External Secrets Operator z Vaultem (slajd)?

### 5. Zmiana ConfigMap — pułapka

```bash
kubectl patch cm meme-config -n memeops --type merge -p '{"data":{"WATERMARK":"#NowyZnak"}}'
```

Wygeneruj mema. Znak wodny się zmienił? Sprawdź `kn revision list -n memeops -s meme-gen` — czy powstała nowa rewizja? Jak wymusić nową rewizję, żeby zmiana była wersjonowana i dała się cofnąć? (Podpowiedź: coś w `spec.template` musi się zmienić, np. adnotacja z wersją konfiguracji.)

### 6. Dla chętnych: HTTPS

```bash
setup/platform.sh --cert-manager --bez-obrazow
kubectl apply -f labs/lab06-sekrety/tls.yaml
kubectl patch cm config-certmanager -n knative-serving --type merge \
  -p '{"data":{"issuerRef":"kind: ClusterIssuer\nname: memeops-ca\n"}}'
kubectl patch cm config-network -n knative-serving --type merge \
  -p '{"data":{"external-domain-tls":"Enabled","http-protocol":"Redirected"}}'
kn service list -n memeops          # adresy https://, po ok. 30 s READY True
kubectl -n cert-manager get secret memeops-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/memeops-ca.crt
curl --cacert /tmp/memeops-ca.crt https://meme-gen.memeops.127.0.0.1.sslip.io/api/info
curl -sI http://meme-gen.memeops.127.0.0.1.sslip.io/ | head -2     # 301 → https
```

**Wyłącz HTTPS przed LAB 7** (k6 i skrypty używają http):

```bash
kubectl patch cm config-network -n knative-serving --type merge \
  -p '{"data":{"external-domain-tls":"Disabled","http-protocol":"Enabled"}}'
```

## SUKCES

- [ ] POST bez tokenu → `401`, z tokenem → `201`, galeria bez tokenu → `200`
- [ ] w YAML usługi nie ma klucza, jest tylko `secretKeyRef`
- [ ] umiesz wyjaśnić, dlaczego zmiana ConfigMap nie utworzyła nowej rewizji i jak to obejść

## Dla chętnych

- Zmień `meme-gen` na obraz `2.0.0-full` z LAB 4. Dlaczego rewizja nie wstaje (`kubectl describe pod`)? Co mówi to o tym obrazie?
- Funkcja tylko wewnątrz klastra: etykieta `networking.knative.dev/visibility=cluster-local` na usłudze `meme-api`. Jaki adres dostaje i czy `curl` z VM działa?

## Dogoń grupę

```bash
tools/dogon.sh lab06
```

**Cliffhanger:** „Każda zmiana szablonu to ręczny `kn service update`. Tak nie da się pracować.”
