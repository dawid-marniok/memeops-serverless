# 04 — Knative Eventing: mem dnia

**Cel:** zobaczyć funkcję wywoływaną **zdarzeniem**, a nie żądaniem od użytkownika. Nadawca wysyła zdarzenie do brokera i nie wie, kto je odbierze. O tym decydują Triggery.

```
PingSource (co minutę) ──┐
curl z poda (ręcznie) ───┴──→ Broker „default” ──→ Trigger (filtr po typie) ──→ funkcja mem-dnia
```

Dwa terminale: **T1** obserwuje, **T2** wykonuje.

## Przygotowanie: instalacja Knative Eventing

Eventing to osobny składnik Knative, w labach go nie ma. Wersja taka sama jak Serving (1.23.0):

```bash
EV=https://github.com/knative/eventing/releases/download/knative-v1.23.0
kubectl apply -f $EV/eventing-crds.yaml         # nowe typy obiektów: Broker, Trigger, PingSource…
kubectl wait crd --all --for=condition=Established --timeout=60s   # czekaj, aż API je zarejestruje
kubectl apply -f $EV/eventing-core.yaml         # kontroler i webhook Eventingu
kubectl apply -f $EV/in-memory-channel.yaml     # kanał w pamięci — tylko na demo
kubectl apply -f $EV/mt-channel-broker.yaml     # implementacja Brokera oparta na kanale
kubectl -n knative-eventing wait deploy --all --for=condition=Available --timeout=300s
kubectl apply -f demo/00-namespace.yaml
```

## Kroki

### 1. Broker

```bash
# T2
cat demo/04-eventing/1-broker.yaml
kubectl apply -f demo/04-eventing/1-broker.yaml
kubectl get broker -n demo
```

👀 Po kilku sekundach `READY True` i `URL` brokera: `http://broker-ingress.knative-eventing.svc.cluster.local/demo/default`. Na ten adres nadawcy wysyłają zdarzenia.

### 2. Odbiorca

```bash
kubectl apply -f demo/04-eventing/2-mem-dnia.yaml
```

`mem-dnia` to zwykła usługa Knative (obraz `event_display` wypisuje w logach każde otrzymane zdarzenie). Między zdarzeniami ma zero podów.

```bash
# T1 — zostaw włączone
kubectl get pods -n demo -l serving.knative.dev/service=mem-dnia -w
```

### 3. Triggery

```bash
cat demo/04-eventing/3-triggery.yaml
kubectl apply -f demo/04-eventing/3-triggery.yaml
kubectl get trigger -n demo
```

Dwa Triggery, oba do `mem-dnia`: `harmonogram` przepuszcza typ `dev.knative.sources.ping`, `nowy-mem` — typ `memeops.mem.nowy`. Żaden nie przepuszcza innych typów.

### 4. Źródło: harmonogram

```bash
kubectl apply -f demo/04-eventing/4-pingsource.yaml
kubectl get pingsource -n demo
```

PingSource co minutę (`* * * * *`, jak w cronie) wysyła zdarzenie do brokera.

👀 W T1 o pełnej minucie pojawia się pod `mem-dnia`, a po kilkunastu sekundach znika.

### 5. Co dostała funkcja

```bash
kubectl logs -n demo -l serving.knative.dev/service=mem-dnia -c user-container --tail=20
```

Logi są tylko póki pod żyje (kilkanaście sekund po zdarzeniu). `No resources found` znaczy, że pod już zniknął: uruchom komendę zaraz po tym, jak w T1 pojawi się nowy pod (o następnej pełnej minucie).

👀 Blok `☁️ cloudevents.Event`: `type: dev.knative.sources.ping`, `source: …/pingsources/mem-co-minute` i dane `{"top": "mem dnia", …}`. Ostrzeżenia o OpenTelemetry na początku logów pomiń.

### 6. Własne zdarzenie

```bash
kubectl run -n demo nadawca --image=curlimages/curl:8.17.0 --rm -i --restart=Never --quiet -- \
  curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  http://broker-ingress.knative-eventing.svc.cluster.local/demo/default \
  -H 'Ce-Id: 1' -H 'Ce-Specversion: 1.0' -H 'Ce-Type: memeops.mem.nowy' -H 'Ce-Source: /uczestnik/ja' \
  -H 'Content-Type: application/json' -d '{"top":"wyslalem zdarzenie","bottom":"a funkcja wstala"}'
```

`kubectl run --rm -i` tworzy jednorazowy pod z `curl` w klastrze (adres brokera działa tylko wewnątrz klastra). Zdarzenie to zwykły POST: nagłówki `Ce-*` to koperta CloudEvents (identyfikator, wersja standardu, typ, nadawca), treść to dane.

👀 `202` — broker przyjął zdarzenie. W T1 wstaje pod, w logach (komenda z kroku 5) blok z `source: /uczestnik/ja`.

Teraz zmień `Ce-Type` na `memeops.mem.usuniety` i wyślij jeszcze raz. 👀 Też `202`, ale funkcja nic nie dostaje: żaden Trigger nie przepuszcza tego typu.

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

Zdarzenie `memeops.mem.nowy`: `202`, w logach blok z `source: /uczestnik/ja`. Zdarzenie `memeops.mem.usuniety`: `202`, w logach nic.

## Co tu się stało

- **CloudEvents** to standard koperty zdarzenia: `specversion`, `type`, `source`, `id` w nagłówkach `Ce-*`, dane w treści. Para `source` + `id` ma być unikalna. Ten sam format obsługują m.in. Knative i Azure Event Grid.
- **Broker** odbiera wszystkie zdarzenia z namespace'u. **Trigger** filtruje je po atrybutach i przekazuje odbiorcy. Nowy odbiorca = nowy Trigger, nadawców nie zmieniasz.
- Odbiorca to zwykła usługa Knative, więc skaluje od zera przy pierwszym zdarzeniu.
- InMemoryChannel trzyma zdarzenia tylko w pamięci — według dokumentacji nie na produkcję. Na produkcji broker na Kafce albo RabbitMQ.

**Wniosek:** HTTP od użytkownika to tylko jedno ze źródeł. Zdarzenia z systemów (harmonogram, kolejka, zmiana w bazie, alarm z sieci) też mogą budzić funkcje.

## Sprzątanie

Po demie (PingSource budzi funkcję co minutę i zaśmieca logi):

```bash
kubectl delete -f demo/04-eventing/4-pingsource.yaml -f demo/04-eventing/3-triggery.yaml \
  -f demo/04-eventing/2-mem-dnia.yaml -f demo/04-eventing/1-broker.yaml
```

Po szkoleniu, cały Eventing (w odwrotnej kolejności niż instalacja):

```bash
EV=https://github.com/knative/eventing/releases/download/knative-v1.23.0
kubectl delete -f $EV/mt-channel-broker.yaml -f $EV/in-memory-channel.yaml -f $EV/eventing-core.yaml
kubectl delete -f $EV/eventing-crds.yaml
```
