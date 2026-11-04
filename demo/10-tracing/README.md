# 10 — Trace cold startu w Tempo

**Cel:** włączyć tracing w Knative jedną ConfigMapą i zobaczyć w trace, gdzie naprawdę idzie czas cold startu. Bez zmian w kodzie funkcji.

```
activator, queue-proxy ──OTLP──→ OTel Collector ──→ Tempo ──→ Grafana
```

## Przygotowanie

Wymaga platformy z `--monitoring` (Grafana).

```bash
kubectl apply -f demo/10-tracing/tracing.yaml
kubectl -n observability rollout status deploy/tempo deploy/otel-collector
```

`tracing.yaml` stawia w namespace `observability`:

| Obiekt | Po co |
|---|---|
| Tempo (Deployment + Service) | baza trace'ów |
| OTel Collector (Deployment + Service + ConfigMap) | odbiera spany od Knative i przekazuje do Tempo |
| ConfigMap `grafana-datasource-tempo` | dodaje Tempo jako źródło danych w Grafanie |

## Kroki

### 1. Collector: jeden adres dla Knative

```bash
kubectl -n observability get configmap otel-collector -o jsonpath='{.data.config\.yaml}'
```

👀 `receivers: otlp` (porty 4317 i 4318) → `exporters: otlp` do `tempo.observability:4317`. Zmiana backendu (Jaeger, Datadog, Azure Monitor) to zmiana tutaj, nie w Knative ani w kodzie.

### 2. Włącz tracing w Knative

```bash
kubectl patch configmap config-observability -n knative-serving --type merge -p '{"data":{
  "tracing-protocol":"http/protobuf",
  "tracing-endpoint":"http://otel-collector.observability:4318/v1/traces",
  "tracing-sampling-rate":"1"}}'
```

| Klucz | Znaczenie |
|---|---|
| `tracing-protocol` | OTLP przez HTTP. Domyślnie `none` — tracing wyłączony |
| `tracing-endpoint` | adres Collectora |
| `tracing-sampling-rate` | `1` = każde żądanie. Tylko na demo; na produkcji 0,01–0,1 |

### 3. Restart activatora

```bash
kubectl -n knative-serving rollout restart deploy/activator
kubectl -n knative-serving rollout status deploy/activator
```

Activator czyta tę konfigurację przy starcie, więc trzeba go zrestartować. `queue-proxy` dostaje ją przy tworzeniu poda — dlatego funkcję wdrażamy dopiero teraz.

### 4. Funkcja

```bash
kubectl apply -f demo/10-tracing/function.yaml
kubectl wait ksvc/meme-trace -n demo --for=condition=Ready
```

`meme-trace` to `meme-api` v1 z krótkim oknem. Odczekaj ok. 30 s, aż zejdzie do zera:

```bash
kubectl get pods -n demo -l serving.knative.dev/service=meme-trace
```

### 5. Cold i warm request

```bash
curl -s -o /dev/null -w 'cold: %{time_total} s\n' "http://meme-trace.demo.127.0.0.1.sslip.io/?top=cold"
curl -s -o /dev/null -w 'warm: %{time_total} s\n' "http://meme-trace.demo.127.0.0.1.sslip.io/?top=cieply"
kubectl -n observability logs deploy/otel-collector --tail=3
```

👀 W logach Collectora linie `Traces … spans` — spany dochodzą.

### 6. Trace w Grafanie

Grafana http://localhost:3000 → **Explore** → źródło **Tempo** → *Search* → posortuj po czasie trwania → najdłuższy trace. Nowe trace'y pojawiają się w wyszukiwarce po 1–2 min.

## Wynik z próby

```
activator  GET                1255.9 ms
activator  throttler_try      1252.4 ms   ← czekanie na pod (scale 0 → 1)
activator  activator_proxy       2.8 ms
meme-trace kn.queueproxy.proxy   1.7 ms
meme-trace HTTP GET              1.6 ms   ← aplikacja
```

Warm request: cały trace 1–15 ms, `throttler_try` 0,2 ms.

## Co tu się stało

- Z 1,26 s cold requestu **1,25 s to czekanie activatora na pod**. Kod aplikacji odpowiadał 1,6 ms. Optymalizacja Pythona nic tu nie da, pomoże `min-scale` albo szybszy start obrazu.
- W trace nie ma spanów z wnętrza aplikacji. To wymaga instrumentacji OpenTelemetry w kodzie. Knative przekazuje nagłówek `traceparent`, więc spany aplikacji dołączą do tego samego trace.
- Metryki mówią, **że** jest wolno. Trace mówi, **gdzie**. Logi z `traceId` mówią, **dlaczego**.

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| w Tempo nic nie ma | `kubectl -n observability logs deploy/otel-collector`: czy dochodzą spany? Odczekaj 2 min |
| w trace jest tylko activator | pod funkcji powstał przed włączeniem tracingu: poczekaj, aż zejdzie do zera, i wyślij nowe żądanie |

## Sprzątanie

```bash
kubectl delete -f demo/10-tracing/function.yaml -f demo/10-tracing/tracing.yaml
kubectl patch configmap config-observability -n knative-serving --type json -p '[
  {"op":"remove","path":"/data/tracing-protocol"},
  {"op":"remove","path":"/data/tracing-endpoint"},
  {"op":"remove","path":"/data/tracing-sampling-rate"}]'
kubectl -n knative-serving rollout restart deploy/activator
```

Patch `--type json` z `remove` usuwa trzy klucze — tracing wraca do domyślnego `none`. Metryki zostają.
