# 09 — Trace cold startu w Tempo

**Cel:** zobaczyć, że Knative sam wysyła trace'y (activator i queue-proxy) bez zmian w kodzie funkcji, i że w jednym trace widać, ile żądanie czekało na pod przy cold starcie.

`Dzień 2 · blok 2.4`

```
activator, queue-proxy ──OTLP──→ OTel Collector ──→ Tempo ──→ Grafana (Explore)
```

## Przygotowanie

Wymaga platformy z `--monitoring` (Grafana).

```bash
demo/10-tracing/prepare.sh       # Tempo 3.1.1 + Collector 0.164.0, tracing w Knative, funkcja meme-trace, ok. 30 s
```

## Kroki

### 1. Wygeneruj trace'y

```bash
kubectl -n demo get kpa                                          # meme-trace: ACTUALSCALE 0 → będzie cold start
curl -s "http://meme-trace.demo.127.0.0.1.sslip.io/?top=cold"
curl -s "http://meme-trace.demo.127.0.0.1.sslip.io/?top=cieply"
```

Tempo pokazuje nowe trace'y w wyszukiwarce po 1–2 min.

### 2. Co jest włączone

```bash
kubectl -n knative-serving get cm config-observability -o yaml | grep '^  tracing'
kubectl -n observability get cm otel-collector -o jsonpath='{.data.config\.yaml}'
kubectl -n observability logs deploy/otel-collector --tail=3
```

Knative zna tylko adres Collectora. Gdzie trafią dane (Tempo, Jaeger, Datadog, Azure Monitor), decyduje konfiguracja Collectora.

### 3. Trace w Grafanie

Grafana http://localhost:3000 → **Explore** → źródło **Tempo** → *Search* → posortuj po czasie trwania → najdłuższy trace.

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
- W trace nie ma spanów z wnętrza aplikacji (zapytanie do bazy, generowanie obrazka). To wymaga instrumentacji OpenTelemetry w kodzie. Knative przekazuje nagłówek `traceparent`, więc spany aplikacji dołączą do tego samego trace.
- Metryki mówią, **że** jest wolno. Trace mówi, **gdzie**. Logi z `traceId` mówią, **dlaczego**.
- Sampling `1` (każde żądanie) jest tylko na demo. Na produkcji 0,01–0,1 albo tail sampling w Collectorze.

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| w Tempo nic nie ma | `kubectl -n observability logs deploy/otel-collector`: czy dochodzą spany? Odczekaj 2 min |
| w trace jest tylko activator | pod funkcji powstał przed włączeniem tracingu: poczekaj, aż zejdzie do zera, i wyślij nowe żądanie |

## Sprzątanie

```bash
demo/10-tracing/prepare.sh --delete      # usuwa Tempo, Collector, funkcję i klucze tracing-*; metryki zostają
```
