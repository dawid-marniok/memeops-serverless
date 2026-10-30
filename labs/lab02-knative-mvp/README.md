# lab02 — MVP MemeOps na Knative

| Dzień | Czas | Po bloku |
|---|---|---|
| 1 | 45 min | 1.4 Knative: CLI, API, rewizje, cold start |

> **Zgłoszenie od PO:** „Wdrażamy MVP: mem tekstowy z adresu URL. Organizator chce nową wersję z emoji, ale tylko dla części ludzi, i chce móc wycofać ją w sekundę.”

**Cel:** wdrażasz usługę Knative z YAML i z `kn`, dzielisz ruch między rewizje, cofasz zmianę i mierzysz cold start.

**Zasada:** rewizja jest niezmienna. Nie „poprawiasz” wdrożenia — tworzysz nową rewizję i przesuwasz ruch.

## Kroki

| # | Co robisz | Czas |
|---|---|---|
| 1 | Wdrożenie z YAML | 7 min |
| 2 | Anatomia: co powstało | 8 min |
| 3 | v2 z emoji dla 20% ruchu | 10 min |
| 4 | Rollback i tag „kandydat” | 5 min |
| 5 | Pomiar cold startu | 15 min |

### 1. Wdrożenie z YAML

```bash
kubectl create namespace memeops
kubectl apply -f labs/lab02-knative-mvp/meme-api.yaml
kn service list -n memeops
curl "http://meme-api.memeops.127.0.0.1.sslip.io/?top=kiedy%20pod&bottom=wstaje%20z%20zera"
```

Ostrzeżenie `Kubernetes default value is insecure…` przy `apply` jest celowe — wrócimy do niego w LAB 6.

### 2. Anatomia: co powstało

```bash
kubectl get ksvc,configuration,revision,route -n memeops
kubectl get deploy,pods -n memeops
kubectl get pods -n memeops -o jsonpath='{.items[0].spec.containers[*].name}'; echo
```

Odpowiedz: ile kontenerów ma pod i po co jest drugi (`queue-proxy`)? Co się stanie z Deploymentem po ok. 90 s bez ruchu? Sprawdź `kubectl get pods -n memeops -w`.

### 3. v2 z emoji dla 20% ruchu

```bash
kn service update meme-api -n memeops \
  --image localhost:5001/meme-api:v2 --revision-name meme-api-v2 \
  --traffic meme-api-v1=80 --traffic meme-api-v2=20
kn revision list -n memeops
for i in $(seq 1 20); do curl -s http://meme-api.memeops.127.0.0.1.sslip.io/ | tail -1; done | cut -d'·' -f1 | sort | uniq -c
```

✅ ok. 16× `[v1` i 4× `[v2`. Porównaj `kubectl get ksvc meme-api -n memeops -o yaml` → sekcja `spec.traffic`: `kn` zrobił z tego zwykły YAML.

### 4. Rollback i tag „kandydat”

```bash
kn service update meme-api -n memeops --traffic meme-api-v1=100 --tag meme-api-v2=kandydat
curl -s http://meme-api.memeops.127.0.0.1.sslip.io/ | tail -1               # tylko v1
curl -s http://kandydat-meme-api.memeops.127.0.0.1.sslip.io/ | tail -1      # v2 nadal dostępna pod własnym adresem
```

Rollback nie wymagał nowego wdrożenia. Tag daje testerom dostęp do v2 bez ruchu produkcyjnego.

### 5. Pomiar cold startu

```bash
tools/coldstart.sh meme-api
```

Skrypt czeka, aż usługa zejdzie do zera podów (ok. 1–2 min), i mierzy pierwsze żądanie oraz trzy kolejne. Wpisz wyniki do tabeli — porównamy je w LAB 4:

| Pomiar | Zimny (ms) | Ciepły (ms) |
|---|---|---|
| meme-api v1 (lab02) | | |

Teraz ustaw minimum jednego poda i zmierz jeszcze raz:

```bash
kn service update meme-api -n memeops --scale-min 1
tools/coldstart.sh meme-api      # skrypt po 5 min się podda. Dlaczego? (możesz przerwać Ctrl+C)
kn service update meme-api -n memeops --scale-min 0
```

## SUKCES

- [ ] `kn revision list -n memeops` pokazuje `meme-api-v1` (100%) i `meme-api-v2` z tagiem `kandydat`
- [ ] masz w tabeli zmierzony cold start i ciepłe żądania
- [ ] umiesz wyjaśnić, kto odebrał pierwsze żądanie, gdy usługa miała zero podów

## Dla chętnych

- Zmień tylko zmienną środowiskową: `kn service update meme-api -n memeops --env GREETING="Witaj na konferencji"`. Ile rewizji przybyło i komu poszedł ruch? (Podpowiedź: ruch jest przypięty do nazw rewizji.)
- `kubectl get cm config-autoscaler -n knative-serving -o yaml | grep -A2 scale-to-zero` — które ustawienie skróci czekanie na zero?

## Dogoń grupę

Stan startowy labu = gotowa platforma z LAB 1 (`setup/check.sh`).

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `curl: Could not resolve host` | brak DNS do sslip.io: `curl -H "Host: meme-api.memeops.127.0.0.1.sslip.io" http://127.0.0.1/` |
| usługa `READY Unknown` dłużej niż minutę | `kubectl describe revision -n memeops` i `kubectl get pods -n memeops` |
| `ErrImagePull` | czy `setup/platform.sh` zbudował obrazy: `curl localhost:5001/v2/meme-api/tags/list` |
