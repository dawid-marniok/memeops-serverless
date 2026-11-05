# lab09 — Obserwowalność: metryki, trace'y, alert

> **Zgłoszenie od PO:** „Organizator pyta trzy rzeczy: ile memów zrobiliśmy w czasie keynote, czemu pierwsza osoba czekała prawie 2 sekundy i skąd się dowiemy o awarii, zanim on do nas zadzwoni. Odpowiedzcie liczbami, nie «chyba działa».”

**Cel:** czytasz metryki Knative w Prometheusie, dodajesz do `meme-gen` tracing OpenTelemetry i oglądasz cały trace w Tempo (od activatora do renderowania mema), a na koniec ustawiasz w Grafanie alert i przechodzisz pełną pętlę: alert → trace → log → przyczyna.

**Zasada:** metryki mówią, **że** coś się dzieje. Trace mówi, **gdzie** idzie czas. Log z `trace_id` mówi, **dlaczego**.

```
            ┌── metryki (pull co 5 s) ──→ Prometheus ──┐
queue-proxy ┤                                          ├──→ Grafana (dashboard, Explore, alert)
activator ──┴── spany OTLP ──→ OTel Collector → Tempo ─┘
meme-gen ────── spany OTLP ──↗   (od kroku 5)
```

## Przed startem

Wymaga platformy z `--monitoring` (Grafana http://localhost:3000, `admin`/`memeops`). Stan startowy: zdrowy `meme-gen` 2.2.0 z JWT (koniec LAB 8).

```bash
tools/start-lab.sh lab09            # tylko jeśli LAB 8 nie skończony albo coś zostało zepsute
export JWT_SECRET=$(kubectl -n memeops get secret meme-jwt -o jsonpath='{.data.JWT_SECRET}' | base64 -d)
export TOKEN=$(tools/token.py test 180)
URL=http://meme-gen.memeops.127.0.0.1.sslip.io/api/memes
```

Przy każdym nowym terminalu powtórz trzy linie `export`/`URL`.

| # | Co robisz | Min |
|---|---|---|
| A | Metryki: skąd się biorą, PromQL, zagadka licznika | 15 |
| B | Trace'y: tracing w Knative i w kodzie funkcji, cold vs warm | 25 |
| C | Alert w Grafanie i pętla diagnozy na awarii | 15 |

## A. Metryki

### 1. Skąd Prometheus bierze metryki

```bash
kubectl get podmonitor -n monitoring
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090   # drugi terminal (File → Open Tab)
```

Otwórz http://localhost:9090 → **Status → Target health** → `knative-queue-proxy`. Zobaczysz targety tylko wtedy, gdy funkcja ma działający pod. Wyślij jedno żądanie i odśwież stronę.

👀 Metryki żądań zbiera **queue-proxy** (sidecar w każdym podzie funkcji, port 9091), nie Twój kod. Aplikacja nie musi nic eksportować, żeby mieć liczbę żądań, kody i czasy.

Port-forward zostaw do końca części A. Zamkniesz go, zamykając kartę terminala.

### 2. Ruch

```bash
k6 run -e TOKEN=$TOKEN tools/keynote.js
```

Test trwa ok. 2 min. W tym czasie otwórz Grafanę → **Explore** → źródło **Prometheus** → tryb **Code**.

### 3. PromQL: cztery pytania organizatora

Pierwsze zapytanie jest gotowe, pozostałe napisz sam (podpowiedzi pod tabelą).

| # | Pytanie | Zapytanie | Twój wynik |
|---|---|---|---|
| 1 | Ile żądań na sekundę, z jakim kodem? | `sum by (http_response_status_code) (rate(http_server_request_duration_seconds_count{namespace="memeops", service="meme-gen"}[1m]))` | |
| 2 | Jaki odsetek żądań kończy się 5xx? | | |
| 3 | Ile czekała najwolniejsza co dwudziesta osoba (p95)? | | |
| 4 | Ile podów było najwięcej? | | |

Podpowiedzi:
- 2: podziel zapytanie 1 z filtrem `http_response_status_code=~"5.."` przez to samo bez filtra. Dlaczego 401 (brak tokenu) nie powinien się tu liczyć? Gdy nie było ani jednego 5xx, dostaniesz *No data*, a nie 0. Dlaczego? (Naprawa: `… or vector(0)`.)
- 3: `histogram_quantile(0.95, sum by (le) (rate(…_bucket{…}[1m])))`. Wynik jest w sekundach.
- 4: metryka autoskalera `kn_revision_pods_count{kn_service_name="meme-gen"}`, funkcja `max_over_time(…[15m])`.

### 4. Zagadka licznika: ile memów zrobiliśmy?

Poczekaj, aż `meme-gen` zejdzie do zera (`kubectl get pods -n memeops -l serving.knative.dev/service=meme-gen`: pusto), i wyślij dokładnie 20 memów:

```bash
for i in $(seq 1 20); do curl -s -o /dev/null -w '%{http_code} ' -XPOST $URL -H "Authorization: Bearer $TOKEN" -d '{"top":"licz mnie"}'; done; echo
```

Po 30 s porównaj w Explore:

```
sum(increase(http_server_request_duration_seconds_count{namespace="memeops", service="meme-gen", http_response_status_code="201"}[5m]))
sum(max_over_time(http_server_request_duration_seconds_count{namespace="memeops", service="meme-gen", http_response_status_code="201"}[5m]))
```

❓ Które zapytanie mówi prawdę i dlaczego drugie się myli? Podpowiedź: w Prometheusie (http://localhost:9090, zakładka **Table**) wykonaj `http_server_request_duration_seconds_count{namespace="memeops", service="meme-gen"}[5m]` i spójrz na pierwszą próbkę serii. Co to oznacza dla raportu „ile memów zrobiliśmy w czasie keynote” w świecie scale-to-zero?

## B. Trace'y

### 5. Tracing w Knative

Te same kroki prowadzący pokazywał w [demie 10](../../demo/10-tracing/). Tu robisz je u siebie.

```bash
kubectl apply -f demo/10-tracing/tracing.yaml
kubectl -n observability rollout status deploy/tempo deploy/otel-collector
kubectl patch configmap config-observability -n knative-serving --type merge -p '{"data":{
  "tracing-protocol":"http/protobuf",
  "tracing-endpoint":"http://otel-collector.observability:4318/v1/traces",
  "tracing-sampling-rate":"1"}}'
kubectl -n knative-serving rollout restart deploy/activator
kubectl -n knative-serving rollout status deploy/activator
```

Po tym kroku spany wysyłają activator i queue-proxy (to drugie w podach utworzonych od teraz). Ale w kodzie `meme-gen` trace się urywa: nie wiesz, ile trwało samo renderowanie.

### 6. Tracing w kodzie funkcji

Moduł `tracing.py` jest gotowy (przeczytaj docstringi, to 70 linii). Bez pakietów OpenTelemetry albo bez zmiennej `OTEL_EXPORTER_OTLP_ENDPOINT` nic nie robi, więc testy i lokalne uruchomienie działają jak wcześniej.

```bash
cp labs/lab09-obserwowalnosc/tracing.py app/meme-gen/
cat >> app/meme-gen/requirements.txt <<'EOF'
opentelemetry-sdk==1.45.2
opentelemetry-exporter-otlp-proto-http==1.45.2
EOF
cat app/meme-gen/requirements.txt     # Pillow (13.0.0 po LAB 7) + dwa pakiety OTel
```

W `app/meme-gen/main.py` zrób trzy zmiany.

**a)** Import obok `import memes`:

```python
import tracing
```

**b)** W `_create` owiń renderowanie spanem `render` z atrybutami (po nich wyszukasz trace w Tempo):

```python
        with tracing.span("render", format=CONFIG["format"], scale=scale):
            ctype, body = memes.render(
                ...  # bez zmian, tylko wcięcie o 4 spacje
            )
```

**c)** Zastąp całe ciało `_handle` wersją ze spanem żądania i `trace_id` w logu:

```python
    def _handle(self):
        t0, self._status, self._user = time.time(), 500, None
        path = self.path.split("?", 1)[0]
        with tracing.request_span(self.command, path, self.headers) as span:
            try:
                self._route()
            except Exception as e:  # noqa: BLE001 — każdy błąd ma trafić do logu jako JSON
                log(level="error", path=self.path, error=repr(e), trace_id=tracing.trace_id())
                if self._status == 500:
                    self._send(500, {"error": "błąd serwera"})
            finally:
                tracing.set_status(span, self._status)
                if path != "/healthz":
                    log(method=self.command, path=path, status=self._status,
                        ms=round((time.time() - t0) * 1000, 1), user=self._user, trace_id=tracing.trace_id())
```

`request_span` czyta nagłówek `traceparent`, który ustawia queue-proxy. Dzięki temu span aplikacji staje się dzieckiem spanu Knative, a nie osobnym trace'em.

Testy (bez pakietów OTel — sprawdzasz, że wyłączony tracing niczego nie psuje):

```bash
docker run --rm -v "$PWD/app/meme-gen:/src:ro" -w /src python:3.12-slim \
  sh -c "pip install -q pytest \$(grep -i "^pillow" requirements.txt) && python -m pytest -q -p no:cacheprovider"
```

Build i wdrożenie (`2.3.0` zajęła awaria z LAB 8, dlatego `2.4.0`):

```bash
docker build -f app/meme-gen/Dockerfile.slim -t localhost:5001/meme-gen:2.4.0 app/meme-gen
docker push localhost:5001/meme-gen:2.4.0
kubectl apply -f labs/lab09-obserwowalnosc/meme-gen.yaml
kubectl wait ksvc/meme-gen -n memeops --for=condition=Ready
```

👀 W `meme-gen.yaml` porównaj z LAB 6: trzy zmienne `OTEL_*`. Adres Collectora i nazwa usługi to konfiguracja, nie kod.

### 7. Cold i warm, mały i HD

Poczekaj, aż funkcja zejdzie do zera, i wyślij trzy żądania:

```bash
curl -s -o /dev/null -w 'cold HD:   %{time_total} s\n' -XPOST $URL -H "Authorization: Bearer $TOKEN" -d '{"top":"cold","scale":8}'
curl -s -o /dev/null -w 'warm HD:   %{time_total} s\n' -XPOST $URL -H "Authorization: Bearer $TOKEN" -d '{"top":"warm","scale":8}'
curl -s -o /dev/null -w 'warm mały: %{time_total} s\n' -XPOST $URL -H "Authorization: Bearer $TOKEN" -d '{"top":"warm","scale":1}'
```

Grafana → **Explore** → źródło **Tempo** → zakładka **TraceQL**. Nowe trace'y pojawiają się po ok. 1 min.

```
{ name = "render" && span.scale = 8 }
```

Otwórz dłuższy z dwóch trace'ów i wypełnij:

| Żądanie | Całość | `throttler_try` (czekanie na pod) | `render` | Reszta (sieć, proxy) |
|---|---|---|---|---|
| cold HD | | | | |
| warm HD | | | | |
| warm mały | | | | |

❓ Organizator pyta, czemu pierwsza osoba czekała prawie 2 s. Co odpowiesz i co poprawi ten czas: `min-scale`, szybszy obraz czy optymalizacja renderowania? Czy odpowiedź jest ta sama dla memów HD?

### 8. Z logu do trace'a

```bash
kubectl logs -n memeops -l serving.knative.dev/service=meme-gen -c user-container --tail=5
```

Skopiuj `trace_id` z dowolnej linii `POST`. W Tempo, w zakładce **TraceQL**, wklej sam identyfikator (32 znaki) zamiast zapytania. Otworzy się trace tego żądania: te same `ms` co w logu, plus wszystko, czego log nie widzi (activator, queue-proxy).

👀 Na produkcji logi trafiają do Loki/Elasticsearch, a Grafana robi z `trace_id` link jednym kliknięciem. Mechanizm jest ten sam: identyfikator w logu.

## C. Alert i pętla diagnozy

### 9. Alert jako kod

Przeczytaj `labs/lab09-obserwowalnosc/alert-5xx.json`: zapytanie A to Twoje zapytanie nr 2 z części A, warunek C to próg 5%, `for: 1m` znaczy „przez minutę bez przerwy”.

```bash
g() { curl -s -u admin:memeops -H 'Content-Type: application/json' "$@"; echo; }
g -X POST localhost:3000/api/folders -d '{"uid":"memeops","title":"MemeOps"}'
g -X PUT localhost:3000/api/v1/provisioning/folder/memeops/rule-groups/meme-gen \
  -H 'X-Disable-Provenance: true' -d @labs/lab09-obserwowalnosc/alert-5xx.json
```

Grafana → **Alerting → Alert rules** → folder **MemeOps** → reguła w stanie **Normal**. Nagłówek `X-Disable-Provenance` pozwala edytować regułę w UI. Bez niego Grafana blokuje edycję reguł z API, żeby nikt nie nadpisał w UI tego, co jest w repozytorium.

### 10. Awaria: alert → trace → log → przyczyna

Wdróż „oszczędności” z LAB 8 (limit pamięci 64Mi) i generuj ruch przez 2 min: co trzeci mem HD.

```bash
sed 's/memory: 256Mi/memory: 64Mi/' labs/lab09-obserwowalnosc/meme-gen.yaml | kubectl apply -f -
kubectl wait ksvc/meme-gen -n memeops --for=condition=Ready
for n in $(seq 1 120); do s=1; [ $((n % 3)) -eq 0 ] && s=8
  curl -s -m 5 -o /dev/null -w '%{http_code} ' -XPOST $URL -H "Authorization: Bearer $TOKEN" -d "{\"top\":\"x\",\"scale\":$s}"; sleep 1; done; echo
```

W trakcie obserwuj **Alerting → Alert rules**: Normal → **Pending** → **Firing**. Zapisz, ile minęło od pierwszego 502 do Firing.

Gdy alert jest w stanie Firing, zdiagnozuj przyczynę tylko narzędziami z tego labu:

1. Grafana → Explore → Tempo → `{ span.http.response.status_code >= 500 }` → otwórz trace. Na którym spanie kończy się trace? Czy jest span `render` albo `POST /api/memes` z `meme-gen`?
2. `kubectl logs -n memeops -l serving.knative.dev/service=meme-gen -c user-container --previous --tail=3`: jaka była ostatnia linia przed śmiercią procesu? Czy jest w niej `trace_id` żądania, które zabiło pod?
3. Potwierdź hipotezę jedną komendą (podpowiedź: LAB 8, zgłoszenie 2).

❓ Dlaczego w trace błędu brakuje spanu aplikacji? Co by się stało, gdyby `OTEL_BSP_SCHEDULE_DELAY` miało domyślne 5000 ms, a pod żył jeszcze 3 s po błędzie?

Naprawa:

```bash
kubectl apply -f labs/lab09-obserwowalnosc/meme-gen.yaml
```

Alert wróci do **Normal**, gdy przez minutę nie będzie 5xx (albo gdy nie będzie ruchu: `noDataState: OK`).

## SUKCES

- [ ] tabela czterech zapytań PromQL ma wyniki z Twojego testu k6
- [ ] umiesz wyjaśnić, dlaczego `increase()` zaniża liczbę memów po scale-to-zero
- [ ] w Tempo widzisz jeden trace od `activator` do `render` i masz wypełnioną tabelę cold/warm
- [ ] alert przeszedł Normal → Pending → Firing → Normal, a przyczynę potwierdziłeś trace'em, logiem i jedną komendą

## Dla chętnych

- **Dashboard jako kod.** Dodaj do dashboardu **MemeOps — funkcja Knative** panel *Stat* „Dostępność 15 min” (`1 - 5xx/wszystkie` z `increase(…[15m])`, jednostka *Percent (0.0-1.0)*). Zapisz, wyeksportuj JSON (**Export → Export as JSON**) i porównaj z `setup/monitoring-knative.yaml`. Jak trafiłby do repozytorium i do Grafany bez klikania?
- **Sampling.** Zmień `tracing-sampling-rate` na `0.1` (pamiętaj o restarcie activatora i nowej rewizji funkcji). Wyślij 30 żądań i policz trace'y w Tempo. Czy cold start, który zdarza się raz na 30 żądań, na pewno trafi do próbki? Kiedy sampling „head” (decyzja na początku) przegrywa z „tail” (decyzja w Collectorze po zakończeniu trace'a)?
- **Alert na cichą awarię.** Napisz regułę, która złapałaby zgłoszenia 1 i 3 z LAB 8 (nowa rewizja nie wstaje, ruch idzie na starą). Podpowiedź: `kube-state-metrics` nie zna Knative, ale autoskaler eksportuje `kn_revision_pods_*` dla każdej rewizji.

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| Target health: brak `knative-queue-proxy` | funkcja ma zero podów — wyślij żądanie i odśwież po 5 s |
| PromQL zwraca *No data* | sprawdź etykiety: `service="meme-gen"`, nie `kn_service_name` (to etykieta metryk autoskalera) |
| w Tempo jest tylko `activator` | pod funkcji powstał przed włączeniem tracingu: poczekaj, aż zejdzie do zera, i wyślij nowe żądanie |
| brak spanów `meme-gen` (`render`) | `kubectl get ksvc meme-gen -n memeops -o yaml \| grep -A1 OTEL_EXPORTER`; w logu poda nie ma `trace_id` → obraz bez pakietów OTel (sprawdź `requirements.txt` i przebuduj) |
| `ImportError` / pod nie wstaje po 2.4.0 | `kubectl logs … -c user-container`; najczęściej literówka we wcięciu w `main.py` — uruchom testy z kroku 6 |
| `logs --previous`: `previous terminated container … not found` | normalne dla podów, które się nie restartowały; liczą się linie z poda po OOMKilled |
| `curl` do API Grafany: `401` | hasło `memeops`; przy platformie bez `--monitoring` Grafany nie ma |
| alert od razu Firing albo wcale | `curl -s -u admin:memeops localhost:3000/api/v1/rules/history?ruleUID=meme-gen-5xx` — historia stanów z wartością A |

## Sprzątanie

Reguła alertu i tracing mogą zostać. Gdy chcesz wrócić do stanu sprzed labu:

```bash
curl -s -u admin:memeops -X DELETE localhost:3000/api/v1/provisioning/alert-rules/meme-gen-5xx
kubectl delete -f demo/10-tracing/tracing.yaml
kubectl patch configmap config-observability -n knative-serving --type json -p '[
  {"op":"remove","path":"/data/tracing-protocol"},
  {"op":"remove","path":"/data/tracing-endpoint"},
  {"op":"remove","path":"/data/tracing-sampling-rate"}]'
kubectl -n knative-serving rollout restart deploy/activator
```

## Dogoń grupę

```bash
tools/start-lab.sh lab09
```
