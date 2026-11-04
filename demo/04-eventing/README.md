# 05 — Knative Eventing: mem dnia

**Cel:** zobaczyć funkcję wywoływaną **zdarzeniem**, a nie żądaniem od użytkownika. Nadawca wysyła zdarzenie do brokera i nie wie, kto je odbierze. O tym decydują Triggery.

`Dzień 1 · po LAB 2`

```
PingSource (co minutę) ──┐
curl z poda (ręcznie) ───┴──→ Broker „default” ──→ Trigger (filtr po typie) ──→ funkcja mem-dnia
```

## Przygotowanie

```bash
demo/04-eventing/prepare.sh       # Knative Eventing 1.23 + InMemoryChannel + broker, scenariusz z eventing.yaml, ok. 1,5 min
```

Pierwsze zdarzenie z harmonogramu przychodzi 1–2 min po instalacji, więc uruchom skrypt chwilę wcześniej.

## Kroki

### 1. Co powstało

```bash
kubectl get broker,trigger,pingsource -n demo
kubectl get ksvc mem-dnia -n demo
```

`mem-dnia` to zwykła usługa Knative (obraz `event_display` wypisuje otrzymane zdarzenia). Między zdarzeniami ma zero podów.

### 2. Zdarzenie z harmonogramu

```bash
kubectl get pods -n demo -l serving.knative.dev/service=mem-dnia -w     # pod pojawia się co minutę
kubectl logs -n demo -l serving.knative.dev/service=mem-dnia -c user-container --tail=20
```

Na początku logów są ostrzeżenia o konfiguracji OpenTelemetry. Pomiń je, ważny jest blok `☁️ cloudevents.Event`.

### 3. Własne zdarzenie

```bash
kubectl run -n demo nadawca --image=curlimages/curl:8.17.0 --rm -i --restart=Never --quiet -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST http://broker-ingress.knative-eventing.svc.cluster.local/demo/default \
  -H 'Ce-Id: 1' -H 'Ce-Specversion: 1.0' -H 'Ce-Type: memeops.mem.nowy' -H 'Ce-Source: /uczestnik/ja' \
  -H 'Content-Type: application/json' -d '{"top":"wyslalem zdarzenie","bottom":"a funkcja wstala"}'
```

Zmień `Ce-Type` na `memeops.mem.usuniety` i wyślij jeszcze raz. Broker przyjmie zdarzenie (`202`), ale funkcja go nie dostanie: żaden Trigger nie filtruje tego typu.

## Wynik z próby

```
☁️  cloudevents.Event
Context Attributes,
  specversion: 1.0
  type: dev.knative.sources.ping
  source: /apis/v1/namespaces/demo/pingsources/mem-co-minute
Data,
  { "top": "mem dnia", "bottom": "z harmonogramu" }
```

Zdarzenie `memeops.mem.nowy`: broker odpowiedział `202`, w logach funkcji pojawił się blok z `source: /uczestnik/ja`. Zdarzenie `memeops.mem.usuniety`: `202`, w logach nic.

## Co tu się stało

- **CloudEvents** to standard koperty zdarzenia: `specversion`, `type`, `source`, `id` w nagłówkach `Ce-*`, dane w treści. Para `source` + `id` ma być unikalna dla każdego zdarzenia. Ten sam format obsługują m.in. Knative i Azure Event Grid.
- **Broker** odbiera wszystkie zdarzenia z namespace'u. **Trigger** filtruje je po atrybutach i przekazuje odbiorcy. Nowy odbiorca to nowy Trigger: nadawców nie trzeba zmieniać.
- Odbiorca to zwykła usługa Knative, więc skaluje od zera przy pierwszym zdarzeniu.
- InMemoryChannel trzyma zdarzenia tylko w pamięci i według dokumentacji nie nadaje się na produkcję — tylko na demo. Na produkcji broker na Kafce albo RabbitMQ.

**Wniosek:** HTTP od użytkownika to tylko jedno ze źródeł. Zdarzenia z systemów (harmonogram, kolejka, zmiana w bazie, alarm z sieci) też mogą budzić funkcje i skalować je od zera.

## Sprzątanie

```bash
demo/04-eventing/prepare.sh --delete
```
